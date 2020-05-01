#!/bin/bash

nmap_root=$1

function usage() {
    echo "Usage: nmap_oci_vcn_notify nmap_root"
}

[ -z "$nmap_root" ] && echo "Error. $(usage)" && exit 1

if [ ! -d $nmap_root/reports ]; then
    echo "Error. Reports directory does not exist."
    exit 1
fi

cd $nmap_root/reports

for report_name in $(ls *.nmap); do
    echo "Resetting scan report for $report_name..."  
    echo > $report_name

    touch $report_name.reset
done

git add *.nmap
git commit -m "nmap reset scan"
cd - >/dev/null

date
echo Done.