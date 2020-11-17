#!/bin/bash

function getcfg() {
    which=$1
    what=$2

    if [ $# -lt 2 ]; then
        echo Nothing to do....
        return 1
    fi

    value_row=$(cat ~/.$which/config | grep "^$what=")
    if [ $? -eq 0 ]; then
        echo $value_row | cut -d= -f2
    fi
}

function setcfg() {
    which=$1
    what=$2
    new_value=$3

    if [ $# -lt 2 ]; then
        echo Nothing to do....
        return 1
    fi

    if [ -z "$new_value" ]; then
        read -p "Enter value for $what:" new_value
    fi
    mkdir -p ~/.$which
    if [ -f ~/.$which/config ]; then
        #echo adding config file...
        echo "# Added by $USER($SUDO_USER) on $(date -I)" >> ~/.$which/config 
        echo "$what=$new_value" >> ~/.$which/config 
    else
        #echo creating config file...
        echo "# Added by $USER($SUDO_USER) on $(date -I)" > ~/.$which/config 
        echo "$what=$new_value" >> ~/.$which/config 
    fi
}

function getsetcfg() {
    which=$1
    what=$2
    new_value=$3

    if [ $# -lt 2 ]; then
        echo Nothing to do....
        return 1
    fi

    value_row=$(cat ~/.$which/config 2>/dev/null | grep "^$what=" | tail -1)
    if [ $? -eq 0 ]; then
        echo $value_row | cut -d= -f2
    else
        setcfg $@
    fi
    unset new_value
}

