!#/bin/bash

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

mkdir $backup_dir/$(hostname)/source
mkdir -p $purge_src_dir

#convert ttl to minutes
ttl_mins=$(awk -vday_frac=$ttl 'BEGIN{printf "%.0f" ,day_frac * 1440}'); 

find $purge_src_dir -type f -mmin +$ttl_mins | egrep "." > $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive

# transfter files to tar backup, before removal. do not compress to save cpu
tar -cf $backup_dir/source/$(hostname)/$diagname-$log-${timestamp}.tar -T $backup_dir/$(hostname)/source/$diagname-$log-${timestamp}.archive
if $? -eq 0 ]; then
  xargs rm < $backup_dir/$(hostname)/source/$diagname-$log-\${timestamp}.archive
  result=done
else
  result=error
fi

# mark archive result in a file with archived file list
mv $backup_dir/$(hostname)/source/$diagname-$log-\${timestamp}.archive $backup_dir/$(hostname)/source/$diagname-$log-\${timestamp}.archive_$result

# remove empty directories
find $purge_src_dir -type d -empty -delete
