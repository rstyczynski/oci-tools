#!/bin/bash

function rn() {
    sed 's/null//g'
}

function y2j() {
    python -c "import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))"
}

function schedule_diag_sync() {
    diag_cfg=$1
    cron_action=$2

    : ${diag_cfg:=~/.x-ray/diagnose.yaml}
    : ${cron_action:=create}

    diagname=$(basename $diag_cfg | cut -f1 -d. | cut -f2-999 -d'-')
    if [ "$diagname" == diagnose ]; then
        diagname=general
    fi

    backup_dir=$(cat $diag_cfg | y2j | jq -r ".backup.dir")

    logs=$(cat $diag_cfg | y2j | jq -r ".diagnose | keys[]")

    rm -rf diag_sync.cron
    if [ -f diag_sync.cron ]; then
        echo "Error: cannot delete tmp cron file."
        exit 1
    fi

    cron_section_start="# START - diagnostics source - $diagname"
    cron_section_stop="# STOP - diagnostics source - $diagname"

    if [ "$cron_action" == remove ]; then

        (crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d") | crontab -

        exit 0
    fi

    #
    # prepare cron
    #
    echo "####################################"
    echo "###Preparing cron for $diagname"
    echo "####################################"

    echo $cron_section_start >>diag_sync.cron

    log_no=0
    for log in $logs; do
        log_no=$(($log_cnt + 1))
        echo "##########################################"
        echo "Processing diagnostics source: $diagname/$log"
        echo "##########################################"

        src_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.dir" | rn)

        src_dir_mode=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.mode" | rn)
        : ${src_dir_mode:=default}
        case $src_dir_mode in
        date2date)
            # remove data from src directory. all purge operations are performed one step above date directory
            purge_src_dir=$(dirname "$src_dir")
            ;;
        *)
            purge_src_dir=$src_dir
            ;;
        esac

        type=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.type" | rn)
        : ${type:=log}
        ttl=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.ttl" | rn)
        : ${ttl:=15}
        ttl_filter=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.ttl_filter" | rn)
        : ${ttl_filter:='.'}

        expose_cycle=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.cycle" | rn)
        : ${expose_cycle:="* * * * *"}
        expose_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.dir" | rn)

        # expose only younger than expose_age. Prevents syncing old files.
        expose_age=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.age" | rn)
        : ${expose_age:=1}

        # exspose only files from expose_depth directory depth. Prevents syncing whoe directory structure
        expose_depth=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.depth" | rn)
        : ${expose_depth:=1}

        expose_delete_before=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.delete_before" | rn)
        if [ ! -z "$expose_delete_before" ]; then
            expose_delete_before_cmd="rm -f $expose_dir/$expose_delete_before;"
        else
            unset expose_delete_before_cmd
        fi

        expose_ttl=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.ttl" | rn)
        : ${expose_ttl:=45}
        expose_access=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.access" | rn)
        : ${expose_access:=+r}

        archive_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.dir")

        archive_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.dir" | rn)
        : ${archive_dir:=oci_os://$bucket}
        backup_root=$(cat $diag_cfg | y2j | jq -r ".backup.dir" | rn)
        : ${backup_root:=~/backup}
        archive_cycle=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.cycle" | rn)
        : ${archive_cycle:="1 0 * * *"}
        archive_ttl=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.ttl" | rn)
        : ${archive_ttl:=90}

        # not required here
        #oci_os_bucket=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.dir" | sed 's|oci_os://||')

        # keep diagnose.yaml next to archive file to make archive process be aware of config
        mkdir -p $backup_dir/$(hostname)
        #chmod -r +xw $backup_dir/$(hostname)
        cat $diag_cfg >$backup_dir/$(hostname)/$(basename $diag_cfg)

        #echo "$log, $src_dir, $type, $expose_dir, $expose_cycle, $expose_ttl"

        #
        # rsync files to central location
        #
        perform_rsync=yes
        echo "Source dir: $src_dir"
        echo "Expose dir: $expose_dir"
        if [ "$src_dir" == "$expose_dir" ]; then
            perform_rsync=no
        fi

        # chmod does not work properly on some rsync e.g. 3.0.6; added  umask to fix
        # umask 022 must be added to each cron

        if [ $perform_rsync == yes ]; then

            appendonly=no
            case $type in
            binary) ;;

            logrotate) ;;

            logappend)
                appendonly=yes
                ;;
            *) ;;

            esac

            case $appendonly in
            no)
                cat >>diag_sync.cron <<EOF1

