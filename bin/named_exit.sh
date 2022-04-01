#!/bin/bash

function set_exit_code_variable() {
  desc=$1
  code=$2

  desc_var=$(echo $desc | tr ' ' '_')
  eval "script_exit_codes_$desc_var=$code"
}

function get_exit_code_variable() {
  desc=$1

  desc_var=$(echo $desc | tr ' ' '_')
  eval "echo \$script_exit_codes_$desc_var"
}

function named_exit() {
  desc=$1

  exit_code=$(get_exit_code_variable "$desc")
  if [ -z "$exit_code" ]; then
    echo "Critical. Exit code unknown."
    exit 125
  else
    echo $desc
    exit $exit_code
  fi 
}
