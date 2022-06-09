#/bin/bash

#
# script information
#

lib_name='cache.bash'
lib_version='1.0'
lib_by='ryszard.styczynski@oracle.com'

lib_tools=''
lib_cfg=''

#
# Check environment
#

function cache.ensure_environment() {

  cache_environment=unknown

  # check required tools
  unset missing_tools
  unset cache_environment_faulure_cause

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

  # TODO: how to exit using generic way?
  if [ ! -z "$missing_tools" ]; then

    cache_environment_faulure_cause="Required tools not available. Missing tools:$missing_tools"
    echo $cache_environment_faulure_cause >&2
    cache_environment=failed
    result=1
  else 
    cache_environment=ok
    result=0
  fi

  return $result
}


cache_group=
cache_key=
cache_ttl=
cache_dir=
cache_debug=
cache_warning=yes

cache_progress=no
cache_spinner_cnt=1
cache_spinner="/-\|"

# https://stackoverflow.com/questions/238073/how-to-add-a-progress-bar-to-a-shell-script
function cache._progress() {
  if [ "$cache_progress" == yes ]; then
    printf "\b${cache_spinner:cache_spinner_cnt++%${#cache_spinner}:1}" >&2
  fi
}

function cache.debug() {
  if [ "$cache_debug" == yes ]; then
    echo $@ >&2
  fi
}

function cache.warning() {
  if [ "$cache_warning" == yes ]; then
    echo $@ >&2
  fi
}

function cache.evict() {
  cmd=$@

  cache._progress

  if [ -z "$cmd" ]; then
    : ${cache_group:=.}
  fi

  : ${cache_dir:=$HOME/.cache/cache_answer}

  # command fingerprint
  : ${cache_key:=$(echo $cmd | sha512sum | cut -f1 -d' ')}
  
  # data group
  : ${cache_group:=$(echo $cache_key | cut -b1-4)}

  cache_ttl=$(cat $cache_dir/$cache_group/.info 2>/dev/null | grep '^cache_ttl=' | cut -f2 -d=)
  : ${cache_ttl:=60}

  cache.debug "Deleting responses older than $cache_ttl minute(s)."
  find $cache_dir/$cache_group -type f -mmin +$cache_ttl -delete 2>/dev/null
  # delete dirs if empty
  find $cache_dir -type d -empty -delete 2>/dev/null
}

function cache._invoke() {

    cache._progress

    eval $cmd > $cmd_stdout 2>$cmd_stderr
    cmd_exit_code=$?
    if [ $cmd_exit_code -ne 0 ]; then
      mv $cmd_stdout $cmd_stdout.err
      cmd_stdout_data=$cmd_stdout.err
    else 
      cmd_stdout_data=$cmd_stdout
    fi

    cat > $cache_dir/$cache_group/$cache_key.info <<EOF
datetime=$(date +%Y-%m-%dT%H:%M:%S%z)
timestamp=$(date +%s)
lib_name=$lib_name
lib_version=$lib_version
hostname=$(hostname)
whoami=$(whoami)
cmd=$cmd
cmd_exit_code=$cmd_exit_code
cmd_stdout=$cmd_stdout_data
cmd_stderr=$cmd_stderr
cache_ttl=$cache_ttl
cache_key=$cache_key
cache_group=$cache_group
cache_dir=$cache_dir
EOF

    # exit if answer failed
    if [ $cmd_exit_code -ne 0 ]; then
      cat $cmd_stdout.err
      cache.warning "cache.bash: Exiting as command invocation returned error. More info: $cache_dir/$cache_group/$cache_key.info"
      return $cmd_exit_code
    fi
}

function cache.invoke() {
  cmd=$@

  if [ -z "$cmd" ]; then
    return 1
  fi

  : ${cache_dir:=$HOME/.cache/cache_answer}
  : ${cache_ttl:=60}

  # command fingerprint
  : ${cache_key:=$(echo $cmd | sha512sum | cut -f1 -d' ')}
  
  # data group
  : ${cache_group:=$(echo $cache_key | cut -b1-4)}

  # fles with reponse data
  cmd_stdout=$cache_dir/$cache_group/$cache_key.stdout
  cmd_stderr=$cache_dir/$cache_group/$cache_key.stderr

  # store ttl information
  mkdir -p $cache_dir/$cache_group
  echo "cache_ttl=$cache_ttl" > $cache_dir/$cache_group/.info

  # delete old data. Note: evict is after setting TTL, so updated TTL will be effective imadiately
  cache.evict $cmd

  # execute
  cache.debug "cache_dir=$cache_dir"
  cache.debug "cache_group=$cache_group"
  cache.debug "cache_key=$cache_key"
  cache.debug "cache_ttl=$cache_ttl"
  cache.debug "info=$cache_dir/$cache_group/$cache_key.info"

  # check if cached data exist
  if [ ! -f $cache_dir/$cache_group/$cache_key.stdout ]; then
    cache.debug "No previous answer. Executing $cmd"
    cache._invoke

  fi

  # return answer from cache
  if [ -d $cache_dir/$cache_group ] && [ -f $cmd_stdout ]; then
    cat $cmd_stdout
  else
    # it's possible that between "check if cached data exist" and "return answer from cache"  
    # another process flushed cache. No worries. Just execute cmd again
    cache.warning "Expected, but previous answer not found. Executing $cmd"
    mkdir -p $cache_dir/$cache_group
    cache._invoke
  fi
  
  # unsetting cache_group, cache_ky not to infuence next invocations of cache.invoke
  unset cache_group
  unset cache_key
  return $cmd_exit_code
}

function cache.help() {
  cat <<EOF
Bash cache library $lib_version

cache.invoke cmd              - use to invoke command cmd. Exit code comes from cmd
cache.evict cmd               - remove old respose; controled by ttl
cache_group=group cache.evict - remove all old data of given group
cache.evict                   - remove all old data

Response data is kept in cache_dir/cache_group/cache_key file. Files are deleted after cache_ttl minutes.
cache is controlled by belowenv variables:

cache_ttl=minutes              - response ttl in minutes; defaults to 60 minutes
cache_group=                   - response group name; computed from cmd f not provided
cache_key=                     - response key name; computed from cmd f not provided
cache_dir=~.cache/cache_answer - cache directory
cache_debug=no|yes             - debug flag
cache_warning=yes|no           - warning flag

Few facts:
1. Bash cache uses flock to serialise data eviction. If not available cache.evict should be executed manually.
2. Cached respone is stored with info file having inforation about kept data. 
3. Cache TTL is specific for cache group, and stored in cache directory in info file.

Special use. If you want to keep response data in well known path/file, you need to specify group and key name before invocation. 

cache_ttl=1
cache_dir=~/greetings
cache_group=echo cache_key=hello cache.invoke echo hello
cache_group=echo cache_key=world cache.invoke echo world

ls -l ~/greetings
ls -la ~/greetings/echo 

cat ~/greetings/echo/.info

cat ~/greetings/echo/hello
cat ~/greetings/echo/hello.info

cat ~/greetings/echo/world

sleep 61
cache_dir=~/greetings
cat ~/greetings/echo/.info

ls -la ~/greetings/echo
cache_group=echo cache.evict
ls -la ~/greetings/echo

EOF
}

# default values
: ${cache_dir:=$HOME/.cache/cache_answer}
: ${cache_ttl:=60}

cache.ensure_environment 2>/dev/null
if [ $? -eq 0 ]; then
  echo "Bash cache library loaded. Invoke cache.help to learn more." >&2
else
  echo "Bash cache library loaded with errors: $cache_environment_faulure_cause. Invoke cache.help to learn more." >&2
fi
