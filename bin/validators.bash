#!/bin/bash

#
# TODO
#
# List of words, labels, etc. always separated by , w/o spaces

#
# PROGRESS
#
# CRITICAL unset IFS in loops

#
# DONE
#
# Mark function level variables as local
# NORMAL add cahce for on-line services

#
# debug handler
#

function validator_DEBUG() {
  if [ "$validator_debug" == yes ]; then
    echo $@ >&2
  fi
}

function validator_WARN() {
  if [ "$validator_warining" == yes ]; then
    echo $@ >&2
  fi
}

# 
# init code
#
: ${validator_warining:=yes}
: ${validator_usecache:=yes}

if [ "$validator_usecache" == yes ]; then
  cache.invoke >/dev/null 2>/dev/null
  if [ $? -eq 127 ]; then
    validator_usecache=no
    WARN "cache.bash not available. To use cache source cache.bash firs."
  fi
fi

#
# validators info
#

unset validator_info
declare -A validator_info

validator_info[yesno]='yes|no'
validator_info[integer]='integer'
#TODO extend this list

#
# validators
#

function validator_yesno() {
  local value=$(echo $1 | tr '[A-Z]' '[a-z]')

  case $value in
  yes)  return 0;;
  no)   return 0;;
  *)    return 1;;
  esac
}

function validator_integer() {
  local value=$1

  # https://stackoverflow.com/questions/806906/how-do-i-test-if-a-variable-is-a-number-in-bash
  re='^[0-9]+$'
  if ! [[ $value =~ $re ]] ; then
    return 1
  fi
}

function validator_word() {
  local value=$1

  re='^[a-zA-Z0-9_]+$'
  if ! [[ $value =~ $re ]] ; then
    return 1
  fi
}

function validator_words() {
  local value=$1

  re='^[ a-zA-Z0-9_]+$'
  if ! [[ $value =~ $re ]] ; then
    return 1
  fi
}

function validator_label() {
  local value=$1

  re='^[a-zA-Z0-9_-]+$'
  if ! [[ $value =~ $re ]] ; then
    return 1
  fi
}

function validator_labels() {
  local value=$1

  # hyphen at the end: https://stackoverflow.com/questions/55377810/bash-regex-with-hyphen-and-dot
  re='^[ a-zA-Z0-9_-]+$'
  if ! [[ $value =~ $re ]] ; then
    return 1
  fi
}

function validator_flag() {
  local value=$1

  test -z "$value" && return 0
  test "$value" == set && return 0
  test "$value" == yes && return 0
  test "$value" == no && return 0
  return 1
}

function validator_directory_writable() {
  local dir=$1

  test ! -d  $dir && return 1
  touch $dir/marker
  test $? -ne 0  && return 1
  rm -f $dir/marker
}


function validator_ip_address() {
  local ip_address=$1

  >&2 python3 <<EOF
import ipaddress

try:
  ipaddress.ip_address("$ip_address")
except Exception as ex:
  print(ex)
  exit(1)
EOF
  return $?
}

# on-line
function validator_tcp_service_reachable() {
  local ip_address=$(echo $1 | cut -d: -f1)
  local ip_address_port=$(echo $1 | cut -d: -f2)

  : ${validator_tcp_service_reachable_timeout:=5}

 >&2 python3 << EOF
import socket  

try:
  s=socket.socket()  
  s.settimeout($validator_tcp_service_reachable_timeout)
  s.connect(("$ip_address",$ip_address_port))
  s.close()
  exit(0)
except Exception as ex:
  print(ex)
  exit(1)
EOF
  return $?
}

# on-line
function validator_ip_address_reachable() {
  local ip_address=$1

  : ${validator_ip_address_reachable_timeout:=5}

  timeout $validator_ip_address_reachable_timeout ping -c1 $ip_address >/dev/null 2>&1 
  ping_status=$?
  [ "$ping_status" -ne 0 ] && >&2 echo "Host does not respond to ICMP."

  return $ping_status
}

function validator_ip_network() {
  local ip_address=$1

  >&2 python3 <<EOF
import ipaddress

try:
  ipaddress.ip_network(unicode("$ip_address"))
except Exception as ex:
  print(ex)
  exit(1)
EOF
  return $?
}

