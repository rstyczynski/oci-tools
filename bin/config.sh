#!/bin/bash

function getcfg() {
    which=$1
    what=$2

    if [ $# -lt 2 ]; then
        echo Nothing to do....
        return 1
    fi

    value_row=$(cat /etc/$which.config 2>/dev/null | grep "^$what=" | tail -1 | grep "^$what=" )
    if [ $? -eq 0 ]; then
        echo $value_row | cut -d= -f2
    else
            value_row=$(cat ~/.$which/config 2>/dev/null | grep "^$what=" | tail -1 | grep "^$what=" )
            if [ $? -eq 0 ]; then
                echo $value_row | cut -d= -f2
            else
                return $?
            fi
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

    read -t 5 -p "Set in global /etc/$which.config? [Yn]" global
    : ${global:=Y}
    global=$(echo $global | tr [a-z] [A-Z])

    case $global in
    Y)
        if [ -f /etc/$which.config ]; then
            grep "$what=$new_value"  /etc/$which.config >/dev/null
            if [ $? -eq 0 ]; then
                echo "Entry is already in place."
            else
                #echo adding config file...
                echo "# Added by $USER($SUDO_USER) on $(date -I)" | sudo tee -a /etc/$which.config
                echo "$what=$new_value" | sudo tee -a /etc/$which.config
            fi
        else
            #echo creating config file...
            echo "# Added by $USER($SUDO_USER) on $(date -I)" | sudo tee /etc/$which.config
            echo "$what=$new_value" | sudo tee -a /etc/$which.config
        fi
        ;;
    *)
        mkdir -p ~/.$which
        if [ -f ~/.$which/config ]; then
            grep "$what=$new_value" ~/.$which/config  >/dev/null
            if [ $? -eq 0 ]; then
                echo "Entry is already in place."
            else
                #echo adding config file...
                echo "# Added by $USER($SUDO_USER) on $(date -I)" >> ~/.$which/config 
                echo "$what=$new_value" >> ~/.$which/config 
            fi
        else
            #echo creating config file...
            echo "# Added by $USER($SUDO_USER) on $(date -I)" > ~/.$which/config 
            echo "$what=$new_value" >> ~/.$which/config 
        fi
        ;;
    esac
    unset new_value
}

function getsetcfg() {
    which=$1
    what=$2
    new_value=$3

    if [ $# -lt 2 ]; then
        echo Nothing to do....
        return 1
    fi

    value=$(getcfg $@)
    if [ $? -eq 0 ]; then
        echo $value
    else
        setcfg $@
    fi
}

