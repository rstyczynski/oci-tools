#!/bin/bash

#
# core settings & functions 1of2
#

#
# TODO
#
# NORMAL Add inforation about used tools and libs by the script
# NORMAL generate documentaton in markup format
# HIGH Check if generic script_* varaibles are filled. Phase 1 of generic steps
# NICE named_exit verification auto scan

#
# PROGRESS
#

#
# DONE
#
# NORMAL add support for documentaton of parameters 
# NORMAL Add exit codes inforamtion to help
# fix # NORMAL add mandatory parameters handler
# NORMAL change script_generic_handler* to generic_handler*
# fix move spinner activation after help
# NORMAL script_desc shortly describes script purpose.
# NORMAL script_cfg takes script name w/o extension
# fix general support to enable library spinner
# fix sort arguments in help 
# NORMAL set local persist as default
# NORMAL convert generic code into functions
# fix handle ctrl-c interrupt handler
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
set_exit_code_variable "Critical error. Script is designed only for Linux. Can't continue." 1
set_exit_code_variable "Critical error. Required named_exit.bash library not found in script path. Can't continue." 1
set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required library not found in script path." 2
set_exit_code_variable "Required generic tools not available." 2
set_exit_code_variable "Required tools not available." 2
set_exit_code_variable "Mandatory arguments missing." 3
set_exit_code_variable "Parameter validation failed." 4
set_exit_code_variable "Operation interrupted." 5

# discover script directory
unset script_bin
script_path=$0
test $script_path != '-bash' && script_bin=$(dirname "$0" 2>/dev/null)
test -z "$script_bin" && named_exit "Script bin directory unknown."

# extend system argument by generic ones
script_args_system="$script_args_system,config_id:,temp_dir:,debug,trace,warning:,help,setconfig:,progress_spinner:,validate_params:"

# extend script libs by config validator, as used by generic code
script_libs="$script_libs,config.bash,validators.bash"

# extend script tools
script_tools="$script_tools,getopt,sed,cut,tr,grep,sort,which"

# script_cfg takes script name w/o extension
: ${script_cfg:=$(basename "$0" | cut -f1 -d.)}

# arguments - help
unset script_args_help
declare -A script_args_help

script_args_help[temp_dir]='Temporary directory used by the script.'
script_args_help[config_id]='Config identifier to sore persistent data.'
script_args_help[global_config]='Flag inicating that you prefer to write configuration to /etc. Useful when script is used from multiple OS accounts.'
script_args_help[debug]='Turn on debug.'
script_args_help[trace]='Turn on trace.'
script_args_help[warning]='Control warning messages presentation.'
script_args_help[help]='Display script help.'
script_args_help[validate_params]='Control validation of paramters. By defult all validation is performed. You may disable it when needed in the particular situation.'
script_args_help[setconfig]='Persists requested ergument value in config.'

# arguments - validators
unset script_args_validator
declare -A script_args_validator

script_args_validator[temp_dir]=directory_writable
script_args_validator[config_id]=label
script_args_validator[global_config]=flag
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
script_args_default[config_id]=$script_cfg
script_args_default[global_config]=no
script_args_default[warning]=yes
script_args_default[debug]=no
script_args_default[trace]=no
script_args_default[warning]=yes
script_args_default[validate_params]=yes

