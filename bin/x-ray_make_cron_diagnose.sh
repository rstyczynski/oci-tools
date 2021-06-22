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

    for log in $logs; do
        echo "##########################################"
        echo "Processing diagnostics source: $diagname/$log"
        echo "##########################################"

        src_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.dir" | rn)

        src_dir_mode=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.mode" | rn)
        : ${src_dir_mode:=default}
        case $src_dir_mode in
        date2date)
            # remove data from src directory. all purge operations are performed one step above date directory
            purge_src_dir=$(dirname $src_dir)
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
        cat $diag_cfg >$backup_dir/$(hostname)/$(basename $diag_cfg)

        #echo "$log, $src_dir, $type, $expose_dir, $expose_cycle, $expose_ttl"

        #
        # rsync files to central location
        #
        perform_rsync=yes
        if [ $src_dir == $expose_dir ]; then
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
                cat >>diag_sync.cron <<EOF

##############
# regular rsync: $log
##############

MAILTO=""
# rsync
$expose_cycle mkdir -p $expose_dir; $expose_delete_before_cmd mkdir -p $HOME/tmp; cd $src_dir; find -maxdepth $expose_depth -mtime -$expose_age -type f > $HOME/tmp/$diagname-$log.files; umask 022; rsync  -t --chmod=Fu=r,Fgo=r,Dgo=rx,Du=rwx --files-from=$HOME/tmp/$diagname-$log.files $src_dir $expose_dir; rm  $HOME/tmp/$diagname-$log.files

EOF
                ;;

            yes)
                cat >>diag_sync.cron <<EOF

##############
# append only rsync: $log
##############

MAILTO=""
# rsync
$expose_cycle mkdir -p $expose_dir; $expose_delete_before_cmd mkdir -p $HOME/tmp; cd $src_dir; find -maxdepth $expose_depth -mtime -$expose_age -type f > $HOME/tmp/$diagname-$log.files; umask 022; rsync  -t --append --chmod=Fu=rw,Fgo=r,Dgo=rx --files-from=$HOME/tmp/$diagname-$log.files $src_dir $expose_dir; rm  $HOME/tmp/$diagname-$log.files

EOF
                ;;
            esac

        else

            cat >>diag_sync.cron <<EOF

##############
# rsync not necessary as src dir is the same as expose dir. Taking care of chmod only.
##############

MAILTO=""
# chmod to give access to group and others
$expose_cycle chmod go+x${expose_access} $expose_dir; chmod go+${expose_access} $expose_dir/*; 

EOF        
        fi

# #
# # backup, and delete old files
# #
#         if [ "$perform_rsync" == yes ]; then

#             cat >>diag_sync.cron <<EOF
# # backup, and delete old files
# EOF

#             if [ "$archive_cycle" != none ]; then
#                 cat >>diag_sync.cron <<EOF
# MAILTO=""
# # 05.05.2021 rstyczynski mkdir -p \$purge_src_dir added as it may not exist in the moment on archive, what blocks find from locating old files
# 1 0 * * * mkdir -p $purge_src_dir; find $purge_src_dir -type f -mtime +$ttl | egrep "$ttl_filter" > $backup_dir/$(hostname)/$diagname-$log-\$(date -I).archive; tar -czf $backup_dir/$(hostname)/$diagname-$log-\$(date -I).tar.gz -T $backup_dir/$(hostname)/$diagname-$log-\$(date -I).archive; test \$? -eq 0 && xargs rm < $backup_dir/$(hostname)/$diagname-$log-\$(date -I).archive; find $purge_src_dir -type d -empty -delete 
# EOF
#             else
#                 cat >>diag_sync.cron <<EOF
# # archive skipped by configuration. archive_cycle is none.

# EOF
#             fi
#             else
#             cat >>diag_sync.cron <<EOF
# # archive skipped by configuration. files are stored in expose dir.

# EOF
#         fi

    done

    echo "#" >>diag_sync.cron
    echo "$cron_section_stop" >>diag_sync.cron

    (
        crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d"
        cat diag_sync.cron
    ) | crontab -

}

schedule_diag_sync $@
