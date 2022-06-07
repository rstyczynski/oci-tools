#!/bin/bash

# TODO
# 2. parametrize env ssh key 
# 3. handle envs discovery / envs parameter
# 4. check if resource is an instance

# DONE
# 1. validate parameters

script_name='oci2ansible_inventory'
script_version='1.0'
script_by='ryszard.styczynski@oracle.com'

script_args='list,host:,progress_spinner:,validate_params:'
script_args_persist='tag_ns:,tag_env_list_key:,regions:,envs:,cache_ttl_tag2values:,cache_ttl_search_instances:,cache_ttl_ocid2vnics:,cache_ttl_ip2instance:,cache_ttl_region:'
script_args_system='cfg_id:,temp_dir:,debug,help'

declare -A script_args_default
script_args_default[cache_ttl_region]=43200          # month
script_args_default[cache_ttl_tag2values]=43200      # month
script_args_default[cache_ttl_search_instances]=1440 # day
script_args_default[cache_ttl_ocid2vnics]=5184000    # 10 years
script_args_default[cache_ttl_ip2instance]=5184000   # 10 years
script_args_default[temp_dir]=~/tmp
script_args_default[progress_spinner]=yes
script_args_default[validate_params]=yes

declare -A script_args_validator
script_args_validator[validate_params]=yesno
script_args_validator[progress_spinner]=yesno
script_args_validator[cache_ttl_region]=integer
script_args_validator[cache_ttl_search_instances]=integer
script_args_validator[cache_ttl_ocid2vnics]=integer
script_args_validator[cache_ttl_ip2instance]=integer
script_args_validator[temp_dir]=directory_writable
script_args_validator[tag_ns]=word
script_args_validator[tag_env_list_key]=word
script_args_validator[regions]=labels
script_args_validator[cfg_id]=label
script_args_validator[debug]=flag
script_args_validator[help]=flag
script_args_validator[list]=flag
script_args_validator[host]=ip_address

script_cfg='oci2ansible_inventory'

script_libs='config.sh cache.bash JSON.bash validators.bash'
script_tools='oci cat cut tr grep jq'

# exit codes
if [ ! -f $(dirname "$0")/named_exit.sh ]; then
  echo "$script_name: Critical error. Required library not found in script path. Can't continue."
  exit 1
fi

source $(dirname "$0")/named_exit.sh

set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required tools not available." 2
set_exit_code_variable "Directory not writeable." 3

set_exit_code_variable "Instance w/o private ip adress." 4
set_exit_code_variable "Instance selector not recognised." 5
set_exit_code_variable "Parameter validation failed."  6

#
# Check environment
#

# discover script directory
script_path=$0
test $script_path != '-bash' && script_bin=$(dirname "$0")
test -z "$script_bin" && named_exit "Script bin directory unknown."

# check required libs
unset missing_tools
for script_lib in $script_libs; do
  test ! -f $script_bin/$script_lib && missing_tools="$script_lib,$missing_tools"
done

# check required tools
for cli_tool in $script_tools; do
  which $cli_tool > /dev/null 2>/dev/null
  test $? -eq 1 && missing_tools="$cli_tool,$missing_tools"
done

missing_tools=$(echo $missing_tools | sed 's/,$//')
test ! -z "$missing_tools" && named_exit "Required tools not available." "$missing_tools"

#
# load libraries
#
for script_lib in $script_libs; do
  source $script_bin/$script_lib 2>/dev/null
done

#
# read arguments
#

# Parameters are reflected in shell varaibles which are set with parameter value. 
# No value parameters are set to 'set' if exist in cmd line arguents

# clean params to avoid exported ones
for cfg_param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , ' ' | tr -d :); do
  unset $cfg_param
done

#
# set default values
#

for variable in ${!script_args_default[@]}; do
  eval $variable=${script_args_default[$variable]}
done

