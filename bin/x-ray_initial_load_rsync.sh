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

        mode=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.mode" | rn)
        : ${mode:=flat2date}

        src_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.dir" | rn)
        expose_dir=$(cat $diag_cfg | y2j | jq -r ".diagnose.$log.expose.dir" | rn)

        case $mode in
        flat2date)
            initial_rsync_flat2date "$src_dir" "$expose_dir" "${diagname}_${log}"
            ;;
        date2date)
            initial_rsync_date2date "$src_dir" "$expose_dir" "${diagname}_${log}"
            ;;
        *)
            echo "Error. Sync mode unknown: $mode. Cannot continue"
            exit 1
            ;;
        esac
    done
}

function initial_rsync_flat2date() {
    src_dir=$1
    expose_dir=$2
    name=$3

    : ${name:=initial_rsync_flat2date}
    iload_tmp=~/tmp/initialload.$name
    rm -rf $iload_tmp
    mkdir -p $iload_tmp

    todayiso8601="\$(date -I)"

    echo "##########################################"
    echo "Processing initial sync in flat2date modes: $src_dir $expose_dir $name"
    echo "##########################################"

    # in fact: replace $(date -I) into current date.
    src_dir=$(echo "$src_dir" | sed "s/$todayiso8601/$(date -I)/g" | sed "s/\$(hostname)/$(hostname)/g")

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

        # rsync creates dst dir, but create to have right permissions
        mkdir -p $dst_dir
        chmod g+rx $dst_dir
        chmod o+rx $dst_dir

        # chmod does not work properly on some rsync e.g. 3.0.6; added  umask to fix        
        umask 022
        #rsync  --dry-run \
        rsync --progress -h \
        -t \
        --chmod=Fu=r,Fgo=r,Dgo=rx,Du=rwx \
        --files-from=$iload_tmp/$date_file \
        $src_dir $dst_dir

        rm -rf $iload_tmp/$date_file
    done

    rm -rf $iload_tmp
 }


function initial_rsync_date2date() {
    src_dir=$1
    expose_dir=$2
    name=$3

    : ${name:=initial_rsync_date2date}
    iload_tmp=~/tmp/initialload.$name
    rm -rf $iload_tmp
    mkdir -p $iload_tmp

    todayiso8601="\$(date -I)"

    echo "##########################################"
    echo "Processing initial sync in date2date modes: $src_dir $expose_dir $name"
    echo "##########################################"

    # in fact: remove $(date -I) from end of path
    src_dir=$(echo "$src_dir" | sed "s/$todayiso8601$//g" | sed "s/\$(hostname)/$(hostname)/g")
    dst_dir=$(echo "$expose_dir" | sed "s/$todayiso8601$//g" | sed "s/\$(hostname)/$(hostname)/g")

    cd $src_dir
    find . -type f > $iload_tmp/sync_files
    cd - >/dev/null

    # chmod does not work properly on some rsync e.g. 3.0.6; added  umask to fix        
    umask 022

    # rsync does not create dst_dir? 
    # building file list ... 
    # 101 files to consider
    # rsync: mkdir "/mwlogs/x-ray/preprod/soa/diag/wls/alert/soa_domain/osb_server1" failed: No such file or directory (2)
    # rsync error: error in file IO (code 11) at main.c(657) [Receiver=3.1.2]
    # rsync creates dst dir, but create to have right permissions
    mkdir -p $dst_dir
    chmod g+rx $dst_dir
    chmod o+rx $dst_dir

    #rsync  --dry-run \
    rsync --progress -h \
    -t \
    --chmod=Fu=r,Fgo=r,Dgo=rx,Du=rwx \
    --files-from=$iload_tmp/sync_files \
    $src_dir $dst_dir

    rm -rf $iload_tmp
 }

initial_load_rsync $@
