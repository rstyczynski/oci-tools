#!/bin/bash
env_files=$1
env=$2
component=$3
bucket=$4

if [ -z "$env_files" ] || [ -z "$env" ] || [ -z "$component" ] || [ -z "$bucket" ]; then
    echo "Error. Usage: x-ray_set_config.sh env_files, env, component, bucket"
    exit 1
fi

source ~/oci-tools/bin/config.sh
setcfg x-ray env_files $env_files force
setcfg x-ray env $env force
setcfg x-ray component $component force
setcfg x-ray diagnostics $diagnostics force

