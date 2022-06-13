

#
# core settings
#

# discover script directory
unset script_bin
script_path=$0
test $script_path != '-bash' && script_bin=$(dirname "$0")
test -z "$script_bin" && named_exit "Script bin directory unknown."

# script param attributes

unset script_args_default
declare -A script_args_default

unset script_args_validator
declare -A script_args_validator

# system level exit codes
set_exit_code_variable "Script bin directory unknown." 1
set_exit_code_variable "Required library not found in script path." 2
set_exit_code_variable "Required tools not available." 3
set_exit_code_variable "Directory not writeable." 4
set_exit_code_variable "Parameter validation failed."  5

# extend script libs by config validator, as used by generic code
script_libs="$script_libs config.bash validators.bash"

# extend system argument by generic ones
script_args_system="$script_args_system,cfg_id:,temp_dir:,debug,trace,warning:,help,setconfig:,progress_spinner:,validate_params:"

# extnd script tools
script_tools="$script_tools,getopt,sed,cut,tr,grep"

#
# Check environment
#

# check required libs
unset missing_tools
for script_lib in $script_libs; do
  test ! -f $script_bin/$script_lib && missing_tools="$script_lib,$missing_tools"
done

# check required tools
for cli_tool in $script_tools; do
  which $cli_tool > /dev/null 2>/dev/null
  test $? -eq 1 && missing_tools="$cli_tool,$missing_tools"
done

missing_tools=$(echo $missing_tools | sed 's/,$//')
test ! -z "$missing_tools" && named_exit "Required tools not available." "$missing_tools"

#
# load libraries
#
for script_lib in $script_libs; do
  source $script_bin/$script_lib 2>/dev/null
done

#
# read arguments
#

# Parameters are reflected in shell variables which are set with parameter value. 
# No value parameters are set to 'set' if exist in cmd line arguents

# clean params to avoid exported ones
for cfg_param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , ' ' | tr -d :); do
  unset $cfg_param
done

#
# set default values
#

for variable in ${!script_args_default[@]}; do
  eval $variable=${script_args_default[$variable]}
done

valid_opts=$(getopt --longoptions "$script_args,$script_args_persist,$script_args_system" --options "" --name "$script_name" -- $@)
eval set --"$valid_opts"

while [[ $# -gt 0 ]]; do
  if [ $1 == '--' ]; then
    break
  fi
  var_name=$(echo $1 | cut -b3-999)
  if [[ "$2" != --* ]]; then
    eval $var_name=$2; shift 2
  else
    eval $var_name="set"; shift 1
  fi
done

# change set flag to yes|no
for param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , '\n' | grep -v :); do
  if [ "${!param}" == set ]; then
    eval $param=yes
  else
    eval $param=no
  fi
done

#
# trace
#
if [ "$trace" == yes ]; then
  PS4='${LINENO} '
  set -x
fi

#
# debug handler
#
if [ "$debug" == yes ]; then

  # enable debug for loaded libraries
  for script_lib in $script_libs; do
    lib_name=$(echo $script_lib | cut -f1 -d.)
    eval ${lib_name}_debug=yes
  done

fi

function DEBUG() {
  if [ "$debug" == yes ]; then
    echo $@ >&2
  fi
}

function WARN() {
  if [ "$warning" == yes ]; then
    echo $@ >&2
  fi
}


#
# set config source
#

if [ ! -z "$cfg_id" ]; then
  script_cfg=$cfg_id
fi


#
# script info
#
function about() {
  echo "$script_name, $script_version by $script_by" 
}

function usage() {
  echo
  echo -n "Usage: $script_name" 
  for param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , ' ' | tr -d :); do
    echo -n " --$param"
  done
  echo

  echo 
  echo 'Argument formats:'
  if [ ${#script_args_validator[@]} -gt 0 ];then
    for variable in ${!script_args_validator[@]}; do
      echo " \-$variable: ${script_args_validator[$variable]}"
    done
  else
    echo '(none)'
  fi

  echo 
  echo 'Default values:'
  if [ ${#script_args_default[@]} -gt 0 ];then
    for variable in ${!script_args_default[@]}; do
      echo " \-$variable: ${script_args_default[$variable]}"
    done
  else
    echo '(none)'
  fi

  if [ ${#script_args_default[@]} -gt 0 ];then
    echo
    echo "Persisted values (config: $script_cfg)":
    persistent=none
    for variable in $(echo $script_args_persist | tr , ' ' | tr -d :); do
      var_value=$(config.getcfg $script_cfg $variable)
      if [ ! -z "$var_value" ]; then
        echo " \-$variable: $var_value"
        persistent=$persistent,$variable
      fi
    done
    if [ $persistent == none ]; then
      echo '(none)'
    fi
  fi
}

#
# start
#
about >&2

if [ "$help" == yes ]; then
  usage
  exit 0
fi

#
# read parameters from config file
#

# read parameters from cfg file
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  if [ -z "${!cfg_param}" ]; then
    eval $cfg_param="$(config.getcfg $script_cfg $cfg_param)"
  fi
done

#
# validate. validate params even from config file, as it's possible thet it was edited manually
#

if [ "$validate_params" == yes ]; then
#  for param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , ' ' | tr -d :); do
    for param in regions; do
      if [ ! -z "${!param}" ]; then
        validators_validate $param
        if [ $? -ne 0 ]; then
          validator_debug_value=$validator_debug
          validator_debug=yes
          validators_validate $param
          validator_debug=$validator_debug_value
          named_exit "Parameter validation failed."
        fi 
      fi
  done
fi

#
# persist parameters
#

# Persistable configurables are stored in config files. When variable is not specified on cmd level, it is loaded from file. 
# If it's not provided in cmd line, and not available in cfg file, then operator is asked for value. 
# Finally if value is set at cmd line, and is not in config file - it will be persisted.
#
# config file identifier may be specified in cmd line. When not set default name of the script is used.

# set parameters when not set
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  if [ -z "${!cfg_param}" ]; then
    echo
    echo "Info. Required configurable $cfg_param unknown."
    read -p "Enter value for $cfg_param:" $cfg_param
    
    validators_validate "$cfg_param"
    if [ $? -ne 0 ]; then
      named_exit "Parameter validation failed." $cfg_param
    fi 

    config.setcfg $script_cfg $cfg_param "${!cfg_param}" force
  fi
done

# persist when not persisted. All data is already validated.
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  value=$(config.getcfg $script_cfg $cfg_param)
  if [ -z "$value" ]; then
    config.setcfg $script_cfg $cfg_param "${!cfg_param}" force
  fi
done
