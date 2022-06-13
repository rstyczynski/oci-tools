#
# core settings 1of2
#

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
declare -g -A script_args_default

unset script_args_validator
declare -g -A script_args_validator
