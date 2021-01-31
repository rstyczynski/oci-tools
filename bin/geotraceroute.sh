#!/bin/bash

function sayatcell() {

    nl=yes
    if [ $1 == '-n' ]; then
        nl=no
        shift
    fi

    fr=no
    if [ $1 == '-f' ]; then
        fr=yes
        shift
    fi

    what=$1
    shift
    size=$1
    shift

    back='____________________________________________________________________________________________________________'
    back='                                                                                                            '
    dots='............................................................................................................'

    what_lth=$(echo -n $what | wc -c)

    if [ $what_lth -lt $size ]; then
        pre=$(echo "($size - $what_lth)/2" | bc)
        post=$(echo "$size - $what_lth - $pre" | bc)

        if [ $pre -gt 0 ]; then
            echo -n "$back" | cut -b1-$pre | tr -d '\n'
        fi

        echo -n "$what"

        if [ $post -gt 0 ]; then
            echo -n "$back" | cut -b1-$post | tr -d '\n'
        fi

    elif [ $what_lth -gt $size ]; then
        echo -n "$what" | cut -b1-$(($size - 2)) | tr -d '\n'
        echo -n "$dots" | cut -b1-2 | tr -d '\n'
    elif [ $what_lth -eq $size ]; then
        echo -n "$what"
    fi

    if [ $nl == yes ]; then
        if [ $fr == yes ]; then
            echo '|'
        else
            echo
        fi
    elif [ $fr == yes ]; then
        echo -n '|'
    fi
}

function geotraceroute() {
    target_ip=$1

    echo "geotraceroute to $target_ip"
    sayatcell -n -f address 20
    sayatcell -n -f location 20
    sayatcell -f latency 15

    hops_ms=$(traceroute -n $target_ip | grep -v traceroute | tr -d '*' | tr -s ' ' | sed 's/^ //g' | cut -f2,3 -d' ' | grep -v '^$' | tr ' ' ';')
    for hop_ms in $hops_ms; do
        hop=$(echo $hop_ms | cut -f1 -d ';')
        region=$(curl -s https://ipinsight.io/ip/$hop | grep -A1 Region | grep -v Region | tr -d ' ' | cut -f2 -d'>' | cut -f1 -d'<')

        sayatcell -n -f $hop 20
        sayatcell -n -f $region 20
        ms=$(echo $hop_ms | cut -f2 -d ';')
        sayatcell -f "$ms ms" 15
    done
}

geotraceroute $@
