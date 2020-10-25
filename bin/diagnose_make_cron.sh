#!/bin/bash


function rn() {
    sed 's/null//g'
}

function y2j() {
    python -c "import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))"
}


function schedule_diag_sync() {
    diag_cfg=$1

    : ${diag_cfg:=~/.x-ray/diagnose.yaml}

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

    #
    # prepare cron
    #
    echo "####################################"
    echo "###Preparing cron for $diagname"
    echo "####################################"

    cron_section_start="# START - diagnostics source - $diagname"
    cron_section_stop="# STOP - diagnostics source - $diagname"

    echo $cron_section_start >> diag_sync.cron
    cat >> diag_sync.cron <<EOF
#
todayiso8601=$(date -I)
EOF

    for log in $logs; do
        echo "##########################################"
        echo "Processing diagnostics source: $diagname/$log"
        echo "##########################################"

        dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.dir" | rn)
        type=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.type" | rn)
        : ${type:=log}
        ttl=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.ttl" | rn)
        : ${ttl:=15}

        expose_cycle=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.cycle" | rn)
        : ${expose_cycle:="* * * * *"}
        expose_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.dir" | rn)

        expose_age=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.age" | rn)
        : ${expose_age:=1}
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

        case $type in
        log)
            rsync_extra_args="--append"
            ;;
        *)
            unset rsync_extra_args
            ;;
        esac

        # not required here
        #oci_os_bucket=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.archive.dir" | sed 's|oci_os://||')

        # keep diagnose.yaml next to archive file to make archive process be aware of config 
        mkdir -p $backup_dir/$(hostname)
        cat $diag_cfg > $backup_dir/$(hostname)/$(basename $diag_cfg)

        #echo "$log, $dir, $type, $expose_dir, $expose_cycle, $expose_ttl"

        cat >> diag_sync.cron <<EOF

##############
# $log
##############

# rsync
$expose_cycle mkdir -p $expose_dir; rsync -t $rsync_extra_args $dir $expose_dir; chmod -r $expose_access $expose_dir/*

EOF

    cat >> diag_sync.cron <<EOF
# backup, and delete old files
EOF
if [ "$archive_cycle" != none ]; then
    cat >> diag_sync.cron <<EOF
1 0 * * * find -type f -mtime +$ttl $dir > $backup_dir/$(hostname)/$diagname-$log.archive; tar -czf $backup_dir/$(hostname)/$diagname-$log.tar.gz -T $backup_dir/$(hostname)/$diagname-$log.archive
EOF
else
    cat >> diag_sync.cron <<EOF
# blocked by configuration

EOF
fi
    done

    echo "#" >> diag_sync.cron
    echo "$cron_section_stop" >> diag_sync.cron

    (crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d"; cat diag_sync.cron) | crontab -

}


schedule_diag_sync $@
