#!/bin/bash

#
# TODO
#
# NORMAL add function to get script params. Should enable to write params with new lines, and potential comments. Current list with comma is hard to read.
# NORMAL add mandatory parameters handler
# LOW cache_ttl as one global parameter
# NICE TODO script information
# NICE named_exit verification auto scan
# EXPERIMENTAL Associate with jump host env level ansible user / key

#
# PROGRESS
#

#
# DONE
#
# NORMAL Move generic script steps to external bash file
# HIGH handle envs discovery / envs parameter
# TIP: react on empty answer when not possible
# Generated inventory JSON parsng failed.
# fix look for the instance in proper region
# CRITICAL unset IFS in loops
# CRITICAL always quote response from cache in echo
# NORMAL move region validation to validators lib
# NORMAL add treace handler - set -x
# HIGH Main processing with exit and usage
# HIGH parametrize env ssh key 
# 1. validate parameters
# 6. change fags (set) to yes|no
# adhoc fixed way of caling oci via cache
# 4. check if resource is an instance

script_name='oci2ansible_inventory'
script_version='1.0'
script_by='ryszard.styczynski@oracle.com'

script_args='list,host:'
script_args_persist='tag_ns:,tag_env_list_key:,regions:,envs:,cache_ttl_oci_tag:,cache_ttl_oci_search_instances:,cache_ttl_oci_ocid2vnics:,cache_ttl_oci_ip2instance:,cache_ttl_oci_compute_instance:,cache_ttl_oci_region:'
script_args_system='cfg_id:,temp_dir:,debug,trace,warning:,help,setconfig:,progress_spinner:,validate_params:'

script_cfg='oci2ansible_inventory'

script_libs='config.sh cache.bash JSON.bash validators.bash'
script_tools='oci cat cut tr grep jq'

unset script_args_default
declare -A script_args_default
script_args_default[cfg_id]=$script_cfg
script_args_default[temp_dir]=~/tmp
script_args_default[debug]=no
script_args_default[trace]=no
script_args_default[warning]=yes
script_args_default[validate_params]=yes
script_args_default[progress_spinner]=yes
script_args_default[cache_ttl_oci_region]=43200               # month
script_args_default[cache_ttl_oci_tag]=43200                  # month
script_args_default[cache_ttl_oci_search_instances]=1440      # day
script_args_default[cache_ttl_oci_ocid2vnics]=5184000         # 10 years
script_args_default[cache_ttl_oci_ip2instance]=5184000        # 10 years
script_args_default[cache_ttl_oci_compute_instance]=5184000   # 10 years

unset script_args_validator
declare -A script_args_validator

script_args_validator[cfg_id]=label
script_args_validator[debug]=flag
script_args_validator[help]=flag
script_args_validator[trace]=flag
script_args_validator[temp_dir]=directory_writable
script_args_validator[validate_params]=yesno
script_args_validator[progress_spinner]=yesno
script_args_validator[cache_ttl_oci_region]=integer
script_args_validator[cache_ttl_oci_search_instances]=integer
script_args_validator[cache_ttl_oci_ocid2vnics]=integer
script_args_validator[cache_ttl_oci_ip2instance]=integer
script_args_validator[cache_ttl_oci_compute_instance]=integer
script_args_validator[tag_ns]=word
script_args_validator[tag_env_list_key]=word
script_args_validator[list]=flag
script_args_validator[host]=ip_address
script_args_validator[regions]=oci_lookup_regions

# exit codes
if [ ! -f $(dirname "$0" 2>/dev/null)/named_exit.sh ]; then
  echo "$script_name: Critical error. Required named_exit.sh library not found in script path. Can't continue."
  exit 1
fi
source $(dirname "$0")/named_exit.sh

set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required library not found in script path." 2
set_exit_code_variable "Required tools not available." 3
set_exit_code_variable "Directory not writeable." 4
set_exit_code_variable "Parameter validation failed."  5

set_exit_code_variable "Instance selector not recognised." 10
set_exit_code_variable "Wrong invocation of setconfig." 11
set_exit_code_variable "Generated inventory JSON parsng failed." 12
set_exit_code_variable "Tag with list of environments must be ENUM type." 13

