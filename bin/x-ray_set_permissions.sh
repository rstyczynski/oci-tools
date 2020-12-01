#!/bin/bash

source ~/oci-tools/bin/config.sh


export env_files=$(getcfg x-ray env_files | tr [A-Z] [a-z])
export env=$(getcfg x-ray env | tr [A-Z] [a-z])
export component=$(getcfg x-ray component | tr [A-Z] [a-z])

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

