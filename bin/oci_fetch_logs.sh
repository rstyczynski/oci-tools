#!/bin/bash

#
# script information
#

script_name='oci_fetch_logs'
script_version='1.0'

script_args='data_dir,tmp_dir,time_start:,time_end:,search_query:'
script_args_persist='compartment_ocid:,loggroup_ocid:,log_ocid:'
script_args_system='cfg_id:'

script_cfg='oci_fetch_logs'

script_tools='oci jq cut tr'

# exit codes
source $(dirname "$0")/named_exit.sh

set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required tools not available." 2
set_exit_code_variable "Query execuion error." 3
set_exit_code_variable "OCI client execution faled." 4

#
# Check environment
#

# discover script directory
script_path=$0
test $script_path != '-bash' && script_bin=$(dirname "$0")
test -z "$script_bin" && named_exit "Script bin directory unknown."

# check required tools
unset missing_tools
test ! -f $script_bin/config.sh && missing_tools="config.sh,$missing_tools"

for cli_tool in $script_tools; do
  which $cli_tool > /dev/null 2>/dev/null
  test $? -eq 1 && missing_tools="$cli_tool,$missing_tools"
done

test ! -z "$missing_tools" && named_exit "Required tools not available." "$missing_tools"


#
# read arguments
#

# Parameters are reflected in shell varaibles which are set with parameter value. 
# No value parameters are set to 'set' if exist in cmd line arguents

valid_opts=$(getopt --longoptions "$script_args,$script_args_persist,$script_args_system" -- "$@")
eval set -- "$valid_opts"

while [[ $# -gt 0 ]]; do
  if [ $1 == '--' ]; then
    break
  fi
  var_name=$(echo $1 | cut -b3-999)
  if [[ "$2" != --* ]]; then
    eval $var_name=$2; shift 2
  else
    eval $var_name="set"; shift 1
  fi
done

#
# persist parameters
#

# Persistable configurables are stored in config files. When variable is not specified on cmd level, it is loaded from file. 
# If it's not provided in cmd line, and not available in cfg file, then operator is asked for value. 
# Finally if value is set at cmd line, and is not in config file - it will be persisted.
#
# config file identifier may be specified in cmd line. When not set default name of the script is used.

script_bin=/mwlogs/tools/oci-tools/bin
source $script_bin/config.sh

if [ ! -z "$cfg_id" ]; then
  script_cfg=$cfg_id
fi

# read parameters from cfg file
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  if [ -z ${!cfg_param} ]; then
    eval $cfg_param=$(getcfg $script_cfg $cfg_param)
  fi
done

# set parameters when not set
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  if [ -z ${!cfg_param} ]; then
    echo
    echo "Warning. Required configurble $cfg_param unknown."
    read -p "Enter value for $cfg_param:" $cfg_param
    setcfg $script_cfg $cfg_param ${!cfg_param} force
  fi
done

# persist when not persisted
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  value=$(getcfg $script_cfg $cfg_param)
  if [ -z "$value" ]; then
    setcfg $script_cfg $cfg_param ${!cfg_param} force
  fi
done

#
#
#

#
# check resources
#
: ${tmp_dir:=~/tmp}
: ${data_dir:=.}
mkdir -p $tmp_dir $data_dir

if ! touch $tmp_dir/marker; then
  echo "Error. tmp directory not writable. Exiting"
  return 1
fi
rm -f $tmp_dir/marker

if ! touch $data_dir/marker; then
  echo "Error. Data directory not writable. Exiting"
  return 1
fi
rm -f $data_dir/marker


#
# invoke OCI API
# 

search_query_prefix="search \"$compartment_ocid/$loggroup_ocid/$log_ocid\" | "

## get record count
search_query_suffix="| count"
total_records=$(oci logging-search search-logs --search-query "$search_query_prefix$search_query$search_query_suffix" --time-end $time_end --time-start $time_start | jq -r '.data.results[0].data.count')
OCI_exit_code=${PIPESTATUS[0]}
if [ $OCI_exit_code -ne 0 ]; then
  named_exit "OCI client execution faled."
fi

if [ -z "$total_records" ]; then

  named_exit "Query execuion error."
fi

## get data
search_query_suffix="| sort by datetime asc"

page_size=1000
page_max=$(( ($total_records/$page_size) + ( $total_records % $page_size > 0 ) ))

page_no=1
page=first
until [ "$page" == null ]; do

 if [ $page_no -gt $page_max ]; then
  echo "Error. Trying to fetch more pages than expected. Stopping data fetch."
  break
 fi 

 tmp_file=$tmp_dir/$$\_$(date +%s).json

 case $page in
 first)
    echo Fetching first page of $page_max into $tmp_file...
    oci logging-search search-logs --search-query "$search_query_prefix$search_query$search_query_suffix" --time-end $time_end --time-start $time_start --limit $page_size > $tmp_file
    page=$(jq -r '."opc-next-page"' $tmp_file)
    page_ts=$(jq -r '.data.results[0].data.datetime' $tmp_file)

    data_file=$data_dir/${page_ts}_${page_no}of${page_max}.json
    echo Moving first page of $page_max into $data_file...
    mv $tmp_file $data_file
    ;;
 *)
    data_file=$data_dir/${page_ts}_${page_no}of${page_max}.json
    echo Fetching page $page_no of $page_max into $data_file...
    oci logging-search search-logs --search-query "$search_query_prefix$search_query$search_query_suffix" --time-end $time_end --time-start $time_start --limit $page_size --page $page > $data_file
    page=$(jq -r '."opc-next-page"' $data_file)
    ;;
 esac
 page_no=$(($page_no+1))
done

