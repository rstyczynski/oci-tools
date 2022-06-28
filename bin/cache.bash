#/bin/bash

#
# TODO
#
# add exit trap to clean cache_invoke_filter etc.

#
# PROGRESS
#


#
# DONE
#
# fix: BASH_SOURCE to be used to discover bin dir
# TIP: react on empty answer when not possible
# add encrypted cache instance storage
# add test section
# moved cache stdut answer to key
# moved cahce sterr answer to key.err

#
# script information
#

cache_lib_name='cache.bash'
cache_lib_version='1.1'
cache_lib_by='ryszard.styczynski@oracle.com'

cache_lib_tools='openssl cut tr grep cat sha1sum'
cache_lib_cfg=''

# cache init 
export cache_ttl
export cache_group
export cache_key
export cache_invoke_filter
export cache_response_filter
export cache_cipher
export cache_key

unset cache_group
unset cache_key
unset cache_ttl
unset cache_invoke_filter
unset cache_response_filter
unset cache_crypto_cipher
unset cache_crypto_key

unset cache_dir
unset cache_debug

cache_warning=yes
cache_progress=no
cache_spinner_cnt=1
cache_spinner="/-\|"
#
# Check environment
#

function cache.ensure_environment() {

  cache_environment=unknown

  # check required tools
  unset missing_tools
  unset cache_environment_failure_cause

  local missing_tools
  local cache_environment_failure_cause

  if [ ! -z "$cache_lib_cfg" ]; then
    test ! -f $lib_bin/config.sh && missing_tools="config.sh,$missing_tools"
  fi

  for cli_tool in $cache_lib_tools; do
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

    cache_environment_failure_cause="Required tools not available. Missing tools:$missing_tools"
    echo $cache_environment_failure_cause >&2
    cache_environment=failed
    result=1
  else 
    cache_environment=ok
    result=0
  fi

  return $result
}


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

