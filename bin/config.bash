#!/bin/bash

#
# TODO
#

#
# PROGRESS
#

#
# DONE
#
# added self test routines
# handle running as script / sourcing

function config._getcfg(){
    source=$1
    which=$2
    what=$3
    info=$4

    value_row=$(cat $source 2>/dev/null | grep "^$what=" | tail -1 | grep "^$what=" )
    if [ $? -eq 0 ]; then
        if [ "$info" == show_file ]; then
            echo "$which/$what has value $(echo $value_row | cut -d= -f2-999) stored in config file: $source"
            return 0
        else
            echo $value_row | cut -d= -f2-999
            return 0
        fi
    fi

    return 1
}

function config.getcfg() {
    which=$1
    what=$2
    info=$3

    if [ $# -lt 2 ]; then
        >&2 echo Nothing to do....
        return 1
    fi

    # read preference: from local, global, and old local
    config._getcfg ~/.config/$which $@ || config._getcfg /etc/$which.config $@ || config._getcfg ~/.$which/config $@

    return $?
}

function config.setcfg() {
    which=$1
    what=$2
    new_value=$3
    force=$4

    if [ $# -lt 2 ]; then
        >&2 echo Nothing to do....
        return 1
    fi

    if [ -z "$new_value" ]; then
        read -p "Enter value for $what:" new_value
    fi

    # test of special characters
    new_value_clean=$(tr -dc '[[:print:]]' <<< "$new_value")
    if [ "$new_value_clean" != "$new_value" ]; then
      >&2 echo "Error. Entered value contains special characters as e.g. new lines, what is forbidden. Enter only pritable characters. This is critical error. Cannot continue."
      return 1
    fi

    unset global

    case $force in
    force)
      global=Y
      ;;
    global)
      global=Y
      ;;
    local)
      global=N
      ;;
    *)
      if [ "$force" != force ]; then
          read -t 5 -p "Set in global /etc/$which.config? [Yn]" global
      fi
      : ${global:=Y}
      global=$(echo $global | tr [a-z] [A-Z])
      ;;
    esac

    # check if it's possible to store data in /etc (sudo)
    case $global in
    Y)  
        timeout -s 9 1 sudo -S touch /etc/$which.config >/dev/null 2>/dev/null
        if [ $? -ne 0 ]; then
            >&2 echo "Notice that config can't be stored in /etc/$which.config, as this user has no root access. Config is stored in user space at ~/.x-ray/config. It's not a problem."
            global=N
        else
            timeout -s 9 1 sudo chmod 644 /etc/$which.config
        fi
        ;;
    esac
    
    case $global in
    Y)
        if [ -f /etc/$which.config ]; then
            cat /etc/$which.config | grep "^$what=" | tail -1 | grep "^$what=$new_value$" >/dev/null
            if [ $? -eq 0 ]; then
                >&2 echo "Entry is already in place."
                return 0
            else
                #echo adding config file...
                echo "# Added by $USER($SUDO_USER) on $(date -I)" | sudo tee -a /etc/$which.config  >/dev/null
                echo "$what=$new_value" | sudo tee -a /etc/$which.config  >/dev/null
            fi
        else
            #echo creating config file...
            echo "# Added by $USER($SUDO_USER) on $(date -I)" | sudo tee /etc/$which.config  >/dev/null
            echo "$what=$new_value" | sudo tee -a /etc/$which.config >/dev/null
        fi
        ;;
    *)
        mkdir -p ~/.config
        if [ -f ~/.config/$which ]; then
            cat ~/.config/$which | grep "^$what=" | tail -1 | grep "^$what=$new_value$" >/dev/null
            if [ $? -eq 0 ]; then
                >&2 echo "Entry is already in place."
            else
                #echo adding config file...
                echo "# Added by $USER($SUDO_USER) on $(date -I)" >> ~/.config/$which 
                echo "$what=$new_value" >> ~/.config/$which 
            fi
        else
            #echo creating config file...
            echo "# Added by $USER($SUDO_USER) on $(date -I)" > ~/.config/$which 
            echo "$what=$new_value" >> ~/.config/$which 
        fi
        ;;
    esac
    unset new_value

    return 0
}

function getsetcfg() {
    which=$1
    what=$2
    new_value=$3

    if [ $# -lt 2 ]; then
        >&2 echo Nothing to do....
        return 1
    fi

    value=$(config.getcfg $@)
    if [ $? -eq 0 ]; then
        echo $value
    else
        config.setcfg $@
        config.getcfg $1 $2
    fi
}


#
# test
# 

function config.test_group1_init() {
  sudo rm -f /etc/test_group1.config
  rm -f ~/.config/test_group1
  rm -f ~/.test_group1/config
}
function config.test_group1_results() {
  echo "Global /etc/test_group1.config:"
  cat /etc/test_group1.config
  echo 
  echo "Local  ~/.config/test_group1:"
  cat ~/.config/test_group1
}

function config.test_group1_clean() {
  sudo rm -f /etc/test_group1.config
  rm -f ~/.config/test_group1
  rm -f ~/.test_group1/config
}
function config.test_group1() {
  test_group=test_group1

  cat > $test_group <<EOF
"regular use - set" "config.setcfg test_group1 key1 val1 force"
"regular use - get" "config.getcfg test_group1 key1" "val1"
"special characters - rejected set" "config.setcfg test_group1 key2 \"val$(echo $"\010\013")1\" force" "" 1 "Error. Entered value contains special characters as e.g. new lines, what is forbidden. Enter only pritable characters. This is critical error. Cannot continue."
"equal character in value - set" "config.setcfg test_group1 key3 val1=char force"
"equal character in value - get" "config.getcfg test_group1 key3" "val1=char"
"space in value - set" "config.setcfg test_group1 key4 \"val1 space\" force"
"space in value - get" "config.getcfg test_group1 key4" "val1 space"
"local use - set" "config.setcfg test_group1 key5 val5 local"
"local use - check file" "ls ~/.config/test_group1" /home/pmaker/.config/test_group1
"local use - get" "config.getcfg test_group1 key5" "val5"
"global use - set" "config.setcfg test_group1 key6 val6 global"
"global use - get" "config.getcfg test_group1 key6" "val6"
"local use to override global - set" "config.setcfg test_group1 key6 val65local local"
"local use to override global - get" "config.getcfg test_group1 key6" "val65local"
"regular use - set with default force" "config.setcfg test_group1 key7 val7"
"Y after command with read to send Y"
"regular use - get with default force" "config.getcfg test_group1 key7" "val7"
EOF
  test.verify $test_group

  #tested separetly due to read fron stdin
  test.verify "regular use - set with default force" "config.setcfg test_group1 key8 val8"
  test.verify "regular use - get with default force" "config.getcfg test_group1 key8" "val8"
}

function config.test() {

  if [ ! -f $(dirname "$0" 2>/dev/null)/unit_test.bash ]; then
    echo
    echo "$script_name: Critical error. Required unit_test.bash library not found in script path. Test will not be executed."
    exit 1
  fi

  source $(dirname "$0" 2>/dev/null)/unit_test.bash

  config.test_group1_init
  config.test_group1
  config.test_group1_results
  config.test_group1_clean
}

#
# default run
#

if [[ $0 == "$BASH_SOURCE" ]] ; then
  echo "Do not run this bash library. It's is intended to be used by source config.bash"
  echo "As you started - executing exemplary test to let you know how to use the library."
  echo 

  config.test
fi

