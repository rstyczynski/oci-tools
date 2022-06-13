#
# core settings 1of2
#

#
# TODO
#

#
# PROGRESS
#
# SYSTEM add generic Trap with default Quit

#
# DONE
#

# fix missing tools check, lib load
# fix validators, default
# improve trace with details

# load named_exit
if [ ! -f $(dirname "$0" 2>/dev/null)/named_exit.sh ]; then
  echo "$script_name: Critical error. Required named_exit.sh library not found in script path. Can't continue."
  exit 1
fi
source $(dirname "$0")/named_exit.sh

# system level exit codes
set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required library not found in script path." 2
set_exit_code_variable "Required tools not available." 3
set_exit_code_variable "Directory not writeable." 4
set_exit_code_variable "Parameter validation failed."  5

# discover script directory
unset script_bin
script_path=$0
test $script_path != '-bash' && script_bin=$(dirname "$0")
test -z "$script_bin" && named_exit "Script bin directory unknown."

# script param attributes

unset script_args_default
declare -A script_args_default
script_args_default[cfg_id]=$script_cfg
script_args_default[temp_dir]=~/tmp/$script_name
script_args_default[debug]=no
script_args_default[trace]=no
script_args_default[warning]=yes
script_args_default[validate_params]=yes

unset script_args_validator
declare -A script_args_validator
script_args_validator[cfg_id]=label
script_args_validator[debug]=flag
script_args_validator[help]=flag
script_args_validator[trace]=flag
script_args_validator[temp_dir]=directory_writable
script_args_validator[validate_params]=yesno

#
# execute quit function on exit
#

function script_generic_handler._quit(){

  if [ -d $temp_dir/$script_name ]; then
    rm -rf $temp_dir/$script_name
  fi
  [[ $(type -t quit) == function ]] && quit

}

trap script_generic_handler._quit exit int

