#!/bin/bash

#
# TODO
#
# fix temp_dir

#
# PROGRESS
#

#
# DONE
#
# initial version


temp_dir=~/tmp
mkdir -p $temp_dir

unset test_name
declare -A test_name
unset test_code
declare -A test_code
unset test_result
declare -A test_result

function test._verify() {
  local name=$1
  local code=$2
  local expected_result_stdout=$3
  local expected_result_exit=$4
  local expected_result_stderr=$5

  : ${expected_result_exit:=0}
  
  code_id=$(echo "$name $code" | sha1sum | cut -f1 -d' ' )
  test_name[$code_id]="$name"
  test_code[$code_id]="$cmd"

  echo -n "$name "
  # eval must be used to handle params with space properly
  (eval $code) >$temp_dir/$code_id.stdout 2>$temp_dir/$code_id.sterr
  exit_code=$?

  if [ "$(cat $temp_dir/$code_id.stdout)" != "$expected_result_stdout" ]; then
    echo Error
    test_result[$code_id]=error
    echo 

    echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    cat $temp_dir/$code_id.stdout
    cat $temp_dir/$code_id.sterr
    echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'

  else
    echo OK
    test_result[$code_id]=ok
  fi
}

function test._verify_fromfile() {
  local test_file=$1

  local id=0
  local id_prev=0
  while IFS='
  ' read -r test_params
  do
      id_prev=$id
      id=$(( $id + 1 ))
      eval verify $test_params
  done < $test_file
}


function test.verify() {
  local name=$1
  local code=$2
  local expected_result_stdout=$3
  local expected_result_exit=$4
  local expected_result_stderr=$5

  if [ -f "$name" ]; then
    test._verify_fromfile $name
  else
    test._verify "$name" "$code" "$expected_result_stdout" "$expected_result_exit" "$expected_result_stderr"
  fi
}

function test.results(){
  for code_id in ${!test_name[@]}; do
    echo "${test_name[$code_id]}: ${test_result[$code_id]}"
  done
}

#
# exemplary test
#

function test.test_group1() {
  verify "simple math  - direct" "echo $((2+2))" 4
  verify "simple math2 - computed result" "echo $((2+2))" $(echo 4)

  function test.code2test(){
    echo $((2+2))
  }
  verify "simple math3 - test function" code2test $(echo 4)

  function test.code2expect(){
    echo 4
  }
  verify "simple math4 - test function, result function" code2test $(code2expect)
}
test_group1


