!#/bin/bash

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
tar -cf $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.tar -T $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progress
if [ $? -eq 0 ]; then 
  xargs rm < $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progress
  result=done
else 
  result=error
fi

# mark archive result in a file with archived file list
mv $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_progres $backup_dir/$(hostname)/expose/$diagname-$log-${timestamp}.purge_expose_$result

# remove empty directories
find $expose_dir_no_date -type d -empty -delete

