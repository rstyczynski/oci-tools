#!/bin/bash

function rn() {
    sed 's/null//g'
}

function y2j() {
    python -c "import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))"
}

function mkdir_force() {
  dst_dir=$1

  mkdir -p $dst_dir 2>/dev/null
  if [ $? -ne 0 ]; then
    parent_dir=$(dirname $dst_dir)
    sudo chmod 777 $parent_dir
  fi

  mkdir -p $dst_dir
  if [ $? -ne 0 ]; then
    echo "Error creating directory."
    return 1
  fi
}

function schedule_diag_sync() {
    diag_cfg=$1
    cron_action=$2
    run_mode=$3

    : ${diag_cfg:=~/.x-ray/diagnose.yaml}
    : ${cron_action:=create}
    : ${run_mode:=TEST}

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

        archive_cycle=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.cycle" | rn)
        : ${archive_cycle:="1 0 * * *"}
        archive_ttl=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.ttl" | rn)
        : ${archive_ttl:=90}

        backup_root=$(cat $diag_cfg | y2j | jq -r ".backup.dir" | rn)
        : ${backup_root:=~/backup}
        backup_ttl=$(cat $diag_cfg | y2j | jq -r ".backup.ttl" | rn)
        : ${backup_ttl:=30}

        # not required here
        #oci_os_bucket=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.dir" | sed 's|oci_os://||')

        # keep diagnose.yaml next to archive file to make archive process be aware of config
	    org_umask=$(umask)
        umask 000
	    
        #mkdir -p $backup_dir/$(hostname)
        mkdir_force $backup_dir/$(hostname)
        umask $org_umask
	    #sudo chmod +x+w+r $backup_dir/$(hostname)
        cat $diag_cfg >$backup_dir/$(hostname)/$(basename $diag_cfg)

        #echo "$log, $src_dir, $type, $expose_dir, $expose_cycle, $expose_ttl"

        if [ ! -d "$src_dir" ]; then
            echo "Error. Source directory does not exist."
            exit 1
        fi

        mkdir_force $expose_dir
        if [ ! -d "$expose_dir" ]; then
            echo "Error. Destination directory does not exist."
            exit 1
        fi

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

                #
                # DO NOT USE % char i cron as ut has special meaning. % must be escaped by \% !!!!
                #

                # TODO: move $HOME/tmp/$diagname-$log.files to $expose_dir/$diagname-$log.inProgress

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
$archive_cycle_cron ~/oci-tools/bin/x-ray_archive_source.sh $diagname $log $purge_src_dir $ttl $backup_dir

EOF5
        else
                cat >>diag_sync.cron <<EOF6
# archive skipped by configuration. archive_cycle is none.

EOF6
        fi

        #
        # permamanent delete from expose and backup locations
        #

        cat >>diag_sync.cron <<EOF8
# purge old files. files will be permanently delted
EOF8
        if [ "$expose_ttl" != none ]; then

            # shift purge start by a minute for each log entry. Note - will anyway run in parallel for different diag.yaml configs
            minute_shift=$(( $log_no % 60 ))

            echo $expose_ttl | grep '\.' >/dev/null
            if [ $? -eq 0 ]; then
                purge_cycle_cron="$minute_shift */1 * * *"
            else
                # add hour shift for different logs - it will distribute work a little 
                hour_shift=$(( $log_no % 12 ))
                purge_cycle_cron="$minute_shift $hour_shift * * *"
            fi

            # for expose dir with date, remove date part to operate on all dates
            expose_dir_no_date=$(echo $expose_dir | sed 's/\/\$todayiso8601//g')
            
            if [[ $expose_dir_no_date != */x-ray/* ]]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "expose_dir_no_date must contain /x-ray/ subdirectory! check configuration."
                exit 1
            fi

            if [[ $backup_dir != */x-ray/* ]]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "backup_dir must contain /x-ray/ subdirectory! check configuration."
                exit 1
            fi

            cat >>diag_sync.cron <<EOF_purge_expose
# Archive old files from expose locations
MAILTO=""
$purge_cycle_cron ~/oci-tools/bin/x-ray_archive_expose.sh $diagname $log $expose_dir_no_date $expose_ttl $backup_dir

EOF_purge_expose

            cat >>diag_sync.cron <<EOF_purge_backup
# Archive old backup files locations (both source backup, and exspose backup).
MAILTO=""
$purge_cycle_cron ~/oci-tools/bin/x-ray_archive_backup.sh $diagname $log $backup_dir $backup_ttl

EOF_purge_backup

#
# purge archive
#
            cat >>diag_sync.cron <<EOF_purge_archive
# purge old archive files 
MAILTO=""
$purge_cycle_cron ~/oci-tools/bin/x-ray_archive_purge.sh $diagname $log $backup_dir $archive_ttl

EOF_purge_archive

        else
                cat >>diag_sync.cron <<EOF_purge_final
# purge skipped by configuration. expose_ttl is none.

EOF_purge_final

        fi

    # log loop
    done

    echo "#" >>diag_sync.cron
    echo "$cron_section_stop" >>diag_sync.cron


    if [ $run_mode == DEPLOY ]; then
        # 
        # update crontab
        #

        (
            crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d"
            cat diag_sync.cron
        ) | crontab -

        #
        # cleanup
        #
        rm diag_sync.cron
    else
        cat diag_sync.cron
    fi
}

# 1 - diag name
# 2 - action: create
# 3 - test run: yes | no
schedule_diag_sync $@
