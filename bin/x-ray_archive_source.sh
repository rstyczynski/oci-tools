#!/bin/bash

diagname=$1; shift
log=$1; shift
purge_src_dir=$1; shift
ttl=$1; shift 
backup_dir=$1; shift

function usage() {
  cat <<EOF_usage
Safe delete of old files with copy in backup location. Tool is part of x-ray diag set.

Usage: x-ray_archive_source.sh diagname log purge_src_dir ttl backup_dir

expose_ttl is a day
EOF_usage
}

if [ -z $diagname ] || [ -z $log ] || [ -z $purge_src_dir ] || [ -z $ttl ] || [ -z $backup_dir ]; then
  usage
  exit 1
fi

timestamp=$(date +"%Y-%m-%dT%H:%M:%SZ%Z")

mkdir -p $backup_dir/$(hostname)/source
mkdir -p $purge_src_dir

#convert ttl to minutes
ttl_mins=$(awk -vday_frac=$ttl 'BEGIN{printf "%.0f" ,day_frac * 1440}'); 

find $purge_src_dir -type f -mmin +$ttl_mins | egrep "." > $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive

# transfter files to tar backup, before removal. do not compress to save cpu
echo '=========' > $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
echo 'Tar files' >> $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
echo '=========' >> $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
tar -cvf $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.tar -T $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive >> $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
if [ $? -eq 0 ]; then
  echo '============' >> $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
  echo 'Remove files' >> $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
  echo '============' >> $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
  xargs rm -v < $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive >> $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_trace 2>&1
  result=done
else
  result=error
fi

# mark archive result in a file with archived file list
mv $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive_$result

# remove empty directories
find $purge_src_dir -type d -empty -delete