set_exit_code_variable "Configuration saved."  0
set_exit_code_variable "Ansible host completed" 0
set_exit_code_variable "set config completed" 0
set_exit_code_variable "Ansible list completed" 0

# run genercic steps for the script
if [ ! -f $(dirname "$0" 2>/dev/null)/script_generichandler.bash ]; then
  named_exit "Required library not found in script path." script_generichandler.bash
fi
source $(dirname "$0")/script_generic_handler.bash

################################
# actual script code starts here
################################

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
# get data from oci
#

function populate_instances() {
  select_by=$1
  select_value=$2

  unset instances

  case $select_by in
  env)
    env=$select_value

    #IFS=,
    for region in $(echo $regions | tr , ' '); do
        #unset IFS

        cache_ttl=$cache_ttl_oci_search_instances
        cache_group=oci_search_instances
        cache_key=${region}_${tag_ns}_${env}
        oci_search=$(cache.invoke \
        " \
          oci search resource structured-search \
          --region $region \
          --query-text \"query all resources where \
          (definedTags.namespace = '$tag_ns' && definedTags.key = 'ENV' && definedTags.value = '$env')\"
        ")
        
        # TIP: always quote response from cache
        ocids=$(echo "$oci_search" | jq -r '.data.items[]."identifier"')

        for ocid in $ocids; do
          # check if resource is an instance
          # tip: resource type is embeded in the oci on second position
          resource_type=$(echo "$ocid" | cut -d. -f2)
          if [ "$resource_type" != instance ]; then
            WARN "Resource in not an compute instance" $ocid 
            continue
          fi
          
          # get private ip    
          cache_ttl=$cache_ttl_oci_ocid2vnics
          cache_group=oci_ocid2vnics
          cache_key=$ocid
          oci_instance=$(cache.invoke oci compute instance list-vnics --region $region --instance-id $ocid)
          
          private_ip=$(echo "$oci_instance" | jq -r '.data[]."private-ip"')
          if [ -z "$private_ip" ]; then
            # instance w/o provite ip address - rather unsual
            WARN "Instance w/o private ip adress." $ocid 
            continue
          fi

          instances+=($private_ip)
          
          # trick - by putting $ocid in cache with key $private_ip - I'll be to receive $ocid in other  place f the code
          cache_ttl=$cache_ttl_oci_ip2instance
          cache_group=oci_ip2instance
          cache_key=$private_ip
          cache.invoke echo $ocid >/dev/null

        done
      done
    ;;
  *)
    named_exit "Instance selector not recognised." $select_by
    ;;
  esac
}

function populate_instance_variables() {
  local private_ip=$1

  unset instance_variables
  declare -g -A instance_variables

  # get instance ocid by private ip (trick above)
  cache_ttl=$cache_ttl_oci_ip2instance
  cache_group=oci_ip2instance
  cache_key=$private_ip
  instance_ocid=$(cache.invoke get)

  # get compute instance details
  cache_ttl=$cache_ttl_oci_compute_instance
  cache_group=oci_compute_instance
  cache_key=$instance_ocid

  search_region=$(echo "$instance_ocid" | cut -f4 -d.)
  compute_instance=$(cache.invoke oci compute instance get --region "$search_region" --instance-id "$instance_ocid")

  # TIP: react on empty answer when not possible
  if [ -z "$compute_instance" ]; then
    WARN "Cache returned emty answer. Clearing cache and retries." $instance_ocid
    cache.flush oci compute instance get --region "$search_region" --instance-id "$instance_ocid"
    compute_instance=$(cache.invoke oci compute instance get --region "$search_region" --instance-id "$instance_ocid")
  fi

  echo "$compute_instance" | 
  jq ".data.\"defined-tags\".$tag_ns" | 
  tr -d '{}" ,' > $temp_dir/oci_instance.tags


  tags=$(cat $temp_dir/oci_instance.tags | cut -f1 -d:)
  for tag in $tags; do
    instance_variables[$tag]=$(cat $temp_dir/oci_instance.tags | grep "^$tag:"| cut -f2 -d:)
  done

  rm $temp_dir/oci_instance.tags

}
  
