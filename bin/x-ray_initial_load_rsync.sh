#!/bin/bash


function rn() {
    sed 's/null//g'
}

function y2j() {
    python -c "import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))"
}


function initial_load_rsync() {
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

        initial_rsync "$src_dir" "$expose_dir" "$diagname\_$log"
    done
}

function initial_rsync() {
    src_dir=$1
    expose_dir=$2
    name=$3

    : ${name:=initial_rsync}
    iload_tmp=~/tmp/initialload.$name
    rm -rf $iload_tmp
    mkdir -p $iload_tmp

    todayiso8601="\$(date -I)"

    echo "##########################################"
    echo "Processing initial sync: $src_dir $expose_dir $name"
    echo "##########################################"


    IFS=$'\n'
    for file_meta in $(ls -la --time-style=full-iso $src_dir | grep -v '^d' | tr -s ' ' | tr ' ' ';' | grep -v '^total')
    do
        date=$(echo $file_meta | cut -f6 -d';')
        file=$(echo $file_meta | cut -f9 -d';')
        echo $file >> $iload_tmp/files.$date
    done

    for date_file in $(ls $iload_tmp)
    do
        date=$(echo $date_file | cut -f2 -d.)

        # in fact: replace $(date -I) into current date.
        dst_dir=$(echo "$expose_dir" | sed "s/$todayiso8601/$date/g" | sed "s/\$(hostname)/$(hostname)/g")

        mkdir -p $dst_dir
        
        #rsync  --dry-run \
        rsync --progress -h \
        -t --chmod=Fu=r,Fgo=r,Dgo=rx,Du=rwx \
        --files-from=$iload_tmp/$date_file \
        $src_dir $dst_dir

        rm -rf $iload_tmp/$date_file
    done

    rm -rf $iload_tmp
 }


initial_load_rsync $@
