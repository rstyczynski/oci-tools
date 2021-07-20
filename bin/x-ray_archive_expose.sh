#!/bin/bash

diagname=$1; shift
log=$1; shift
expose_dir_no_date=$1; shift
expose_ttl=$1; shift 
backup_dir=$1; shift

function usage() {
  cat <<EOF_usage
Safe delete of old files with copy in backup location. Tool is part of x-ray diag set.

Usage: x-ray_archive_expose.sh diagname log expose_dir_no_date expose_ttl backup_dir

expose_ttl is a day
EOF_usage
}

if [ -z $diagname ] || [ -z $log ] || [ -z $expose_dir_no_date ] || [ -z $expose_ttl ] || [ -z $backup_dir ]; then
  usage
  exit 1
fi

mkdir -p $backup_dir/$(hostname)/expose
timestamp=$(date +"%Y-%m-%dT%H:%M:%SZ%Z" | tr -d '\')

# convert ttl to minutes
expose_ttl_mins=$(awk -vday_frac=$expose_ttl 'BEGIN{printf "%.0f" ,day_frac * 1440}'); 

# locate files to be removed
find $expose_dir_no_date -type f -mmin +$expose_ttl_mins | egrep "." > $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progress

# transfter files to tar backup, before removal. do not compress to save cpu
echo '=========' >  $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
echo 'Tar files' >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
echo '=========' >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
tar -cvf $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.tar -T $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progress >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
if [ $? -eq 0 ]; then
  echo '============' >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
  echo 'Remove files' >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
  echo '============' >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
  if [ -s $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progress ]; then
    xargs rm -v < $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progress >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
  else
    echo 'no files to be removed' >> $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_trace 2>&1
  fi
  result=done
else 
  result=error
fi

# mark archive result in a file with archived file list
mv $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progress $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_$result

# remove empty directories
find $expose_dir_no_date -type d -empty -delete