function populate_hostgroup_variables() {
  local env=$1

  unset ansible_hostgroup
  declare -g -A ansible_hostgroup
  # ansible_hostgroup=( "${ansible_hostgroup[@]/ansible_ssh_user}" )
  # ansible_hostgroup=( "${ansible_hostgroup[@]/ansible_ssh_private_key_file}" )

  ansible_ssh_user=$(getcfg $script_cfg ${env}_ansible_ssh_user)
  : ${ansible_ssh_user:=$(getcfg $script_cfg ansible_ssh_user)}
  if [ -z "$ansible_ssh_user" ]; then
    WARN "ansible_ssh_user unknown for $env. Specify per env (--setconfig ${env}_ansible_ssh_user=USER) or global one (--setconfig ansible_ssh_user=USER)"
  else
    ansible_hostgroup[ansible_ssh_user]=$ansible_ssh_user
  fi

  ansible_ssh_private_key_file=$(getcfg $script_cfg ${env}_ansible_ssh_private_key_file)
  : ${ansible_ssh_private_key_file:=$(getcfg $script_cfg ansible_ssh_private_key_file)}

  if [ -z "$ansible_ssh_private_key_file" ]; then
    WARN "ansible_ssh_private_key_file unknown for $env. Specify env specific (--setconfig ${env}_ansible_ssh_private_key_file=KEYPATH) or global one (--setconfig ansible_ssh_private_key_file=KEYPATH)"
  else
    ansible_hostgroup[ansible_ssh_private_key_file]=$ansible_ssh_private_key_file
  fi
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

    populate_hostgroup_variables $env
    JSON.map.add ansible_hostgroup vars

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
# start control logic
#
test "$envs" == discover && unset envs
if [ -z "$envs" ]; then
  WARN "envs parameter not specified. Discovering list of environments from tag."
  # discover ENV names via OCI ENUM tag 
  cache_ttl=$cache_ttl_oci_tag
  cache_group=oci_tag
  cache_key=${tag_ns}_${tag_env_list_key}

  oci_tag=$(cache.invoke oci iam tag get --tag-name $tag_env_list_key --tag-namespace-id $tag_ns)
  tag_type=$(echo "$oci_tag" | jq -r '.data.validator."validator-type"')
  if [ "$tag_type" != ENUM ]; then
    named_exit "Error. Tag with list of environments must be ENUM type."
  fi

  envs=$(echo $oci_tag | jq .data.validator.values | tr -d '[]" ,' | grep -v '^$')
fi

#
# execute configuration tasks
#
if [ ! -z "$setconfig" ]; then
  echo $setconfig | grep '=' >/dev/null
  if [ $? -eq 1 ]; then
    named_exit "Wrong invocation of setconfig." $setcfg
  else
    key=$(echo $setconfig | cut -f1 -d=)
    value=$(echo $setconfig | cut -f2 -d=)
    if [ -z "$key" ] || [ -z "$value" ]; then
      named_exit "Wrong invocation of setconfig." $setcfg
    else
      setcfg $script_cfg $key $value force
      named_exit "Configuration saved." $script_cfg
    fi
  fi
  named_exit "set config completed" # never used
fi

#
# execute ansible required tasks
#
if [ "$list" == yes ]; then 
  get_ansible_inventory $envs >/$temp_dir/inventory.json
  jq . /$temp_dir/inventory.json || named_exit "Generated inventory JSON parsng failed."
  rm /$temp_dir/inventory.json

  named_exit "Ansible list completed"
fi

if [ ! -z "$host" ]; then
  get_host_variables $host >/$temp_dir/variables.json
  jq ".\"$host\"" /$temp_dir/variables.json || named_exit "Generated inventory JSON parsng failed."
  rm /$temp_dir/variables.json
  named_exit "Ansible host completed"
fi

# nothing requested? Present how to use the script.
usage
