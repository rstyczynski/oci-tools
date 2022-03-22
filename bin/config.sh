#!/bin/bash

function getcfg() {
    which=$1
    what=$2
    info=$3

    if [ $# -lt 2 ]; then
        >&2 echo Nothing to do....
        return 1
    fi

    value_row=$(cat /etc/$which.config 2>/dev/null | grep "^$what=" | tail -1 | grep "^$what=" )
    if [ $? -eq 0 ]; then
        if [ "$info" == show_file ]; then
            echo "$which/$what has value $(echo $value_row | cut -d= -f2) stored in config file: /etc/$which.config"
        else
            echo $value_row | cut -d= -f2
        fi
    else
            value_row=$(cat ~/.$which/config 2>/dev/null | grep "^$what=" | tail -1 | grep "^$what=" )
            if [ $? -eq 0 ]; then
                if [ "$info" == show_file ]; then
                    echo "$which/$what has value $(echo $value_row | cut -d= -f2) stored in config file: /etc/$which.config"
                else
                    echo $value_row | cut -d= -f2
                fi
            else
                return 1
            fi
    fi
}

function setcfg() {
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
    if [ "$force" != force ]; then
        read -t 5 -p "Set in global /etc/$which.config? [Yn]" global
    fi
    : ${global:=Y}
    global=$(echo $global | tr [a-z] [A-Z])

    case $global in
    Y)  
        timeout -s 9 1 sudo -S touch /etc/$which.config >/dev/null 2>/dev/null
        if [ $? -ne 0 ]; then
            >&2 echo "Notice that config can't be stored in /etc/x-ray.config, as this user has no root access. Config is stored in user space at ~/.x-ray/config. It's not a problem."
            unset global
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
            cat ~/.$which/config | grep "^$what=" | tail -1 | grep "^$what=$new_value$" >/dev/null
            if [ $? -eq 0 ]; then
                >&2 echo "Entry is already in place."
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
        >&2 echo Nothing to do....
        return 1
    fi

    value=$(getcfg $@)
    if [ $? -eq 0 ]; then
        echo $value
    else
        setcfg $@
        getcfg $1 $2
    fi
}




