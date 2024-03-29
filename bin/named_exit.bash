#!/bin/bash

#
# TODO
#

#
# PROGRESS
#

#
# DONE
#
# store labels and code in associative array

#
# lib information
#

lib_name='named_exit.bash'
lib_version='1.1'
lib_by='ryszard.styczynski@oracle.com'

lib_tools=''
lib_cfg=''

#
# lib code
#

declare -A named_exit_exit_label
declare -A named_exit_exit_code

function set_exit_code_variable() {
  local desc=$1
  local code=$2

  desc_id=$(echo "$desc" | sha256sum | cut -f1 -d' ')
  named_exit_exit_label[$desc_id]="$desc"
  named_exit_exit_code[$desc_id]=$code
}

function get_exit_code_variable() {
  local desc=$1

  desc_id=$(echo "$desc" | sha256sum | cut -f1 -d' ')
  echo ${named_exit_exit_code[$desc_id]}
}

function named_exit() {
  local desc=$1
  local info=$2

  exit_code=$(get_exit_code_variable "$desc")
  if [ -z "$exit_code" ]; then
    >&2 echo
    >&2 echo "Critical. Exit code unknown."
    exit 125
  else
    if [ -z "$info" ];then
      >&2 echo
      >&2 echo "$desc"
    else
      >&2 echo
      >&2 echo "$desc Info: $info"
    fi
    exit $exit_code
  fi 
}