##############
# regular rsync: $log
##############

MAILTO=""
# rsync
$expose_cycle mkdir -p $expose_dir; if [ -f $HOME/tmp/$diagname-$log.files ]; then echo "\$(date +\%Y-\%m-\%dT\%H:\%M:\%S); rsync overload. Skipped this rsync round." >> $expose_dir/rsync.overload; else $expose_delete_before_cmd mkdir -p $HOME/tmp; cd $src_dir; find -maxdepth $expose_depth -mtime -$expose_age -type f > $HOME/tmp/$diagname-$log.files; umask 022; rsync  -t --chmod=Fu=r,Fgo=r,Dgo=rx,Du=rwx --files-from=$HOME/tmp/$diagname-$log.files $src_dir $expose_dir; rm  $HOME/tmp/$diagname-$log.files; fi

EOF1
                ;;

            yes)
                cat >>diag_sync.cron <<EOF2

##############
# append only rsync: $log
##############

MAILTO=""
# rsync
$expose_cycle mkdir -p $expose_dir; if [ -f $HOME/tmp/$diagname-$log.files ]; then echo "\$(date +\%Y-\%m-\%dT\%H:\%M:\%S); rsync overload. Skipped this rsync round." >> $expose_dir/rsync.overload; else $expose_delete_before_cmd mkdir -p $HOME/tmp; cd $src_dir; find -maxdepth $expose_depth -mtime -$expose_age -type f > $HOME/tmp/$diagname-$log.files; umask 022; rsync  -t --append --chmod=Fu=rw,Fgo=r,Dgo=rx --files-from=$HOME/tmp/$diagname-$log.files $src_dir $expose_dir; rm  $HOME/tmp/$diagname-$log.files; fi

EOF2
                ;;
            esac

        else

            cat >>diag_sync.cron <<EOF3

##############
# rsync not necessary as src dir is the same as expose dir. Taking care of chmod only.
##############

