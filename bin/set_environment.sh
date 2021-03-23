#!/bin/bash

if [ -z "$env_files" ]; then
  echo "Error. Environment shared root dir not configured. Exiting."
  return 1
fi

source $env_files/tools/oci-tools/bin/config.sh
export os_user=$(getcfg x-ray mw_owner)

# ohs only? take data from node manager.
if [ -z "$os_user" ]; then
  os_user:=$(ps aux | grep weblogic.nodemanager | grep -v grep | cut -f1 -d' ' | sort -u)
  setcfg x-ray mw_owner ${os_user:=undefined} force
fi

if [ -z "$os_user" ]; then
  source $env_files/tools/wls-tools/bin/discover_processes.sh
  discoverWLS
  os_user=$(getWLSjvmAttr ${wls_managed[0]} os_user)
  # admin only?
  : ${os_user:=$(getWLSjvmAttr ${wls_admin[0]} os_user)}

  setcfg x-ray mw_owner ${os_user:=undefined} force
fi

if [ -z "$os_user" ]; then
  echo 'Error. MW owner user not found'
  return 1
fi

source $env_files/tools/oci-tools/bin/config.sh
export env_files=$(getcfg x-ray env_files)
export env=$(getcfg x-ray env)
export component=$(getcfg x-ray component)

if [ -z "$env" ] || [ -z "$component" ]; then
  echo "Error. Environment not configured. Exiting."
  return 1
fi

cat <<EOF
Environment configuration:
env:        $env
component:  $component
mw onwer:   $os_user

env_files:  $env_files
EOF
