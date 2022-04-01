#!/bin/bash

function set_exit_code_variable() {
  desc=$1
  code=$2

  desc_var=$(echo $desc | sed -e 's/[^A-Za-z0-9_-]/_/g')
  eval "script_exit_codes_$desc_var=$code"
}

function get_exit_code_variable() {
  desc=$1

  desc_var=$(echo $desc | sed -e 's/[^A-Za-z0-9_-]/_/g')
  eval "echo \$script_exit_codes_$desc_var"
}

function named_exit() {
  desc=$1
  info=$2

  exit_code=$(get_exit_code_variable "$desc")
  if [ -z "$exit_code" ]; then
    >&2 echo "Critical. Exit code unknown."
    exit 125
  else
    >&2 echo "$desc Info: $info"
    exit $exit_code
  fi 
}
