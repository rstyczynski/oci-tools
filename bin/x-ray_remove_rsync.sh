#!/bin/bash

source ~/oci-tools/bin/config.sh

export env_files=$(getcfg x-ray env_files | tr [A-Z] [a-z])
export env=$(getcfg x-ray env | tr [A-Z] [a-z])
export component=$(getcfg x-ray component | tr [A-Z] [a-z])

export bucket=$(getcfg x-ray bucket | tr [A-Z] [a-z])

if [ -z "$env_files" ] || [ -z "$env" ] || [ -z "$component" ] || [ -z "$bucket" ]; then
    echo "Error. x-ray.config must has defined: env_files, env, component, bucket"
    exit 1
fi

export todayiso8601="\$(date -I)"
export hostname=$(hostname)

source ~/wls-tools/bin/discover_processes.sh 
discoverWLS

mkdir -p ~/.x-ray

echo "9.  Remove all sync descriptors"
ls -l .x-ray/diagnose-*

for diag in $(ls ~/.x-ray/diagnose-*); do
   echo "Preparing: $diag"
   oci-tools/bin/x-ray_make_cron_diagnose.sh $diag remove
   rm -rf $diag
done
