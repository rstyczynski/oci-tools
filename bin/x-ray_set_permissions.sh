#!/bin/bash

env_files=$1
env=$2
component=$3

source ~/oci-tools/bin/config.sh
: ${env_files:=$(getcfg x-ray env_files)}
: ${env:=$(getcfg x-ray env)}
: ${component:=$(getcfg x-ray component)}

if [ -z "$env_files" ] || [ -z "$env" ] || [ -z "$component" ]; then
    echo "Error. Not defined: env_files, env, component. Provide as script parameters or via x-ray.config"
    exit 1
fi

sudo mkdir -p $env_files/backup

sudo mkdir -p $env_files/x-ray/$env
sudo mkdir -p $env_files/x-ray/$env/$component/diag/hosts
sudo mkdir -p $env_files/x-ray/$env/$component/diag/wls/log
sudo mkdir -p $env_files/x-ray/$env/$component/diag/wls/jfr
sudo mkdir -p $env_files/x-ray/$env/$component/diag/wls/dms
sudo mkdir -p $env_files/x-ray/$env/$component/diag/wls/heap
sudo mkdir -p $env_files/x-ray/$env/$component/watch/hosts

sudo chmod 777 $env_files/backup

sudo chmod 777 $env_files/x-ray
sudo chmod 777 $env_files/x-ray/$env

sudo chmod 777 $env_files/x-ray/$env/$component/diag
sudo chmod 777 $env_files/x-ray/$env/$component/diag/hosts
sudo chmod 777 $env_files/x-ray/$env/$component/diag/wls/log 
sudo chmod 777 $env_files/x-ray/$env/$component/diag/wls/jfr 
sudo chmod 777 $env_files/x-ray/$env/$component/diag/wls/dms
sudo chmod 777 $env_files/x-ray/$env/$component/diag/wls/heap
sudo chmod 777 $env_files/x-ray/$env/$component/watch/hosts

component=soa
sudo mkdir -p $env_files/x-ray/$env/$component/diag/wls/alert
sudo chmod 777 $env_files/x-ray/$env/$component/diag/wls/alert