valid_opts=$(getopt --longoptions "$script_args,$script_args_persist,$script_args_system" --options "" --name "$script_name" -- $@)
eval set --"$valid_opts"

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
# set config source
#

if [ ! -z "$cfg_id" ]; then
  script_cfg=$cfg_id
fi


#
# script info
#
function about() {
  echo "$script_name, $script_version by $script_by" 
}

function usage() {
  echo
  echo -n "Usage: $script_name" 
  for param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , ' ' | tr -d :); do
    echo -n " --$param"
  done
  echo

  echo 
  echo 'Argument formats:'
  if [ ${#script_args_validator[@]} -gt 0 ];then
    for variable in ${!script_args_validator[@]}; do
      echo " \-$variable: ${script_args_validator[$variable]}"
    done
  else
    echo '(none)'
  fi

  echo 
  echo 'Default values:'
  if [ ${#script_args_default[@]} -gt 0 ];then
    for variable in ${!script_args_default[@]}; do
      echo " \-$variable: ${script_args_default[$variable]}"
    done
  else
    echo '(none)'
  fi

  if [ ${#script_args_default[@]} -gt 0 ];then
    echo
    echo "Persisted values (config: $script_cfg)":
    persistent=none
    for variable in $(echo $script_args_persist | tr , ' ' | tr -d :); do
      var_value=$(getcfg $script_cfg $variable)
      if [ ! -z "$var_value" ]; then
        echo " \-$variable: $var_value"
        persistent=$persistent,$variable
      fi
    done
    if [ $persistent == none ]; then
      echo '(none)'
    fi
  fi
}

#
# start
#
about >&2

if [ "$help" == set ]; then
  usage >&2
  exit 0
fi


#
# read parameters from config file
#

# read parameters from cfg file
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  if [ -z ${!cfg_param} ]; then
    eval $cfg_param=$(getcfg $script_cfg $cfg_param)
  fi
done

#
# validate. validate params even from config file, as it's possible thet it was edited manually
#

if [ $validate_params == yes ]; then
  for param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , ' ' | tr -d :); do
      validators_validate $param
      if [ $? -ne 0 ]; then
        named_exit "Parameter validation failed." ${!param}
      fi 
  done
fi


#
# persist parameters
#

# Persistable configurables are stored in config files. When variable is not specified on cmd level, it is loaded from file. 
# If it's not provided in cmd line, and not available in cfg file, then operator is asked for value. 
# Finally if value is set at cmd line, and is not in config file - it will be persisted.
#
# config file identifier may be specified in cmd line. When not set default name of the script is used.

# set parameters when not set
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  if [ -z ${!cfg_param} ]; then
    echo
    echo "Warning. Required configurable $cfg_param unknown."
    read -p "Enter value for $cfg_param:" $cfg_param
    
    validators_validate $cfg_param
    if [ $? -ne 0 ]; then
      named_exit "Parameter validation failed." $cfg_param
    fi 

    setcfg $script_cfg $cfg_param ${!cfg_param} force
  fi
done

# persist when not persisted. All data is already validated.
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  value=$(getcfg $script_cfg $cfg_param)
  if [ -z "$value" ]; then
    setcfg $script_cfg $cfg_param ${!cfg_param} force
  fi
done

#
# proccess parameters
#

# data and temp directories
if ! touch $temp_dir/marker; then
  named_exit "Directory not writeable." $temp_dir
fi
rm -f $temp_dir/marker


cache_progress=$progress_spinner

#
# actual script code starts here
#

#
# get data from oci
#

function populate_instances() {
  select_by=$1
  select_value=$2

  unset instances

  case $select_by in
  env)
    env=$select_value

    for region in $regions; do

        cache_ttl=$cache_ttl_search_instances
        cache_group=search_instances
        cache_key=${region}_${env}

        ocids=$(
          cache.invoke " \
          oci search resource structured-search \
          --region $region \
          --query-text \"query all resources where \
          (definedTags.namespace = '$tag_ns' && definedTags.key = 'ENV' && definedTags.value = '$env')\"
          " | 
          jq -r '.data.items[]."identifier"')

        for ocid in $ocids; do
          # TODO: check if resource is an instance

          # get private ip    
          cache_ttl=$cache_ttl_ocid2vnics
          cache_group=ocid2vnics
          cache_key=$ocid

          private_ip=$(cache.invoke oci compute instance list-vnics \
          --region $region --instance-id $ocid | 
          jq -r '.data[]."private-ip"')
          
          if [ -z "$private_ip" ]; then
            echo "Error. private ip empty. Can't continue."
            named_exit "Instance w/o private ip adress." $ocid
          fi

          instances+=($private_ip)

        done
      done

    ;;
  *)
    named_exit "Instance selector not recognised." $select_by
    ;;
  esac
}

function populate_instance_variables() {
  private_ip=$1

  unset instance_variables
  declare -g -A instance_variables

  # get tags
  cache_group=ip2instance
  cache_key=$private_ip

  # get tags
  cache_ttl=$cache_ttl_ip2instance
  cache_group=ip2instance
  cache_key=$private_ip

  cache.invoke oci compute instance get \
  --region $region --instance-id $ocid | 
  jq ".data.\"defined-tags\".$tag_ns" | tr -d '{}" ,' | tr ':' '=' > $temp_dir/oci_instance.tags

  source $temp_dir/oci_instance.tags

  tags=$(cat $temp_dir/oci_instance.tags | cut -f1 -d=)
  for tag in $tags; do
    instance_variables[$tag]=${!tag}
  done

  rm $temp_dir/oci_instance.tags

}
  

#
# inventory formatter
#

function get_ansible_inventory() {

  envs=$@

  JSON.init

  for host_group in $envs; do
    JSON.object.init $host_group

    populate_instances env $host_group
    JSON.array.add instances hosts

    declare -A ansible_user
    ansible_user[ansible_ssh_user]=pmaker
    ansible_user[ansible_ssh_private_key_file]=/home/pmaker/.ssh/dev_id_rsa
    JSON.map.add ansible_user vars

    JSON.object.close $host_group
  done

  JSON.object.init _meta
  JSON.object.init hostvars

  for host_group in $envs; do
    populate_instances env $host_group
    for instance in ${instances[@]}; do
      populate_instance_variables $instance
      JSON.map.add instance_variables $instance
    done
  done
  
  JSON.object.close
  JSON.object.close

  JSON.close
}

function get_host_variables() {
  instance=$1

  JSON.init

  populate_instance_variables $instance
  JSON.map.add instance_variables $instance

  JSON.close
}

#
#
#

#verify region
for region in $regions; do
  cache_ttl=$cache_ttl_region
  cache_group=region
  cache_key=regions
  region_name=$(cache.invoke oci iam region list | jq -r ".data[] | select(.name==\"$region\") | .name")
  if [ "$region" != "$region_name" ]; then
    echo "No such region: $region"
  fi
done

# discover ENV names via OCI ENUM tag 
cache_ttl=$cache_ttl_tag2values
cache_group=tag2values
cache_key=${tag_ns}_${tag_env_list_key}

tag_type=$(cache.invoke oci iam tag get --tag-name $tag_env_list_key --tag-namespace-id $tag_ns | 
jq -r '.data.validator."validator-type"')
if [ "$tag_type" != ENUM ]; then
  #TODO: add named exit
  echo "Error. Tag with list of environments must be ENUM type. Exiting."
  exit 1
fi

envs=$(cache.invoke oci iam tag get --tag-name $tag_env_list_key --tag-namespace-id $tag_ns | 
jq .data.validator.values | tr -d '[]" ,' | grep -v '^$')

# execute ansible required tasks
test ! -z "$list" && get_ansible_inventory $envs | jq
test ! -z "$host" && get_host_variables $host | jq ".\"$host\""