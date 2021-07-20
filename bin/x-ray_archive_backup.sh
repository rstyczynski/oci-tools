!#/bin/bash

diagname=$1; shift
log=$1; shift
backup_dir=$1; shift
backup_ttl_mins=$1; shift 

function usage() {
  cat <<EOF_usage
Safe delete of old backup files with one more copy in backup location. Tool is part of x-ray diag set.

Usage: x-ray_archive_backup.sh diagname log backup_dir backup_ttl

backup_ttl is number of days
EOF_usage
}

if [ -z $diagname ] || [ -z $log ] || [ -z $backup_dir ] || [ -z $backup_ttl ]; then
  usage
  exit 1
fi

mkdir -p $backup_dir/$(hostname)/archive
timestamp=$(date +"%Y-%m-%dT%H:%M:%SZ%Z")

# convert ttl to minutes
backup_ttl_mins=$(awk -vday_frac=$backup_ttl 'BEGIN{printf "%.0f" ,day_frac * 1440}'); 

# locate files to be removed
find $backup_dir/$(hostname)/source/$diagname-$log-* -type f -mmin +$backup_ttl_mins | egrep "." > $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_backup_progress
find $backup_dir/$(hostname)/expose/$diagname-$log-* -type f -mmin +$backup_ttl_mins | egrep "." >> $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_backup_progress

# transfter files to tar archive, before removal. do not compress to save cpu
tar -cf $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.tar -T $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_backup_progress
if [ $? -eq 0 ]; then
  xargs xargs rm < $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_backup_progress
  result=done
else 
  result=error
fi

# mark archive result in a file with archived file list
mv $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_backup_progress $backup_dir/$(hostname)/archive/$diagname-$log-${timestamp}.purge_backup_$result