MAILTO=""
# chmod to give access to group and others
$expose_cycle chmod go+x${expose_access} $expose_dir; chmod go+${expose_access} $expose_dir/*; 

EOF3
        fi

        #
        # backup, and delete old files
        #


        cat >>diag_sync.cron <<EOF4
# backup, and delete old files
EOF4

        if [ "$ttl" != none ]; then

            # shift archive by a minute for each log entry. Note - will anyway run in parallel for different diag.yaml configs
            minute_shift=$(( $log_no % 60 ))
            echo $ttl | grep '\.' >/dev/null
            if [ $? -eq 0 ]; then
                archive_cycle_cron="$minute_shift */1 * * *"
            else
                archive_cycle_cron="$minute_shift 0 * * *"
            fi

            #convert ttl to minutes
            ttl_mins=$(awk -vday_frac=$ttl 'BEGIN{printf "%.0f" ,day_frac * 1440}'); 

            if [ -z $purge_src_dir ] || [ $purge_src_dir == '/' ] || [ $purge_src_dir == '~' ] || [ $purge_src_dir == "$HOME" ]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "purge_src_dir is empty or points to root / home directory! check configuration."
                exit 1
            fi

            if [[ $backup_dir != */x-ray/* ]]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "backup_dir must contain /x-ray/ subdirectory! check configuration."
                exit 1
            fi

            cat >>diag_sync.cron <<EOF5
MAILTO=""
$archive_cycle_cron timestamp=\$(date +"\%Y-\%m-\%dT\%H:\%M:\%SZ\%Z"); mkdir $backup_dir/$(hostname)/source; mkdir -p $purge_src_dir; find $purge_src_dir -type f -mmin +$ttl_mins | egrep "." > $backup_dir/$(hostname)/source/$diagname-$log-\${timestamp}.archive; tar -czf $backup_dir/source/$(hostname)/$diagname-$log-\${timestamp}.tar.gz -T $backup_dir/source/$(hostname)/$diagname-$log-\${timestamp}.archive; test $? -eq 0 && xargs rm < $backup_dir/$(hostname)/source/$diagname-$log-\${timestamp}.archive; find $purge_src_dir -type d -empty -delete

EOF5
        else
                cat >>diag_sync.cron <<EOF6
# archive skipped by configuration. archive_cycle is none.

EOF6
        fi

        #
        # permamanent delete from expose and backup locations
        #

#         cat >>diag_sync.cron <<EOF8
# # backup, and delete old files from expose and backup locations
# EOF8
#         if [ "$expose_ttl" != none ]; then
#             # shift archive by a minute for each log entry. Note - will anyway run in parallel for different diag.yaml configs
#             minute_shift=$(( $log_no % 60 ))

#             echo $expose_ttl | grep '\.' >/dev/null
#             if [ $? -eq 0 ]; then
#                 purge_cycle_cron="$minute_shift */1 * * *"
#             else
#                 # add hour shift for different logs - it will distribute work a little 
#                 hour_shift=$(( $log_no % 12 ))
#                 purge_cycle_cron="$minute_shift $hour_shift * * *"
#             fi

#             # for expose dir with date, remove date part to operate on all dates
#             expose_dir_no_date=$(echo $expose_dir | sed 's/\/\$todayiso8601//g')
            
#             if [[ $expose_dir_no_date != */x-ray/* ]]; then
#                 echo "ERROR! BRAKING THE PROCEDURE."
#                 echo "ERROR! BRAKING THE PROCEDURE."
#                 echo "ERROR! BRAKING THE PROCEDURE."

#                 echo "expose_dir_no_date must contain /x-ray/ subdirectory! check configuration."
#                 exit 1
#             fi

#             if [[ $backup_dir != */x-ray/* ]]; then
#                 echo "ERROR! BRAKING THE PROCEDURE."
#                 echo "ERROR! BRAKING THE PROCEDURE."
#                 echo "ERROR! BRAKING THE PROCEDURE."

#                 echo "backup_dir must contain /x-ray/ subdirectory! check configuration."
#                 exit 1
#             fi

#             # convert ttl to minutes
#             expose_ttl_mins=$(awk -vday_frac=$expose_ttl 'BEGIN{printf "%.0f" ,day_frac * 1440}'); 

#             cat >>diag_sync.cron <<EOF9
# MAILTO=""
# $purge_cycle_cron 
# mkdir -p $backup_dir/$(hostname)/expose
# timestamp=$(date +"\%Y-\%m-\%dT\%H:\%M:\%SZ\%Z" | tr -d '\')
# find $expose_dir_no_date -type f -mmin +$expose_ttl_mins | egrep "." > $backup_dir/$(hostname)/expose/$diagname-$log-\${timestamp}.purge_expose
# tar -cf $backup_dir/$(hostname)/expose/$diagname-$log-\${timestamp}.tar.gz -T $backup_dir/$(hostname)/expose/$diagname-$log-\${timestamp}.purge_backup
# test $? -eq 0 && xargs rm < $backup_dir/$(hostname)/expose/$diagname-$log-\${timestamp}.purge_expose
# find $expose_dir_no_date -type d -empty -delete

# $purge_cycle_cron timestamp=$(date +"\%Y-\%m-\%dT\%H:\%M:\%SZ\%Z")
# find $backup_dir/$(hostname)/$diagname-$log-* -type f -mmin +$expose_ttl_mins | egrep "." > $backup_dir/$(hostname)/$diagname-$log-\${timestamp}.purge_backup
# find $backup_dir/$(hostname)/expose/$diagname-$log-* -type f -mmin +$expose_ttl_mins | egrep "." >> $backup_dir/$(hostname)/$diagname-$log-\${timestamp}.purge_backup
# xargs rm < $backup_dir/$(hostname)/$diagname-$log-\${timestamp}.purge_backup

# EOF9
#         else
#                 cat >>diag_sync.cron <<EOF10
# # purge skipped by configuration. expose_ttl is none.

# EOF10
#         fi

    # log loop
    done

    echo "#" >>diag_sync.cron
    echo "$cron_section_stop" >>diag_sync.cron

    (
        crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d"
        cat diag_sync.cron
    ) | crontab -

    # cleanup
    rm diag_sync.cron
}

schedule_diag_sync $@
