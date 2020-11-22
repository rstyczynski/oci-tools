#!/bin/bash

function getmwlogs() {
    env_files=$(cat /etc/x-ray.config 2>/dev/null | grep env_files | tail -1 | cut -f2 -d=)
    test -z "$env_files" && read -p "Enter location of mwlogs (defaults to /mwlogs):" env_files
    test -z "$env_files" && env_files=/mwlogs

    env_files=$(echo $env_files | tr -d ' ')
}
getmwlogs
cp -rf --preserve=mode,timestamps $env_files/tools/* ~/

source wls-tools/bin/discover_processes.sh
discoverWLS

function make_jfr_cron() {
    jfr_location="~/x-ray/diag/wls/jfr/$domain_name/$wls_server/\$(date -I)"

    cron_section_start="# START jfr - $wls_server@$domain_name"
    cron_section_stop="# STOP jfr - $wls_server@$domain_name"

    cat >jfr.cron <<EOF
$cron_section_start
*/15 * * * * ~/wls-tools/bin/wls_jfr.sh $wls_server start 890s dump_location $jfr_location
$cron_section_stop
EOF

    (
        crontab -l 2>/dev/null |
            sed "/$cron_section_start/,/$cron_section_stop/d"
        cat jfr.cron
    ) | crontab -
    rm jfr.cron
}

for srvNo in ${!wls_admin[@]}; do
    export wls_server=$(getWLSjvmAttr ${wls_admin[$srvNo]} -Dweblogic.Name)
    export domain_home=$(getWLSjvmAttr ${wls_managed[$srvNo]} -Ddomain.home)
    export domain_name=$(basename $domain_home)

    make_jfr_cron
done

for srvNo in ${!wls_managed[@]}; do
    export wls_server=$(getWLSjvmAttr ${wls_managed[$srvNo]} -Dweblogic.Name)
    export domain_home=$(getWLSjvmAttr ${wls_managed[$srvNo]} -Ddomain.home)
    export domain_name=$(basename $domain_home)

    make_jfr_cron
done
