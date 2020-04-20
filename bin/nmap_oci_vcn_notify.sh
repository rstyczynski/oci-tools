#!/bin/bash

nmap_root=$1
topic_id=$2

function usage() {
    echo "Usage: nmap_oci_vcn_notify nmap_root topic_id"
}

[ -z "$nmap_root" ] && echo "Error. $(usage)" && exit 1
[ -z "$topic_id" ] && echo "Error. $(usage)" && exit 1

echo "Starting nmap_oci_vcn_notify..."

# check OCI commiunication
timeout 30 oci os ns get
if [ $? -ne 0 ]; then
    echo "Error! No access to OCI API."
    exit 1
fi

if [ ! -d $nmap_root/reports ]; then
    echo "Error. Reports directory does not exist."
    exit 1
fi

cd $nmap_root/reports

if [ ! -d .git ]; then
    echo "Error. Reports directory not initialized."
    exit 1
fi

tmp=/tmp/$$
mkdir -p $tmp

declare -A reports_diff
declare -A reports_diff_cnt

for report_name in $(ls *.nmap); do
    # 10 lines of change is ok due to DATE change, more means that file was really modified
    reports_diff[$report_name]="$(git diff HEAD^^ HEAD $report_name)"
    reports_diff_cnt[$report_name]=$(( $(git diff HEAD^^ HEAD $report_name | wc -l) - 10 ))
done

for report_name in ${!reports_diff_cnt[@]}; do

    echo "Processing $report_name..."
    if [ ${reports_diff_cnt[$report_name]} -gt 0 ]; then
        echo ">> detected change in subnet: $report_name."

        alert_title="Detected change in subnet: $report_name."
        alert_body="${reports_diff[$report_name]}"
        timeout 30 oci ons message publish --topic-id $topic_id --body "$alert_body" --title "$alert_title"
    fi 
done

