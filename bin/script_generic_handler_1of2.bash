#!/bin/bash

#
# core settings & functions 1of2
#

#
# TODO
#

#
# PROGRESS
#

#
# DONE
#
# fix persist only arguents with value. Never ask for the value. 
# NORMAL add mandatory parameters handler
# CRITICAL check if OS is linux-gnu
# fix argument - list with spaces to list with commas
# SYSTEM add generic Trap with default Quit
# temp dir with script name
# fix missing tools check, lib load
# fix validators, default
# improve trace with details

# check if OS is linux-gnu
if [ $OSTYPE != 'linux-gnu' ]; then
  echo "Critical error. Script is designed only for Linux. Can't continue." >&2
  exit 1
fi

# load named_exit
if [ ! -f $(dirname "$0" 2>/dev/null)/named_exit.bash ]; then
  echo "Critical error. Required named_exit.bash library not found in script path. Can't continue." >&2
  exit 1
fi
source $(dirname "$0" 2>/dev/null)/named_exit.bash

# system level exit codes
set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required library not found in script path." 2
set_exit_code_variable "Required tools not available." 3
set_exit_code_variable "Mandatory arguments missing." 4
set_exit_code_variable "Parameter validation failed."  5


# discover script directory
unset script_bin
script_path=$0
test $script_path != '-bash' && script_bin=$(dirname "$0" 2>/dev/null)
test -z "$script_bin" && named_exit "Script bin directory unknown."

# extend script libs by config validator, as used by generic code
script_libs="$script_libs,config.bash,validators.bash"

# extend system argument by generic ones
script_args_system="$script_args_system,cfg_id:,temp_dir:,debug,trace,warning:,help,setconfig:,progress_spinner:,validate_params:"

# extend script tools
script_tools="$script_tools,getopt,sed,cut,tr,grep"

# arguments - validators
unset script_args_validator
declare -A script_args_validator

script_args_validator[temp_dir]=directory_writable
script_args_validator[cfg_id]=label
script_args_validator[debug]=flag
script_args_validator[trace]=flag
script_args_validator[warning]=flag
script_args_validator[help]=flag
script_args_validator[validate_params]=yesno

# arguments - default values
unset script_args_default
declare -A script_args_default

temp_dir=$HOME/tmp/$script_name/$RANDOM; mkdir -p $temp_dir
script_args_default[temp_dir]=$temp_dir
script_args_default[cfg_id]=$script_cfg
script_args_default[debug]=no
script_args_default[trace]=no
script_args_default[warning]=yes
script_args_default[validate_params]=yes

