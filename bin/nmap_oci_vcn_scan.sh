#!/bin/bash

nmap_root=$1
compartment_id=$2
vcn_cidr=$3
scan_type=$4
scan_only_first_n=$5

function usage() {
    echo "Usage: nmap_oci_vcn_scan compartment_id vcn_cidr ssh|port|full [scan_only_first_n]"
}

[ -z "$nmap_root" ] && echo "Error. $(usage)" && exit 1
[ -z "$compartment_id" ] && echo "Error. $(usage)" && exit 1
[ -z "$vcn_cidr" ] && echo "Error. $(usage)" && exit 1
[ -z "$scan_type" ] && echo "Error. $(usage)" && exit 1
[ -z "$scan_only_first_n" ] && scan_only_first_n=1000

echo "Starting nmap_oci_vcn_scan..."

date

tmp=/tmp/$$
mkdir -p $tmp

# # share with group
# umask 002

if [ ! -d $nmap_root/reports ]; then
    echo "Error. Reports directory does not exist."
    exit 1
fi

# check OCI commiunication
timeout 30 oci os ns get
if [ $? -ne 0 ]; then
    echo "Error! No access to OCI API."
    exit 1
fi

if [ ! -d $nmap_root/reports/.git ]; then
    echo "Initializing reports directory."
    $nmap_root/reports
    git init
    cd - >/dev/null
fi

# get vcn id
oci network vcn list \
    --compartment-id $compartment_id |
    sed 's/-/XXX_XXX/g' |
    jq -r ".data[] | select(.cidrXXX_XXXblock==\"$vcn_cidr\") | .id" |
    sed 's/XXX_XXX/-/g' |
    tee $tmp/vcn_id

# get list of subnets
vcn_id=$(cat $tmp/vcn_id)
oci network subnet list --compartment-id $compartment_id --vcn-id $vcn_id --all |
    sed 's/-/XXX_XXX/g' |
    jq -r .data[].cidrXXX_XXXblock |
    sed 's/XXX_XXX/-/g' |
    tee $tmp/subnet_list

# get reports
for subnet in $(cat $tmp/subnet_list | head -$scan_only_first_n); do

    echo "Scaning $subnet..."
    subnet_report="$(echo $subnet | tr / .)_$scan_type.nmap"
    case $scan_type in
    ssh)
        docker run -w /root kali/nmap nmap --script nmap-vulners -sV -p22 $subnet |
            # clean report
            sed "s/[0-9][0-9]*\.[0-9][0-9]*s /NN.NNs /g" |
            sed "s/[0-9][0-9]*\.[0-9][0-9]* latency /NN latency /g" |
            sed "s/[0-9][0-9]*\.[0-9][0-9]* seconds/NN seconds/g" |
            sed 's/Stats: [0-9][0-9]*:[0-9][0-9]*:[0-9][0-9]* elapsed; [0-9][0-9]* hosts completed ([0-9][0-9]* up)/Stats: HH:MM:SS elapsed; N hosts completed (0 up)/g' |
            sed 's/\w+,\s\d+\s\w+\s\d+\s\d+:\d+:\d+\s\w+/Weekday, Day Month Year, hh:mm:ss TZ/g' | # Wed, 29 Apr 2020 23:04:41 GMT
            grep -v "Stats:" |
            grep -v "Ping Scan Timing:" |
            cat >$nmap_root/reports/$subnet_report
            if [ -f $subnet_report.reset ]; then
                rm -f $report_name.reset
            fi
        ;;
    port)
        docker run -w /root kali/nmap nmap $subnet |
            # clean report
            sed "s/[0-9][0-9]*\.[0-9][0-9]*s /NN.NNs /g" |
            sed "s/[0-9][0-9]*\.[0-9][0-9]* latency /NN latency /g" |
            sed "s/[0-9][0-9]*\.[0-9][0-9]* seconds/NN seconds/g" |
            sed 's/Stats: [0-9][0-9]*:[0-9][0-9]*:[0-9][0-9]* elapsed; [0-9][0-9]* hosts completed ([0-9][0-9]* up)/Stats: HH:MM:SS elapsed; N hosts completed (0 up)/g' |
            sed 's/\w+,\s\d+\s\w+\s\d+\s\d+:\d+:\d+\s\w+/Weekday, Day Month Year, hh:mm:ss TZ/g' | # Wed, 29 Apr 2020 23:04:41 GMT
            grep -v "Stats:" |
            grep -v "Ping Scan Timing:" |
            cat >$nmap_root/reports/$subnet_report
            if [ -f $subnet_report.reset ]; then
                rm -f $report_name.reset
            fi
        ;;

    full)
        docker run -w /root kali/nmap nmap --script nmap-vulners,vulscan --script-args vulscandb=scipvuldb.csv -sV $subnet |
            # clean report
            sed "s/[0-9][0-9]*\.[0-9][0-9]*s /NN.NNs /g" |
            sed "s/[0-9][0-9]*\.[0-9][0-9]* latency /NN latency /g" |
            sed "s/[0-9][0-9]*\.[0-9][0-9]* seconds/NN seconds/g" |
            sed 's/Stats: [0-9][0-9]*:[0-9][0-9]*:[0-9][0-9]* elapsed; [0-9][0-9]* hosts completed ([0-9][0-9]* up)/Stats: HH:MM:SS elapsed; N hosts completed (0 up)/g' |
            grep -v "Stats:" |  
            grep -v "Ping Scan Timing:" | 
            cat >$nmap_root/reports/$subnet_report
            if [ -f $subnet_report.reset ]; then
                rm -f $report_name.reset
            fi
        ;;
    esac

    #TODO check error in pipe's first element
    #     in case of -ne 0 report error      
done

# commit
cd $nmap_root/reports
git add *.nmap
git commit -m "nmap scan type $scan_type"
cd - >/dev/null

rm -rf /tmp/$$

date
echo Done.

