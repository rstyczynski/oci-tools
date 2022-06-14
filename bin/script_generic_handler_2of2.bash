#!/bin/bash

#
# core settings & functions 2of2
#

#
# Check environment
#

# check required libs
unset missing_tools
IFS=', '
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
unset IFS

#
# execute quit function on exit
#

trap script_generic_handler._quit exit int

function script_generic_handler._quit(){

  if [ -d $temp_dir ]; then
    rm -rf $temp_dir
  fi

  # invoke quit function if defined
  [[ $(type -t quit) == function ]] && quit
}


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
    eval $var_name="$2"; shift 2
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
  # http://www.skybert.net/bash/debugging-bash-scripts-on-the-command-line/
  export PS4='# ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]}() - [${SHLVL},${BASH_SUBSHELL},$?] '
  set -o xtrace
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
  for param in $(echo "$script_args_persist,$script_args_system,$script_args" | tr , ' ' | tr -d :); do
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
# persist parameters. All data is already validated.
#

for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  value=$(config.getcfg $script_cfg $cfg_param)
  if [ -z "$value" ]; then
    config.setcfg $script_cfg $cfg_param "${!cfg_param}" force
  fi
done

###########################
# check mandatory arguments
###########################

function generic.check_mandatory_arguments() {
  local mandatory_missing=''
  for cfg_param in $(echo $script_args_mandatory | tr , ' ' | tr -d :); do
    if [ -z "${!cfg_param}" ]; then
      echo
      echo "Required argument $cfg_param missing."
      if [ -z "$mandatory_missing" ]; then
        mandatory_missing=$cfg_param
      else
        mandatory_missing=$mandatory_missing,cfg_param
      fi
    fi
  done

  if [ ! -z "$mandatory_missing" ]; then
    named_exit "Mandatory arguments missing." $mandatory_missing
  fi
}

