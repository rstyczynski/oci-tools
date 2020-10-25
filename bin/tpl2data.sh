#!/usr/bash

function tpl2data() {
    template=$1

    : ${tmp:=/tmp}

    local error=no

    # to stop per from complaing about locale
    export LC_CTYPE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    # get vars from template
    # sort from longst ones to avoid partial replacement $var in place of $variable
    vars=$(cat $template | perl -ne 'while(/\$(\w+)/gm){print "$1\n";}' | sort -u | awk '{ print length, $0 }' | sort -n -s -r | cut -d" " -f2-)

    tmpfile=$tmp/$(basename $template).$$
    cat $template >$tmpfile

    # move bash like variable into format ||var||
    for var in $vars; do
        value=$(echo $(eval echo \$$var))
        : ${value:=\{\{$var\}\}}
        sed -i "s/\$$var/||$var||/g" $tmpfile
    done

    # substitute variables
    for var in $vars; do
        value=$(echo $(eval echo \$$var))
        if [ -z "$value" ]; then
            value=\$$var
            echo >&2 "Error: Variable $var has no value."
            error=yes
        fi
        value=$(echo $value | sed "s|/|\\\/|g")
        sed -i "s/||$var||/$value/g" $tmpfile
    done

    if [ "$error" == "no" ]; then
        cat $tmpfile
        rm $tmpfile
    else
        return 1
    fi
}

tpl2data $@
exit $?