function cache.evict_group() {
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


function cache.flush() {
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

  cache.debug "Flushing $cache_group/$cache_key."
  rm -rf $cache_dir/$cache_group/$cache_key.*
}

function cache._invoke() {

    cache._progress

    # EXPERIMENTAL
    if [ ! -z "$cache_crypto_key" ]; then
      : ${cache_crypto_cipher:=aes-256-cbc}
      cache_invoke_filter="openssl $cache_crypto_cipher -a -pass file:$cache_crypto_key"
      cache_response_filter="openssl $cache_crypto_cipher -d -a -pass file:$cache_crypto_key"
    fi
    : ${cache_invoke_filter:=cat}
    : ${cache_response_filter:=cat}

    rm -f $cmd_stdout.fifo; mkfifo $cmd_stdout.fifo
    rm -f $cmd_stderr.fifo; mkfifo $cmd_stderr.fifo

    (cat $cmd_stdout.fifo | $cache_invoke_filter  > $cmd_stdout &)
    (cat $cmd_stderr.fifo | $cache_invoke_filter  > $cmd_stderr &)
    
    eval $cmd > $cmd_stdout.fifo 2>$cmd_stderr.fifo

    rm -f $cmd_stdout.fifo
    rm -f $cmd_stderr.fifo
    # EXPERIMENTAL

    # eval $cmd > $cmd_stdout 2>$cmd_stderr

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
cache_lib_name=$cache_lib_name
cache_lib_version=$cache_lib_version
hostname=$(hostname)
whoami=$(whoami)
cmd=$cmd
cmd_exit_code=$cmd_exit_code
cmd_stdout=$cmd_stdout_data
cmd_stderr=$cmd_stderr
cache_invoke_filter=$cache_invoke_filter
cache_response_filter=$cache_response_filter
cache_crypto_key=$cache_crypto_key
cache_crypto_cipher=$cache_crypto_cipher
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
  cmd_stdout=$cache_dir/$cache_group/$cache_key
  cmd_stderr=$cache_dir/$cache_group/$cache_key.err

  # store ttl information
  mkdir -p $cache_dir/$cache_group
  echo "cache_ttl=$cache_ttl" > $cache_dir/$cache_group/.info

  # delete old data. Note: evict is after setting TTL, so updated TTL will be effective imadiately
  cache.evict_group $cmd

  # execute
  cache.debug "cache_dir=$cache_dir"
  cache.debug "cache_group=$cache_group"
  cache.debug "cache_key=$cache_key"
  cache.debug "cache_ttl=$cache_ttl"
  cache.debug "info=$cache_dir/$cache_group/$cache_key.info"

  # check if cached data exist
  if [ ! -f $cache_dir/$cache_group/$cache_key ]; then
    cache.debug "No previous answer. Executing $cmd"
    cache._invoke
  fi

  # return answer from cache
  if [ -d $cache_dir/$cache_group ] && [ -f $cmd_stdout ]; then
    
    # EXPERIMENTAL
    cache_response_filter=$(cat $cache_dir/$cache_group/$cache_key.info | grep "^cache_response_filter=" | cut -f2-999 -d=)

    cat $cmd_stdout | $cache_response_filter
    # EXPERIMENTAL
  
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
  unset cache_invoke_filter
  unset cache_response_filter
  unset cache_crypto_key
  unset cache_crypto_cipher

  return $cmd_exit_code
}

function cache.help() {
  cat <<EOF
Bash cache library $cache_lib_version

cache.invoke cmd              - use to invoke command cmd. Exit code comes from cmd
cache.evict_group cmd               - remove old respose; controled by ttl
cache_group=group cache.evict_group - remove all old data of given group
cache.evict_group                   - remove all old data

Response data is kept in cache_dir/cache_group/cache_key file. Files are deleted after cache_ttl minutes.
cache is controlled by belowenv variables:

cache_ttl=minutes              - response ttl in minutes; defaults to 60 minutes
cache_group=                   - response group name; computed from cmd f not provided
cache_key=                     - response key name; computed from cmd f not provided
cache_crypto_key=              - key used to encrypt/decryopt stored answer using opens ssl
cache_crypto_cipher=           - cipher used to encrypt/decryopt stored answer using opens ssl
cache_invoke_filter=           - command used to filter answer before storage
cache_response_filter=         - command used to filter answer before receiving from storage
cache_dir=~.cache/cache_answer - cache directory
cache_debug=no|yes             - debug flag
cache_warning=yes|no           - warning flag

Few facts:
1. Cached respone is stored with info file having inforation about kept data. 
1. Cache TTL i.e. time to live in minutes is specific for cache group, and stored in cache directory in info file.

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
cache_group=echo cache.evict_group
ls -la ~/greetings/echo

EOF
}

# default values
: ${cache_dir:=$HOME/.cache/cache_answer}
: ${cache_ttl:=60}

cache_lib_name='cache.bash'
cache_lib_version='1.1'
cache_lib_by='ryszard.styczynski@oracle.com'


cache.ensure_environment 2>/dev/null
if [ $? -eq 0 ]; then
  cat >&2 <<_hello1_EOF
Library $cache_lib_name $cache_lib_version by $cache_lib_by loaded.
Invoke cache.help to learn more. Invoke cache.test to verify that all is ok.
_hello1_EOF

else
  cat >&2 <<_hello2_EOF
Library $cache_lib_name $cache_lib_version by $cache_lib_by loaded with errors: $cache_environment_failure_cause. 
Invoke cache.help to learn more.
_hello2_EOF
fi

#
# test
#


#source $script_bin/unit_test.bash
#source $script_bin/cache.bash

function cache.test_group1_init() {
  cache_dir=~/cache.test
  rm -rf ~/cache.test # by intention not to delte real cache_dir
}

function cache.test_group1_results() {
  :
}

function cache.test_group1_clean() {
  rm -rf ~/cache.test # by intention not to delte real cache_dir
}

function cache.test_group1() {
  test_group=test_group1

  cat > $test_group <<EOF
"smoke test1" "echo OK1" OK1
EOF
  test.verify $test_group

  #tested separetly due to read fron stdin
  test.verify "smoke test2" "echo OK2" OK2
  test.verify "cache1 - slow operation" "cache.invoke 'sleep 1; echo hello'" hello
  test.verify "cache1 - slow operation now is fast" "cache.invoke 'sleep 1; echo hello'" hello

  test.verify "cache2 - cache group/key with command" "cache_group=echo cache_key=hello cache.invoke echo hello" hello
  test.verify "cache2 - cache group/key w/o command" "cache_group=echo cache_key=hello cache.invoke :" hello
  test.verify "cache2 - read directly from cache directory" "cat $cache_dir/echo/hello" hello

  dynamic='$(date)'
  expected=$(cache_group=dynamic cache_key=date cache.invoke "sleep 1; eval echo \$dynamic")
  sleep 1
  test.verify "cache3 - dynamic answer" "cache_group=dynamic cache_key=date cache.invoke \"sleep 1; eval echo \$dynamic\"" "$expected"
  sleep 1
  test.verify "cache3 - dynamic answer" "cache_group=dynamic cache_key=date cache.invoke \"sleep 1; eval echo \$dynamic\"" "$expected"

  dynamic='$(date)'
  expected=$(cache.invoke "sleep 1; echo; eval echo $dynamic")
  sleep 1
  test.verify "cache4 - dynamic answer" "cache.invoke \"sleep 1; echo; eval echo \$dynamic\"" "$expected"
  sleep 1
  test.verify "cache4 - dynamic answer" "cache.invoke \"sleep 1; echo; eval echo \$dynamic\"" "$expected"

  dynamic='$(curl http://worldclockapi.com/api/json/utc/now)'
  expected=$(cache.invoke "sleep 1; echo; eval echo $dynamic")
  sleep 1
  test.verify "cache5 - dynamic answer" "cache.invoke \"sleep 1; echo; eval echo \$dynamic\"" "$expected"
  sleep 1
  test.verify "cache5 - dynamic answer" "cache.invoke \"sleep 1; echo; eval echo \$dynamic\"" "$expected"

  cache_invoke_filter="tr '[a-z]' '[A-Z]'"
  test.verify "cache6 - cache filter" "cache_group=echo cache_key=hello6 cache.invoke echo hello" HELLO
  test.verify "cache6 - cache filter" "cache_group=echo cache_key=hello6 cache.invoke :" HELLO
  test.verify "cache6 - read directly from cache directory" "cat $cache_dir/echo/hello6" HELLO
  unset cache_invoke_filter

  cache_invoke_filter="tr '[a-z]' '[A-Z]'"
  cache_response_filter="tr '[A-Z]' '[a-z]'"
  test.verify "cache7 - cache filter" "cache_group=echo cache_key=hello7 cache.invoke echo hello" hello
  test.verify "cache7 - cache filter" "cache_group=echo cache_key=hello7 cache.invoke :" hello
  test.verify "cache7 - read directly from cache directory" "cat $cache_dir/echo/hello7" HELLO
  unset cache_invoke_filter
  unset cache_response_filter

  cache_crypto_key=$HOME/.ssh/id_rsa
  cache_crypto_cipher=aes-256-cbc
  cache_invoke_filter="openssl $cache_crypto_cipher -a -pass file:$cache_crypto_key"
  cache_response_filter="openssl $cache_crypto_cipher -d -a -pass file:$cache_crypto_key"
  test.verify "cache8 - cache cipher" "cache_group=echo cache_key=hello8 cache.invoke echo hello" hello
  test.verify "cache8 - cache cipher" "cache_group=echo cache_key=hello8 cache.invoke :" hello
  unset cache_response_filter
  unset cache_invoke_filter
  unset crypto_key
  unset crypto_cipher

  cache_crypto_key=$HOME/.ssh/id_rsa
  cache_crypto_cipher=aes-256-cbc
  test.verify "cache9 - cache cipher" "cache_group=echo cache_key=hello9 cache.invoke echo hello" hello
  test.verify "cache9 - cache cipher" "cache_group=echo cache_key=hello9 cache.invoke :" hello
  unset cache_crypto_key
  unset cache_crypto_cipher

  cache_crypto_key=$HOME/.ssh/id_rsa
  test.verify "cache9a - cache cipher" "cache_group=echo cache_key=hello9a cache.invoke echo hello9a" hello9a
  test.verify "cache9a - cache cipher" "cache_group=echo cache_key=hello9a cache.invoke :" hello9a
  unset cache_crypto_key

  # big files
  rm -rf $cache_dir/download
  mkdir -p $cache_dir/download
  url='curl https://freetestdata.com/wp-content/uploads/2022/02/Free_Test_Data_5MB_AVI.avi'
  cache_group=download cache_key=file10 cache.invoke $url > $cache_dir/download/file10.stream
  test.verify "cache10 - 5MB file" "cache_group=download cache_key=file10 cache.invoke $url | sha1sum" "$(cat $cache_dir/download/file10.stream | sha1sum)"

  rm -rf $cache_dir/download
  mkdir -p $cache_dir/download
  cache_crypto_key=$HOME/.ssh/id_rsa
  cache_crypto_cipher=aes-256-cbc
  url='curl https://freetestdata.com/wp-content/uploads/2022/02/Free_Test_Data_5MB_AVI.avi'
  cache_group=download cache_key=file11 cache.invoke $url > $cache_dir/download/file11.stream
  test.verify "cache10 - 5MB file" "cache_group=download cache_key=file11 cache.invoke $url | sha1sum" "$(cat $cache_dir/download/file11.stream | sha1sum)"
  unset cache_crypto_key
  unset cache_crypto_cipher

  filter=$(cat $cache_dir/download/file11.info | grep "^cache_response_filter=" | cut -f2-999 -d=)
  test.verify "cache10 - 5MB file - apply filter check" "cat $cache_dir/download/file11 | $filter | sha1sum" "$(cat $cache_dir/download/file11.stream | sha1sum)"
  test.verify "cache10 - 5MB file - openssl decrypt check" "cat $cache_dir/download/file11 | openssl aes-256-cbc -d -a -pass file:/home/pmaker/.ssh/id_rsa | sha1sum" "$(cat $cache_dir/download/file11.stream | sha1sum)"


}

function cache.test() {

  script_bin=$(dirname "$BASH_SOURCE" 2>/dev/null)

  if [ ! -f $script_bin/unit_test.bash ]; then
    echo
    echo "$script_name: Critical error. Required unit_test.bash library not found in script path. Test will not be executed."
    exit 1
  fi

  source $script_bin/unit_test.bash

  cache.test_group1_init
  cache.test_group1
  cache.test_group1_results
  cache.test_group1_clean
}

#
# default run
#

if [[ $0 == "$BASH_SOURCE" ]] ; then
  cat <<_info_EOF 
Do not run this bash library. It's is intended to be used by source cache.bash. Use cache.help to learn how to use the library."
As you started - executing exemplary test to let you know how to use the library.

_info_EOF

  cache.test
fi
