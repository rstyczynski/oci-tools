#!/bin/bash

env_files=$(cat /etc/x-ray.config 2>/dev/null | grep env_files | tail -1 | cut -d= -f2)
if [ -z "$env_files" ]; then
  echo "Error. Environment shared root dir not configured. Exiting."
  return 1
fi

source $env_files/tools/oci-tools/bin/config.sh
export mw_owner=$(getcfg fmw mw_owner)

# ohs only? take data from node manager.
if [ -z "$mw_owner" ] || [ "$mw_owner" = undefined ]; then
  mw_owner=$(ps aux | grep weblogic.nodemanager | grep -v grep | cut -f1 -d' ' | sort -u)
  setcfg fmw mw_owner ${mw_owner} force
fi

if [ -z "$mw_owner" ] || [ "$mw_owner" = undefined ]; then
  source $env_files/tools/wls-tools/bin/discover_processes.sh
  discoverWLS
  mw_owner=$(getWLSjvmAttr ${wls_managed[0]} os_user)
  # admin only?
  : ${mw_owner:=$(getWLSjvmAttr ${wls_admin[0]} os_user)}

  setcfg x-ray mw_owner ${mw_owner:=undefined} force
fi
mw_owner=$(getcfg fmw mw_owner)

export domain_home=$(getcfg fmw domain_home)
if [ -z "$domain_home" ] || [ "$domain_home" = undefined ]; then
  source $env_files/tools/wls-tools/bin/discover_processes.sh
  discoverWLS
  domain_home=$(getWLSjvmAttr ${wls_managed[0]} domain_home)
  : ${domain_home:=$(getWLSjvmAttr ${wls_admin[0]} domain_home)}

  setcfg fmw domain_home ${domain_home:=undefined} force
fi
getcfg fmw domain_home
domain_home=$(getcfg fmw domain_home)

if [ -z "$mw_owner" ]; then
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
env:         $env
component:   $component
mw onwer:    $mw_owner
domain_home: $domain_home

env_files:  $env_files
EOF
