#!/bin/bash

env_files=$(cat /etc/x-ray.config 2>/dev/null | grep env_files | tail -1 | cut -d= -f2)
if [ -z "$env_files" ]; then
  echo "Error. Environment shared root dir not configured. Exiting."
  exit 1
fi

source $env_files/tools/oci-tools/bin/config.sh
export os_user=$(getcfg x-ray mw_owner)

# ohs only? take data from node manager.
: ${os_user:=$(ps aux | grep weblogic.nodemanager | grep -v grep | cut -f1 -d' ' | sort -u)}

if [ -z "$os_user" ]; then
  source $env_files/tools/wls-tools/bin/discover_processes.sh
  discoverWLS
  os_user=$(getWLSjvmAttr ${wls_managed[0]} os_user)
  # admin only?
  : ${os_user:=$(getWLSjvmAttr ${wls_admin[0]} os_user)}
fi

if [ -z "$os_user" ]; then
  echo 'Error. MW owner user not found'
  exit 1
else
  setcfg x-ray mw_owner ${os_user:=undefined} force

fi

source $env_files/tools/oci-tools/bin/config.sh
export env_files=$(getcfg x-ray env_files)
export env=$(getcfg x-ray env)
export component=$(getcfg x-ray component)

if [ -z "$env" ] || [ -z "$component" ]; then
  echo "Error. Environment not configured. Exiting."
  exit 1
fi