function validator_oci_format_ocid() {
  local resource_ocid=$1
  local resource_type=$2

  : ${resource_type:=^[a-z]+}

  unset validator_oci_format_ocid_error
  declare -gA validator_oci_format_ocid_error

  IFS=. read ocid_ver oci_resource_type oci_realm oci_region id_a id_bid_c <<< $resource_ocid
  unset IFS

  # https://docs.oracle.com/en-us/iaas/Content/General/Concepts/identifiers.htm

  exit_code=0
  [[ "$ocid_ver" =~ ^ocid[0-9]+ ]]; validator_oci_format_ocid_error[0]=$?
  [[ "$oci_resource_type" =~ $resource_type ]]; validator_oci_format_ocid_error[1]=$?
  [[ "$oci_realm" =~ ^oc[0-9]+ ]]; validator_oci_format_ocid_error[2]=$?

  if [ -z "$oci_region" ]; then
    validator_oci_format_ocid_error[3]=0
  else
    [[ "$oci_region" =~ ^[a-z0-9\-]+ ]]; validator_oci_format_ocid_error[3]=$?
  fi

  ocid_resource_id=$id_a.$id_b.$id_c
  [[ "$ocid_resource_id" =~ ^[a-z0-9\.]+ ]]; validator_oci_format_ocid_error[4]=$?

  for element in ${!validator_oci_format_ocid_error[@]}; do
    [ ${validator_oci_format_ocid_error[$element]} -eq 1 ] && exit_code=1
  done

  return $exit_code
}

function validator_oci_format_ocid_compartment() {
  validator_oci_format_ocid $1 compartment
  return $?
}

function validator_oci_format_ocid_tenancy() {
  validator_oci_format_ocid $1 tenancy
  return $?
}

# on-line
function validator_oci_lookup_ocid() {
  ocid=$1

  region=$(echo $ocid | cut -f2 -d.)

  if [ "$validator_usecache" == yes]; then
    cache_ttl=$cache_ttl_oci_ocid_search
    cache_group=oci_ocid
    cache_key=$ocid
    oci_ocid_search=$(cache.invoke "oci search -region $region resource free-text-search --text \"$ocid\"")
  else
    oci_ocid_search=$(oci search -region $region resource free-text-search --text "$ocid")
  fi

  echo $oci_ocid_search | jq '.data.items[]'  | 
  jq "select(.identifier==\"$ocid\")" |
  grep "\"identifier\": \"$ocid" >/dev/null
  search_status=$?
  [ "$search_status" -ne 0 ] && >&2 echo "OCID not found at OCI."

  return $search_status
}

# on-line
function validator_oci_lookup_region() {
  local region=$1

  if [ "$validator_usecache" == yes ]; then
    cache_ttl=$cache_ttl_oci_region
    cache_group=oci_region
    cache_key=regions
    oci_regions=$(cache.invoke oci iam region list)
  else
    oci_regions=$(oci iam region list)
  fi

  region_name=$(echo "$oci_regions" | jq -r ".data[] | select(.name==\"$region\") | .name")
  if [ "$region" != "$region_name" ]; then
    >&2 echo "No such region: $region"
    return 1
  fi

}

# on-line
function validator_oci_lookup_regions() {
  local regions=$@

  #IFS=,
  for region in $(echo $regions | tr , ' '); do
    #unset IFS

    validator_oci_lookup_region $region
  done
}

#
# handler
# 

function validators_validate() {
  local var_name=$1

  unset validate_codes
  declare -gA validate_codes

  validator_cnt=0
  validator_passed=0

  if [ ! -z ${script_args_validator[$var_name]} ]; then
    validator_DEBUG "Validates: $var_name"
  fi

  #IFS=,
  for validator in $(echo ${script_args_validator[$var_name]} | tr , ' '); do
    #unset IFS

    type validator_$validator | head -1 | grep "^validator_$validator is a function$" >/dev/null
    if [ $? -ne 0 ]; then
      echo "Error. Validator must be a function."
      validator_passed=1
      validate_codes[$validator_cnt]=127
      break
    fi

    validator_$validator ${!var_name}
    validator_exit_code=$?

    test $validator_exit_code -eq 0 && validate_result=PASSED || validate_result=FAILED
    
    validator_DEBUG " \-$validator:$validate_result "

    test $validator_exit_code -ne 0 && validator_passed=1

    validate_codes[$validator_cnt]=$validator_exit_code
    validator_cnt=$(( $validator_cnt + 1 ))
  done
  

  return $validator_passed
}

