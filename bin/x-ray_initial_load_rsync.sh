#!/bin/bash

function getCfgValue() {
  cfg_yaml=$1
  jq_query=$2

  desc='Reads values from yaml file using jq query syntax. 
  To make it possible python one liner is used to convert yaml to json.
  As sometimes python may be not availabe on host, uses json file as backup.
  '

  if [ ! -f $cfg_yaml ]; then
    echo "Error. Configuration file not found: $cfg_yaml" >&2
    return 1
  fi

  cfg_json=${cfg_yaml%.yaml}.json

  python -c "import json, sys, yaml ; y=yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))" < $cfg_yaml 2>/dev/null | 
  jq -r "$jq_query" | sed 's/null//g'
  RC1=( "${PIPESTATUS[@]}" )
  if [ "${RC1[0]}" -ne 0 ]; then
      cat $cfg_json | jq -r "$jq_query" | sed 's/null//g'
      RC2=( "${PIPESTATUS[@]}" )
      if [ "${RC2[0]}" -ne 0 ]; then
          echo "Error converting yaml to json, and json file is not available." >&2
          return 2
      elif [ "${RC2[1]}" -ne 0 ]; then
          echo "Error getting data." >&2
          return 3
      fi
  elif [ "${RC1[1]}" -ne 0 ]; then
          echo "Error getting data." >&2
          return 3
  fi
}


function initial_load_rsync() {
    diag_cfg=$1

    : ${diag_cfg:=~/.x-ray/diagnose.yaml}

    diagname=$(basename $diag_cfg | cut -f1 -d. | cut -f2-999 -d'-')
    if [ "$diagname" == diagnose ]; then
        diagname=general
    fi

    logs=$(getCfgValue $diag_cfg ".diagnose | keys[]")

    if [ -z "$logs" ]; then
        echo "Error reading log sync descriptor."
        exit 1
    fi

    for log in $logs
    do
        echo "##########################################"
        echo "Processing diagnostics source: $diagname/$log"
        echo "##########################################"

        mode=$(getCfgValue $diag_cfg ".diagnose.$log.mode" )
        : ${mode:=flat2date}

        src_dir=$(getCfgValue $diag_cfg ".diagnose.$log.dir" )
        expose_dir=$(getCfgValue $diag_cfg ".diagnose.$log.expose.dir" )

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


function mkdir_force() {
  dst_dir=$1

  mkdir -p $dst_dir 2>/dev/null
  if [ $? -ne 0 ]; then
    parent_dir=$(dirname $dst_dir)
    
    # removed sudo
    # sudo chmod 777 $parent_dir
    chmod 777 $parent_dir
  fi

  mkdir -p $dst_dir
  if [ $? -ne 0 ]; then
    echo "Error creating directory."
    return 1
  fi
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

    if [ ! -d "$src_dir" ]; then
        echo "Error. Source directory does not exist: $src_dir"
        exit 1
    fi

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
        #mkdir -p $dst_dir
        mkdir_force $dst_dir
        chmod g+rx $dst_dir
        chmod o+rx $dst_dir

        if [ ! -d "$dst_dir" ]; then
            echo "Error. Destination directory does not exist: $dst_dir"
            exit 1
        fi
        
        # chmod does not work properly on some rsync e.g. 3.0.6; added  umask to fix        
        umask 022
        #rsync  --dry-run \
        rsync --progress -h \
        -t \
        --chmod=Fu=rw,Fgo=r,Dgo=rx,Du=rwx \
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

    if [ ! -d $src_dir ]; then
        echo "Error. Source directory does not exist: $src_dir"
        exit 1
    fi

    cd $src_dir
    find . -type f > $iload_tmp/sync_files
    cd - > /dev/null

    # chmod does not work properly on some rsync e.g. 3.0.6; added  umask to fix        
    umask 022

    # rsync does not create dst_dir? 
    # building file list ... 
    # 101 files to consider
    # rsync: mkdir "/mwlogs/x-ray/preprod/soa/diag/wls/alert/soa_domain/osb_server1" failed: No such file or directory (2)
    # rsync error: error in file IO (code 11) at main.c(657) [Receiver=3.1.2]
    # rsync creates dst dir, but create to have right permissions
    #mkdir -p $dst_dir
    mkdir_force $dst_dir
    chmod g+rx $dst_dir
    chmod o+rx $dst_dir

    #rsync  --dry-run \
    rsync --progress -h \
    -t \
    --chmod=Fu=rw,Fgo=r,Dgo=rx,Du=rwx \
    --files-from=$iload_tmp/sync_files \
    $src_dir $dst_dir

    rm -rf $iload_tmp
 }

initial_load_rsync $@
