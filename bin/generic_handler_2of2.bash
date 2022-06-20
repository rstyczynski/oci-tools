#!/bin/bash

#
# core settings & functions 2of2
#

# execute quit function on exit
trap generic._exit exit int
trap generic._interrupt int

function generic._exit(){

  if [ -d $temp_dir ]; then
    rm -rf $temp_dir
  fi

  # invoke quit function if defined
  [[ $(type -t quit) == function ]] && quit
}

function generic._interrupt(){

  generic._exit
  named_exit "Operation interrupted."
}


#############################
# Helper functions
#############################

function generic._check_required_generic_tool() {
  tool=$1

  $tool 2>/dev/null >/dev/null
  if [ $? -eq 127 ]; then
    if [ -z "$missing_tools" ]; then
      missing_tools=$tool
    else
      missing_tools=$missing_tools,$tool
    fi
  fi
}

# check required libs
function generic.check_required_tools() {
  unset missing_tools
  
  generic._check_required_generic_tool which
  generic._check_required_generic_tool tr
  test ! -z "$missing_tools" && named_exit "Required generic tools not available." "$missing_tools"

  script_libs=$(echo $script_libs | tr , ' ')
  for script_lib in $script_libs; do
    test ! -f $script_bin/$script_lib && missing_tools="$script_lib,$missing_tools"
  done

  # check required tools
  script_tools=$(echo $script_tools | tr , ' ')
  for cli_tool in $script_tools; do
    which $cli_tool > /dev/null 2>/dev/null
    test $? -eq 1 && missing_tools="$cli_tool,$missing_tools"
  done
  missing_tools=$(echo $missing_tools | sed 's/,$//')
  test ! -z "$missing_tools" && named_exit "Required tools not available." "$missing_tools"
}

  # load libraries
function generic.load_libraries() {
  script_libs=$(echo $script_libs | tr , ' ')
  for script_lib in $script_libs; do
    source $script_bin/$script_lib 2>/dev/null
  done
}

#
# set default values
#
function generic.set_default_arguments() {
  for variable in ${!script_args_default[@]}; do
    eval $variable=${script_args_default[$variable]}
  done
}

#
# read command line arguments
#
function generic.load_cli_arguments() {
  valid_opts=$(getopt --longoptions "$script_args,$script_args_mandatory,$script_args_persist,$script_args_system" --options "" --name "$script_name" -- $@)
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
  for param in $(echo "$script_args,$script_args_mandatory,$script_args_persist,$script_args_system" | tr , '\n' | grep -v :); do
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
  # start
  #
  about >&2

  if [ "$help" == yes ]; then
    usage >&2
    exit 0
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


  # set script_cfg name
  if [ ! -z "$config_id" ]; then
    script_cfg=$config_id
  fi

  # cache spinner
  for script_lib in $script_libs; do
    lib_name=$(echo $script_lib | cut -f1 -d.)
    eval ${lib_name}_progress=$progress_spinner
  done

}

function generic.handle_setconfig() {

  ########################################
  # execute configuration tasks
  ########################################
  if [ ! -z "$setconfig" ]; then
    echo $setconfig | grep '=' >/dev/null
    if [ $? -eq 1 ]; then
      named_exit "Wrong invocation of setconfig." $setcfg
    else
      key=$(echo $setconfig | cut -f1 -d=)
      value=$(echo $setconfig | cut -f2 -d=)
      if [ -z "$key" ] || [ -z "$value" ]; then
        named_exit "Wrong invocation of setconfig." $setcfg
      else
        config.setcfg $script_cfg $key $value force
        named_exit "Configuration saved." "$script_cfg: $key/$(config.getcfg $script_cfg $key)"
      fi
    fi
  fi

}

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
# script info
#
function about() {
  echo "$script_name, $script_version by $script_by" 
}

