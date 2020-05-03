#!/bin/bash

nmap_root=$1
topic_id=$2

function usage() {
    echo "Usage: nmap_oci_vcn_notify nmap_root topic_id"
}

[ -z "$nmap_root" ] && echo "Error. $(usage)" && exit 1
[ -z "$topic_id" ] && echo "Error. $(usage)" && exit 1

echo "Starting nmap_oci_vcn_notify..."

date

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

if [ ! -d $nmap_root/notified ]; then
    echo "Error. Notification content directory does not exist."
    exit 1
fi

if [ ! -d $nmap_root/reports/.git ]; then
    echo "Error. Reports directory not initialized."
    exit 1
fi

tmp=/tmp/$$
mkdir -p $tmp

# date_now=$(date -u +"%Y%m%dT%H%M%S")

# # share with group
# umask 002

declare -A reports_diff
declare -A reports_diff_cnt

cd $nmap_root/reports
for report_name in $(ls *.nmap); do
    # 10 lines of change is ok due to DATE change, more means that file was really modified
    reports_diff[$report_name]="$(git diff HEAD^ HEAD $report_name)"
    reports_diff_cnt[$report_name]=$(($(git diff HEAD^ HEAD $report_name | wc -l) - 10))
done

for report_name in ${!reports_diff_cnt[@]}; do

    notify=yes
    if [ -f $report_name.reset ]; then
        echo "$report_name. Report after reset. Nothing to send. Invoke scan first."
        notify=no
    else
        if [ -f $report_name.notified ]; then
            diff $report_name $report_name.notified >/dev/null
            if [ $? -eq 0 ]; then
                echo "$report_name. Already notified."
                notify=no
            fi
        fi
    fi

    if [ "$notify" == yes ]; then

        echo -n "Processing $report_name..."
        if [ ${reports_diff_cnt[$report_name]} -gt 0 ]; then
            echo
            echo ">> detected change in subnet: $report_name."

            alert_title="Detected change in subnet: $report_name."
            # copy to notification repository (http exposed)
            # mkdir -p $nmap_root/notified/$date_now
            # cp $report_name $nmap_root/notified/$date_now/$report_name
            # chmod g+r $nmap_root/notified/$date_now
            # chmod g+r $nmap_root/notified/$date_now/$report_name

            # is it first email or following one? For the first, diff is not presented

            if [ ! -f $report_name.notified ]; then

                alert_title="Full scan performed on subnet: $report_name."
                alert_body="Note: This is a full scan report. Starting from next email you will receive list of differences, and the full report.

==================================
==================================
=== Current scan report:
==================================
==================================
$(cat $report_name)
"
            else
                alert_body="Note: change is presented on top. For actual report scroll to \"Current scan report\" section.

==================================
==================================
=== Chanages detected:
==================================
==================================
${reports_diff[$report_name]}

==================================
==================================
=== Current scan report:
==================================
==================================
$(cat $report_name)
"
            fi

            # OCI ONS accepts messages up to 64kB
            # It's required to check if message is not too big, as uch will be not delivered

            chunk_size=$(echo 63*1024 | bc) # 62KB is a max. message size. 1kb left for msg_warning.
            chunk_max=2                     # will deliver up to 2 64kB chunks

            mkdir -p $tmp/split
            echo "$alert_body" >$tmp/split/alert.txt

            split -d -b $chunk_size $tmp/split/alert.txt $tmp/split/alert_chunk

            chunk_cnt=$(find $tmp/split/ -name "alert_chunk*" | wc -l)
            if [ $chunk_cnt -gt 1 ]; then

                msg_warning=''
                chunk_delivery_cnt=$chunk_cnt
                if [ $chunk_cnt -gt $chunk_max ]; then
                    msg_warning="=========
Attention: the message is too big. Only firsst $chunk_max with 64k part(s) will be delivered. Check the report [$nmap_root/reports/$report_name] using different means.
=========
"
                    chunk_delivery_cnt=$chunk_max

                fi

                chunk_no=0
                for msg_chunk_file in $(find $tmp/split/ -name "alert_chunk*" | head -$chunk_delivery_cnt); do
                    chunk_no=$(($chunk_no + 1))

                    alert_chunk_title="$alert_title (${chunk_no}of$chunk_max)"
                    timeout 30 oci ons message publish --topic-id $topic_id --body "$(echo $msg_warning)$(cat $msg_chunk_file)" --title "$alert_chunk_title"
                    notify_result=$?
                done

            else
                timeout 30 oci ons message publish --topic-id $topic_id --body "$alert_body" --title "$alert_title"
                notify_result=$?
            fi

            # clean up split files
            rm -rf $tmp/split

            if [ $notify_result -eq 0 ]; then
                cp $report_name $report_name.notified
            fi
        else
            alert_title="No changes at subnet: $report_name."
            timeout 30 oci ons message publish --topic-id $topic_id --body "No changes." --title "$alert_title"
            notify_result=$?
            if [ $notify_result -eq 0 ]; then
                cp $report_name $report_name.notified
            fi
        fi
    fi
done

cd - >/dev/null

date
echo Done.
