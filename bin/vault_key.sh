#!/bin/bash

source $(dirname "$0")/named_exit.sh

# script info
script_name='vault_key'
script_version='1.0'
script_desc='Store and retrieve partner resource key from OCI vault'
script_params="store|retrieve environment partner service username [key_file]"
script_cfg='vault_key'
script_tools='oci jq curl base64 sha384sum cut tr'

# exit codes
set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required tools not available." 2
set_exit_code_variable "Wrong ocid entered." 3
set_exit_code_variable "Wrong operation specified." 4
set_exit_code_variable "Missing required parameters." 5
set_exit_code_variable "No such key found." 6
set_exit_code_variable "OCI reported error."  7

set_exit_code_variable "Uploaded initial version." 0
set_exit_code_variable "Uploaded new version." 0
set_exit_code_variable "The same version already exist in vault." 0

set_exit_code_variable "Key found and retrieved." 0

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

# read configuration
source $script_bin/config.sh
compartment_ocid=$(getcfg $script_cfg compartment_ocid)
vault_ocid=$(getcfg $script_cfg vault_ocid)
key_ocid=$(getcfg $script_cfg key_ocid)

# configure
if [ -z "$compartment_ocid" ] || [ -z "$vault_ocid" ] || [ -z "$key_ocid" ]; then
  echo "Info. Required OCI parameters unknown. Entering configuration."
fi

if [ -z "$compartment_ocid" ]; then
  echo -n "compartment_ocid unknown. Trying to discover..."
  compartment_ocid=$(curl  --connect-timeout 1 -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
  if [ ! -z "$compartment_ocid" ]; then
    echo OK
    setcfg $script_cfg compartment_ocid $compartment_ocid
  else
    echo -n "Discovery failed. "
    compartment_ocid=$(getsetcfg $script_cfg compartment_ocid)
  fi
fi

if [ -z "$vault_ocid" ]; then
  echo "vault_ocid unknown."

  read -p "Enter value for vault_ocid:" vault_ocid

  details=$(oci search resource free-text-search --text "$vault_ocid" | jq '.data.items[]'  | jq "select(.identifier==\"$vault_ocid\")" | jq 'select(."resource-type"=="Vault")')
  if [ -z "$details" ]; then
    echo "Provided vault_ocid is not correct. Exiting."
    unset vault_ocid
    named_exit "Wrong ocid entered."
  else
    setcfg $script_cfg vault_ocid "$vault_ocid" force
  fi
fi

if [ -z "$key_ocid" ]; then
  echo "key_ocid unknown."
  read -p "Enter value for key_ocid:" key_ocid

  details=$(oci search resource free-text-search --text "$key_ocid" | jq '.data.items[]'  | jq "select(.identifier==\"$key_ocid\")" | jq 'select(."resource-type"=="Key")')
  if [ -z "$details" ]; then
    echo "Provided key_ocid is not correct. Exiting."
    unset key_ocid
    named_exit "Wrong ocid entered."
  else
    setcfg $script_cfg key_ocid "$key_ocid" force
  fi
fi

# usage
function usage() {
  echo "Usage: $script_name $script_params"
  echo
  echo $script_desc, version $script_version
}

# check parameters
operation=$1; shift
environment=$1; shift
partner=$1; shift
service=$1; shift
username=$1; shift
key_file=$1; shift

if [ -z $operation ] || [ -z $environment ] || [ -z $partner ] || [ -z $service ] || [ -z $username ]; then
  usage
  named_exit "Missing required parameters."
fi

# set id for the key
secret_name=${environment}_${partner}_${service}_${username}

# discover
>&2 echo "Looking for $secret_name..."
vsid=$(oci vault secret list --compartment-id $compartment_ocid --raw-output --query "data[?\"secret-name\" == '$secret_name'].id" 2>/dev/null | jq -r .[0])

case $operation in
  store)
    if [ -z $key_file ]; then
      usage
      named_exit "Missing required parameters." key_file
    fi

    content_payload=$(base64 --wrap 0 $key_file)
    content_name="access_key"

    if [ -z "$vsid" ]; then
        # create
        >&2 echo "Uploading initial version of $secret_name..."
        oci vault secret create-base64 \
            --compartment-id $compartment_ocid \
            --vault-id $vault_ocid \
            --key-id $key_ocid \
            --secret-content-stage CURRENT \
            --secret-name "$secret_name" \
            --secret-content-content "$content_payload" \
            --secret-content-name "$content_name"
          if [ $? -eq 0 ]; then
            named_exit "Uploaded initial version." 
          else
            named_exit "OCI reported error." $?
          fi
    else
        current_payload_hash=$(oci secrets secret-bundle get --secret-id $vsid | tr - _ | jq -r '.data.secret_bundle_content.content' | base64 -d | sha384sum | cut -f1 -d ' ')
        new_payload_hash=$(echo $content_payload | base64 -d | sha384sum | cut -f1 -d ' ')

        if [ "$new_payload_hash" != "$current_payload_hash" ]; then
            # add new version
             >&2 echo "Uploading new version of $secret_name..."
            oci vault secret update-base64 \
                --secret-id $vsid \
                --secret-content-content "$content_payload"
            if [ $? -eq 0 ]; then
              named_exit "Uploaded new version." 
            else
              named_exit "OCI reported error." $?
            fi
        else
            named_exit "The same version already exist in vault."
        fi
    fi

    ;;
  retrieve)

    if [ -z "$vsid" ]; then
      named_exit "No such key found."
    
    else
      
       >&2 echo "Retrieving $secret_name..."
      if [ -z "$key_file" ]; then
        oci secrets secret-bundle get --secret-id $vsid | tr - _ | jq -r '.data.secret_bundle_content.content' | base64 -d
      else
        oci secrets secret-bundle get --secret-id $vsid | tr - _ | jq -r '.data.secret_bundle_content.content' | base64 -d > $key_file
      fi
      if [ $? -eq 0 ]; then
        named_exit "Key found and retrieved." 
      else
        named_exit "OCI reported error." $?
      fi
    fi
    ;;
  *)
    named_exit "Wrong operation specified." "Allowed: store, retrieve."
    ;;
esac