#
# test
# 

function validators_test() {

  unset script_args_validator
  declare -A script_args_validator

  # srv_address=1.1.1.1
  script_args_validator[srv_address]="ip_address,ip_address_reachable"

  # test srv_address
  validator_ip_address_reachable_timeout=1
  srv_address=1.1.1.255
  validators_validate srv_address
  echo $?
  echo "${validate_codes[@]}"

  srv_address=1.1.1.1
  validators_validate srv_address
  echo $?
  echo "${validate_codes[@]}"

  # svc_address=1.1.1.1:25
  script_args_validator[svc_address]="tcp_service_reachable"

  svc_address=1.1.1.1:53
  validators_validate svc_address
  echo $?
  echo "${validate_codes[@]}"

  validator_tcp_service_reachable_timeout=1
  svc_address=1.1.1.1:1
  validators_validate svc_address
  echo $?
  echo "${validate_codes[@]}"

  #
  # ocid
  # 

  for resource_ocid in ocid1.compartment.oc1..aaaaaaaai3ynjnzj5v4wizepnfosvcd4ntv2jgctqh4wpymhcn3odhuw6luq \
  ocid1.loggroup.oc1.eu-frankfurt-1.amaaaaaakb7hq2ia5kwo4b24umk6z6txhrl5bchth4jbksb6mrv2fuxfxj2q \
  ocid1.vault.oc1.eu-frankfurt-1.bfpz743daaaao.abtheljs3m4qeip5fm7rgr42kxtxhnn2xkwipuhi5fkirh4yt5p7ax2t2c2a \
  ocid1.loggroup.oc1.eu-frankfurt-1.akb7hq2ia5kwo4b24umk6z6txhrl5bchth4jbksb6mrv2fuxfxj2q \
  ocid1.vault.oc1.eu-frankfurt-1.bfpz7da.abtheljs3m4qeip5fm7rgr42kxtxhnn2xkwipuhi5fkirh4yt5p7ax2t2c2a
  do
    echo $resource_ocid
    validator_oci_format_ocid $resource_ocid
    echo $?
    echo ${validator_oci_format_ocid_error[@]}
  done


  # compartment verification
  compartment_ocid=ocid1.compartment.oc1..aaaaaaaai3ynjnzj5v4wizepnfosvcd4ntv2jgctqh4wpymhcn3odhuw6luq

  script_args_validator[compartment_ocid]="oci_format_ocid_compartment"

  validators_validate compartment_ocid
  echo $?
  echo "${validate_codes[@]}"
  echo ${validator_oci_format_ocid_error[@]}

  # any resource verification
  script_args_validator[resource_ocid]="oci_format_ocid,oci_lookup_ocid"

  resource_ocid=ocid1.vault.oc1.eu-frankfurt-1.bfpz743daaaao.abtheljs3m4qeip5fm7rgr42kxtxhnn2xkwipuhi5fkirh4yt5p7ax2t2xxx

  validators_validate resource_ocid
  echo $?
  echo "${validate_codes[@]}"
  echo ${validator_oci_format_ocid_error[@]}

  resource_ocid=ocid1.vault.oc1.eu-frankfurt-1.bfpz743daaaao.abtheljs3m4qeip5fm7rgr42kxtxhnn2xkwipuhi5fkirh4yt5p7ax2t2c2a
  validators_validate resource_ocid
  echo $?
  echo "${validate_codes[@]}"
  echo ${validator_oci_format_ocid_error[@]}

  # compartment will fail
  resource_ocid=ocid1.compartment.oc1..aaaaaaaai3ynjnzj5v4wizepnfosvcd4ntv2jgctqh4wpymhcn3odhuw6luq

  validator_oci_format_ocid $resource_ocid
  echo $?
  echo ${validator_oci_format_ocid_error[@]}

  validators_validate resource_ocid
  echo $?
  echo "${validate_codes[@]}"
  echo ${validator_oci_format_ocid_error[@]}

  # log group
  resource_ocid=ocid1.loggroup.oc1.eu-frankfurt-1.amaaaaaakb7hq2ia5kwo4b24umk6z6txhrl5bchth4jbksb6mrv2fuxfxj2q
  validators_validate resource_ocid
  echo $?
  echo "${validate_codes[@]}"
  echo ${validator_oci_format_ocid_error[@]}

}
