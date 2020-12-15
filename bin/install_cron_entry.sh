#!/bin/bash

function install_cron() {
    cmd=$1
    MODULE_NAME=$1
    MODULE_DESC=$2
    MODULE_CRON=$3

    cron_section_start="# START - $MODULE_DESC"
    cron_section_stop="# STOP - $MODULE_DESC"

case $cmd in
add)
    cat >$MODULE_NAME.cron <<EOF
    $cron_section_start
    $MODULE_CRON
    $cron_section_stop
EOF

    (crontab -l 2>/dev/null | 
    sed "/$cron_section_start/,/$cron_section_stop/d"
    cat $MODULE_NAME.cron) | crontab -
    rm $MODULE_NAME.cron
    ;;
    
remove)
    (crontab -l 2>/dev/null | 
    sed "/$cron_section_start/,/$cron_section_stop/d"
    ) | crontab -
    ;;
esac

crontab -l
}

install_cron $@