function usage() {
  echo "$script_desc"
  echo
  echo -n "Usage: $script_name" 
  for param in $(echo "$script_args,$script_args_mandatory,$script_args_persist,$script_args_system" | tr , ' ' | tr -d :); do
    echo -n " --$param"
  done
  echo

  echo
  echo 'Notes about arguments:'
  for param in $(echo "$script_args,$script_args_mandatory,$script_args_persist,$script_args_system" | tr , ' ' | tr -d :); do
    echo " * $param: ${script_args_help[$param]}"
  done

  echo 
  echo 'Argument formats:'
  if [ ${#script_args_validator[@]} -gt 0 ]; then
    for variable in $(echo ${!script_args_validator[@]} | tr ' ' '\n' | sort); do
      for validator in ${script_args_validator[$variable]}; do
        echo " \-$variable: $validator - ${validator_info[$validator]}"
      done
    done
  else
    echo '(none)'
  fi

  echo 
  echo 'Default values:'
  if [ ${#script_args_default[@]} -gt 0 ];then
    for variable in $(echo ${!script_args_default[@]}  | tr ' ' '\n' | sort); do
      echo " \-$variable: ${script_args_default[$variable]}"
    done
  else
    echo '(none)'
  fi

  if [ ${#script_args_default[@]} -gt 0 ];then
    echo
    echo "Persisted values (config: $script_cfg)":
    persistent=none
    for variable in $(echo $script_args_persist | tr , '\n' | sort | tr -d :); do
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

  unset ok_code
  unset error_code
  for exit_code_id in ${!named_exit_exit_code[@]}; do
    exit_label=${named_exit_exit_label[$exit_code_id]}
    exit_code=${named_exit_exit_code[$exit_code_id]}
    if [ $exit_code -eq 0 ]; then
      echo " \-$exit_label" >> $temp_dir/ok_codes
    else
      echo " \-$exit_code: $exit_label" >> $temp_dir/error_codes
    fi
  done

  echo
  echo "Success messages:"
  cat $temp_dir/ok_codes | sort -k2

  echo
  echo "Error codes and messages:"
  cat $temp_dir/error_codes | sort -n -t '-' -k2

  rm -rf $temp_dir/ok_codes $temp_dir/error_codes

}


###########################
# define non help functions
###########################

# read parameters from cfg file
function generic.load_persisted_arguments() {
for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
  if [ -z "${!cfg_param}" ]; then
    eval $cfg_param="$(config.getcfg $script_cfg $cfg_param)"
  fi
done
}

#
# validate. validate params even from config file, as it's possible thet it was edited manually
#
function generic.validate_arguments() {
  if [ "$validate_params" == yes ]; then
    for param in $(echo "$script_args,$script_args_mandatory,$script_args_persist,$script_args_system" | tr , ' ' | tr -d :); do
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
}

#
# persist parameters. All data is already validated.
#
function generic.persist_arguments() {

  local config_level
  test "$global_config" == y && config_level=global || config_level=local

  for cfg_param in $(echo $script_args_persist | tr , ' ' | tr -d :); do
    value=$(config.getcfg $script_cfg $cfg_param)
    if [ -z "$value" ]; then
      if [ ! -z "${!cfg_param}" ]; then
        config.setcfg $script_cfg $cfg_param "${!cfg_param}" $config_level
      fi
    fi
  done
}

###########################
# check mandatory arguments
###########################

function generic.check_mandatory_arguments() {
  if [ ! -z "$1" ]; then
    mandatory_args="$@"
  else
    mandatory_args=$(echo $script_args_mandatory | tr , ' ' | tr -d :)
  fi

  local mandatory_missing=''
  for cfg_param in $mandatory_args; do
    if [ -z "${!cfg_param}" ]; then
      echo "Required argument $cfg_param missing."
      if [ -z "$mandatory_missing" ]; then
        mandatory_missing=$cfg_param
      else
        mandatory_missing=$mandatory_missing,$cfg_param
      fi
    fi
  done

  if [ ! -z "$mandatory_missing" ]; then
    named_exit "Mandatory arguments missing." $mandatory_missing
  fi
}

