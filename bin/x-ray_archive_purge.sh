#!/bin/bash

diagname=$1; shift
log=$1; shift
backup_dir=$1; shift
archive_ttl=$1; shift 

function usage() {
  cat <<EOF_usage
Purge of old backup files without backup. It's final operation. Tool is part of x-ray diag set.

Usage: x-ray_archive_purge.sh diagname log backup_dir archive_ttl

archive_ttl is number of days. 
EOF_usage
}

if [ -z $diagname ] || [ -z $log ] || [ -z $backup_dir ] || [ -z $archive_ttl ]; then
  usage
  exit 1
fi

mkdir -p $backup_dir/$(hostname)/archive
timestamp=$(date +"%Y-%m-%dT%H:%M:%SZ%Z")

# convert ttl to minutes
archive_ttl_mins=$(awk -vday_frac=$archive_ttl 'BEGIN{printf "%.0f" ,day_frac * 1440}'); 

# locate old archive files
find $backup_dir/$(hostname)/archive/$diagname-$log-* -type f -mmin +$archive_ttl_mins | egrep "." > $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_progress

# remove old archive files
echo '============' >> $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_trace 2>&1
echo 'Remove files' >> $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_trace 2>&1
echo '============' >> $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_trace 2>&1
if [ -s $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_progress ]; then
  xargs rm -v < $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_progress >> $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_trace 2>&1
else
  echo 'no files to be removed' >> $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_trace 2>&1
fi

# mark process done
mv $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_progress $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_archive_done
