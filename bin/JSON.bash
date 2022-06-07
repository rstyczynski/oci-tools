#/bin/bash

#
# script information
#

lib_name='JSON.bash'
lib_version='1.0'
lib_by='ryszard.styczynski@oracle.com'

lib_tools='jq'
lib_cfg=''

#
# Check environment
#

function JSON.ensure_environment() {

  JSON_environment=unknown

  # check required tools
  unset missing_tools
  unset JSON_environment_faulure_cause

  if [ ! -z "$lib_cfg" ]; then
    test ! -f $lib_bin/config.sh && missing_tools="config.sh,$missing_tools"
  fi

  for cli_tool in $lib_tools; do
    which $cli_tool > /dev/null 2>/dev/null
    if [ $? -eq 1 ]; then
      if [ -z "$missing_tools" ]; then
        missing_tools="$cli_tool"
      else
        missing_tools="$cli_tool,$missing_tools"
      fi
    fi
  done

  # TODO: how to exit from using generic way?
  if [ ! -z "$missing_tools" ]; then

    JSON_environment_faulure_cause="Required tools not available. Missing tools:$missing_tools."
    echo $JSON_environment_faulure_cause >&2
    JSON_environment=failed
    result=1
  else 
    JSON_environment=ok
    result=0
  fi

  return $result
}

#
#
#

JSON_debug=no

function JSON.debug() {
  if [ "$JSON_debug" == yes ]; then
    echo $@ >&2
  fi
}

#
#
#

function JSON.init(){

  echo '{'
  object_element_level=0
  declare -g -A object_variable_cnt
  object_variable_cnt[$object_element_level]=0

  # TIP: trick to report error in returned JSON data
  JSON.ensure_environment
  if [ $JSON_environment != ok ]; then

    cat <<_EOF
"_error": {
  "datetime": "$(date +"%Y-%m-%dT%H:%M:%S%z")",
  "timestamp": "$(date +%s)",
  "lib_name": "$lib_name",
  "lib_version": "$lib_version", 
  "hostname": "$(hostname)",
  "whoami": "$(whoami)",
  "error": "Environment verification failed",
  "cause": "$JSON_environment_faulure_cause"
}
_EOF

    object_variable_cnt[$object_element_level]=1
  fi
}

function JSON.close(){
  echo '}'
}

function JSON.object.init(){
  var_name=$1

  JSON.debug object_element_level:$object_element_level 
  JSON.debug object_variable_cnt: ${object_variable_cnt[$object_element_level]}

  case ${object_variable_cnt[$object_element_level]} in
  0)
    echo "\"$1\": {"
    ;;
  *)
    echo ", \"$1\": {"
    ;;
  esac

  object_variable_cnt[$object_element_level]=$(( ${object_variable_cnt[$object_element_level]} + 1))
  object_element_level=$(($object_element_level + 1))
  object_variable_cnt[$object_element_level]=0
}

function JSON.object.close(){

  echo '}'

  object_variable_cnt[$object_element_level]=0
  object_element_level=$(($object_element_level - 1))
}

