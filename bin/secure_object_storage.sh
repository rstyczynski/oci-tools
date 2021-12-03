#!/bin/bash

DEBUG=NO
function DEBUG() {
  if [ $DEBUG == YES ]; then
    return 0
  else
    return 1
  fi
}

function secure_put() {
  bucket_name=$1
  file=$2
  public_key=$3
  cipher_set=$4

  : ${public_key:=~/.ssh/id_rsa.pub}
  : ${cipher_set:=aes-256-cbc}

  tmp=~/tmp; mkdir -p $tmp

  result=100

  # encrypt
  secret_put=$(openssl rand 32)
  if [ $? -eq 0 ]; then
    DEBUG && echo $secret_put | xxd -l 16 -p
    openssl $cipher_set -in $file -pass "pass:$secret_put" -out $tmp/$file.enc 
    if [ $? -eq 0 ]; then
      openssl rsautl -encrypt -oaep -pubin -inkey <(ssh-keygen -e -f $public_key -m PKCS8) -in <(echo $secret_put) -out $tmp/$file.key.enc
      if [ $? -eq 0 ]; then
        unset secret_put
        cd $tmp
        tar -cvf $file.tar $file.enc $file.key.enc
        if [ $? -eq 0 ]; then
          cd - >/dev/null
          rm $tmp/$file.enc $tmp/$file.key.enc
          # send
          oci os object put --bucket-name $bucket_name --file $tmp/$file.tar --name $file.secure --force      
          if [ $? -eq 0 ]; then
            rm $tmp/$file.tar
            result=0
          else
            result=5
          fi    
        else
          cd - >/dev/null
          result=4
        fi
      else
        result=3
      fi
    else
      result=2
    fi
  else
    result=1
  fi

  return $result

}

function secure_get() {
  bucket_name=$1
  file=$2
  private_key=$3
  cipher_set=$4

  : ${private_key:=~/.ssh/id_rsa}
  : ${cipher_set:=aes-256-cbc}

  tmp=~/tmp; mkdir -p $tmp

  result=100

  oci os object get --bucket-name $bucket_name --name $file.secure --file $tmp/$file.tar
  if [ $? -eq 0 ]; then
    cd $tmp
    tar -xvf $file.tar
    cd - >/dev/null
    if [ $? -eq 0 ]; then
      rm $tmp/$file.tar
      # decrypt
      secret_get=$(openssl rsautl -decrypt -oaep -inkey $private_key -in $tmp/$file.key.enc)
      if [ $? -eq 0 ]; then
        DEBUG && echo $secret_get | xxd -l 16 -p
        rm $tmp/$file.key.enc
        openssl $cipher_set -d -in $tmp/$file.enc -pass "pass:$secret_get" -out $file
        if [ $? -eq 0 ]; then
          unset secret_get
          rm $tmp/$file.enc 
          result=0
        else
          result=4
        fi
      else
        resut=3
      fi
    else
      result=2
    fi
  else
    result=1
  fi

  return $result
}

function secure_test() {
  bucket=$1 

  if [ -z $bucket ]; then
    echo "Error. Usage: secure_test bucket"
    return 1
  fi

  echo "Secure test no.1" > secure_test_1

  secure_put $bucket secure_test_1
  rm secure_test_1

  secure_get $bucket secure_test_1
  cat secure_test_1

  rm secure_test_1

  # test no.2 29kB file
  dd if=/dev/urandom of=secure_test_2 bs=2048 count=10
  md5sum secure_test_2 

  secure_put $bucket secure_test_2
  rm secure_test_2

  secure_get $bucket secure_test_2
  md5sum secure_test_2 

  rm secure_test_2

  # test no.3 100MB file
  dd if=/dev/urandom of=secure_test_3 bs=1048576 count=100
  md5sum secure_test_3 

  secure_put $bucket secure_test_3
  rm secure_test_3

  secure_get $bucket secure_test_3
  md5sum secure_test_3 

  rm secure_test_3

}

