#!/bin/bash


function rn() {
    sed 's/null//g'
}

function y2j() {
    python -c "import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))"
}


function fix_permissions_rsync() {
    diag_cfg=$1

    : ${diag_cfg:=~/.x-ray/diagnose.yaml}

    diagname=$(basename $diag_cfg | cut -f1 -d. | cut -f2-999 -d'-')
    if [ "$diagname" == diagnose ]; then
        diagname=general
    fi

    logs=$(cat $diag_cfg | y2j | jq -r ".diagnose | keys[]")

    for log in $logs
    do
        echo "##########################################"
        echo "Processing diagnostics source: $diagname/$log"
        echo "##########################################"

        src_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.dir" | rn)
        expose_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.dir" | rn)

        fix_permissions "$src_dir" "$expose_dir" "$diagname\_$log"
    done
}

function fix_permissions() {
    src_dir=$1
    expose_dir=$2
    name=$3

    : ${name:=initial_rsync}


    echo "##########################################"
    echo "Processing fix permissions sync: $src_dir $expose_dir $name"
    echo "##########################################"

    find $expose_dir -type d | xargs chmod g+rx 
    find $expose_dir -type d | xargs chmod o+rx 

    find $expose_dir -type f | xargs chmod g+r 
    find $expose_dir -type f | xargs chmod o+r 

 }

fix_permissions_rsync $@