function JSON.array.add(){
  array_name=$1
  var_name=$2

  : ${var_name:=$array_name}

  # pass array by name. https://stackoverflow.com/questions/16461656/how-to-pass-array-as-an-argument-to-a-function-in-bash
  array_var_name=$1[@]
  array_var=("${!array_var_name}")

  JSON.debug object_variable_cnt: ${object_variable_cnt[$object_element_level]}

  case ${object_variable_cnt[$object_element_level]} in
  0)
    echo -n "\"$var_name\": ["
    ;;
  *)
    echo -n ", \"$var_name\": ["
    ;;
  esac

  array_ndx=0
  while [ $array_ndx -lt ${#array_var[@]} ]; do
    echo -n "\"${array_var[$array_ndx]}\""

    if [ $array_ndx -lt $(( ${#array_var[@]} - 1 )) ]; then
      echo -n ", "
    fi
    array_ndx=$(( $array_ndx + 1 ))
  done

  #echo ${array_var[@]} | tr ' ' ',' | sed 's/,/","/g; s/^/"/; s/$/"/'
  echo "]"

  object_variable_cnt[$object_element_level]=$(( ${object_variable_cnt[$object_element_level]} + 1))
}

function JSON.map.add(){
  map_name=$1
  var_name=$2

  : ${var_name:=$map_name}

  case ${object_variable_cnt[$object_element_level]} in
  0)
    echo "\"$var_name\": {"
    ;;
  *)
    echo ", \"$var_name\": {"
    ;;
  esac
  
  key_cnt=0
  for key in $(eval "echo \${!$map_name[@]}"); do
    value=$(eval "echo \${$map_name[$key]}")

    if [ $key_cnt -gt 0 ]; then
      echo -n ', '
    fi
    echo "\"$key\": \"$value\""
    key_cnt=$(( $key_cnt + 1 ))
  done

  echo "}"

  object_variable_cnt[$object_element_level]=$(( ${object_variable_cnt[$object_element_level]} + 1))
}


function JSON.var.add(){
  env_name=$1
  var_name=$2

  : ${var_name:=$env_name}

  case ${object_variable_cnt[$object_element_level]} in
  0)
    echo "\"$var_name\": \"${!env_name}\""
    ;;
  *)
    echo ", \"$var_name\": \"${!env_name}\""
    ;;
  esac
  
  object_variable_cnt[$object_element_level]=$(( ${object_variable_cnt[$object_element_level]} + 1))
}

function JSON.literal.add(){
  literal_name=$1
  literal_value=$2

  case ${object_variable_cnt[$object_element_level]} in
  0)
    echo "\"$literal_name\": \"$literal_value\""
    ;;
  *)
    echo ", \"$literal_name\": \"$literal_value\""
    ;;
  esac
  
  object_variable_cnt[$object_element_level]=$(( ${object_variable_cnt[$object_element_level]} + 1))
}

#
# test
#

function JSON.test1() {
  JSON.init

      JSON.literal.add words1 'Lorem ipsum dolor sit amet'

      words2=', consectetur adipiscing elit'
      JSON.var.add words2

      JSON.object.init object1
      
          array1=(, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.)
          JSON.array.add array1
          
          array2=(Ut enim ad minim veniam)
          JSON.array.add array2

          declare -A map1
          map1[var1]=", quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
          map1[var2]="Duis aute irure dolor in reprehenderit in voluptate"
          JSON.map.add map1

          JSON.literal.add invitation 'velit esse cillum dolore eu fugiat'

          words='nulla pariatur.'
          JSON.var.add words

          JSON.object.init object1.1

              declare -A map2
              map2[var3]=Excepteur
              map2[var4]=sint
              JSON.map.add map2

          JSON.object.close object1.1

      JSON.object.close object1

      JSON.object.init object2

          declare -A map4
          map4[var1]="occaecat cupidatat"
          map4[var2]="non proident"
          JSON.map.add map4 m.a.p.4

          JSON.literal.add invitation ', sunt in culpa'

          invite='qui officia deserunt mollit anim id est laborum.'
          JSON.var.add invite

      JSON.object.close object2

  JSON.close
}

function JSON.help() {
  cat <<EOF
Bash JSON library $lib_version

Set of functions to facilitate building JSON data structure.

JSON.init                    - init JSON. Invoke at begining
JSON.object.init             - init object. You can embed objects n other objets as needed.
JSON.literal.add key value   - add key with literal value
JSON.var.add var [key]       - add key with value taken from env's var variable. You may set key name or use the var name.
JSON.array.add array [key]   - add key with value taken from env's array variable. You may set key name or use the var name.
JSON.map.add map [key]       - add key with value taken from env's map variable. You may set key name or use the var name.
JSON.object.close            - close object
JSON.close                   - close JSON. Invoke at the end

Tip: Alwaya use jq utility to validate created JSON structire.

Exemplary function: JSON.test1. Look inside by "type JSON.test1". Execute with jq: "JSON.test1 | jq"
EOF
}

JSON.ensure_environment
if [ $? -eq 0 ]; then
  echo "Bash JSON library loaded. Invoke JSON.help to learn more." >&2
else
  echo "Bash JSON library loaded with errors: $JSON_environment_faulure_cause" >&2
fi
