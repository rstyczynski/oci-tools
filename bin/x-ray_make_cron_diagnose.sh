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

    echo $cron_section_start >> diag_sync.cron

    for log in $logs; do
        echo "##########################################"
        echo "Processing diagnostics source: $diagname/$log"
        echo "##########################################"

        dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.dir" | rn)
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
        cat $diag_cfg > $backup_dir/$(hostname)/$(basename $diag_cfg)

        #echo "$log, $dir, $type, $expose_dir, $expose_cycle, $expose_ttl"


        appendonly=no
        case $type in
            binary)
                ;;
            logrotate)
                ;;
            logappend)
                appendonly=yes
                ;;
            *)
                ;;
        esac


        case $appendonly in
        no)
            cat >> diag_sync.cron <<EOF

##############
# regular rsync: $log
##############

# rsync
$expose_cycle mkdir -p $expose_dir; rsync  -t -h --stats --progress --chmod=Fu=r,Fgo=r,Dgo=rx,Du=rwx --files-from=<(cd $dir; find -maxdepth $expose_depth -mtime -$expose_age -type f) $dir $expose_dir; find $expose_dir/* -type f | xargs sudo chown  --recursive nobody:nobody 

EOF
            ;;

        yes)
            cat >> diag_sync.cron <<EOF

##############
# append only rsync: $log
##############

# rsync
$expose_cycle mkdir -p $expose_dir; rsync  -t -h --stats --progress --append --chmod=Fu=rw,Fgo=r,Dgo=rx --files-from=<(cd $dir; find -maxdepth $expose_depth -mtime -$expose_age -type f) $dir $expose_dir; find $expose_dir/* -type f | xargs sudo chgrp  --recursive nobody 

EOF
            ;;
        esac


    cat >> diag_sync.cron <<EOF
# backup, and delete old files
EOF

if [ "$archive_cycle" != none ]; then
    cat >> diag_sync.cron <<EOF
1 0 * * * find  $dir -type f -mtime +$ttl | egrep "$ttl_filter" > $backup_dir/$(hostname)/$diagname-$log-\$(date -I).archive; tar -czf $backup_dir/$(hostname)/$diagname-$log-\$(date -I).tar.gz -T $backup_dir/$(hostname)/$diagname-$log-\$(date -I).archive; test $? -eq 0 && xargs rm < $backup_dir/$(hostname)/$diagname-$log-\$(date -I).archive 
EOF
else
    cat >> diag_sync.cron <<EOF
# archive skipped by configuration

EOF
fi
    done

    echo "#" >> diag_sync.cron
    echo "$cron_section_stop" >> diag_sync.cron

    (crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d"; cat diag_sync.cron) | crontab -

}


schedule_diag_sync $@
