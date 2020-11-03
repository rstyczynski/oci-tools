#!/bin/bash


function make_cron_jfr() {

    jfr_location="~/x-ray/diagnose/wls/$domain_name/servers/$wls_server/\$(date -I)"

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
}


make_cron_jfr