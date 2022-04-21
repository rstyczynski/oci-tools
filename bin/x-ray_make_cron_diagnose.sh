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


function mkdir_force() {
  dst_dir=$1

  mkdir -p $dst_dir 2>/dev/null
  if [ $? -ne 0 ]; then
    parent_dir=$(dirname $dst_dir)
    sudo chmod 777 $parent_dir
  fi

  mkdir -p $dst_dir
  if [ $? -ne 0 ]; then
    echo "Error creating directory."
    return 1
  fi
}

function schedule_diag_sync() {
    diag_cfg=$1
    cron_action=$2
    run_mode=$3

    : ${diag_cfg:=~/.x-ray/diagnose.yaml}
    : ${cron_action:=create}
    : ${run_mode:=TEST}

    diagname=$(basename $diag_cfg | cut -f1 -d. | cut -f2-999 -d'-')
    if [ "$diagname" == diagnose ]; then
        diagname=general
    fi

    backup_dir=$(getCfgValue $diag_cfg ".backup.dir")

    logs=$(getCfgValue $diag_cfg ".diagnose | keys[]")

    if [ -z "$logs" ]; then
        echo "Error reading log sync descriptor."
        exit 1
    fi

    rm -rf diag_sync.cron
    if [ -f diag_sync.cron ]; then
        echo "Error: cannot delete tmp cron file."
        exit 1
    fi

    cron_section_start="# START - diagnostics source - $diagname"
    cron_section_stop="# STOP - diagnostics source - $diagname"

    if [ "$cron_action" == remove ]; then

        (crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d") | crontab -

        exit 0
    fi

    #
    # prepare cron
    #
    echo "####################################"
    echo "###Preparing cron for $diagname"
    echo "####################################"

    echo $cron_section_start >>diag_sync.cron

    log_no=0
    for log in $logs; do
        log_no=$(($log_cnt + 1))
        echo "##########################################"
        echo "Processing diagnostics source: $diagname/$log"
        echo "##########################################"

        src_dir=$(getCfgValue $diag_cfg ".diagnose.$log.dir" )

        src_dir_mode=$(getCfgValue $diag_cfg ".diagnose.$log.mode" )
        : ${src_dir_mode:=default}
        case $src_dir_mode in
        date2date)
            # remove data from src directory. all purge operations are performed one step above date directory
            purge_src_dir=$(dirname "$src_dir")
            ;;
        *)
            purge_src_dir=$src_dir
            ;;
        esac

        type=$(getCfgValue $diag_cfg ".diagnose.$log.type" )
        : ${type:=log}
        ttl=$(getCfgValue $diag_cfg ".diagnose.$log.ttl" )
        : ${ttl:=15}
        ttl_filter=$(getCfgValue $diag_cfg ".diagnose.$log.ttl_filter" )
        : ${ttl_filter:='.'}

        expose_cycle=$(getCfgValue $diag_cfg ".diagnose.$log.expose.cycle" )
        : ${expose_cycle:="* * * * *"}
        expose_dir=$(getCfgValue $diag_cfg ".diagnose.$log.expose.dir" )

        # expose only younger than expose_age. Prevents syncing old files.
        expose_age=$(getCfgValue $diag_cfg ".diagnose.$log.expose.age" )
        : ${expose_age:=1}

        # exspose only files from expose_depth directory depth. Prevents syncing whoe directory structure
        expose_depth=$(getCfgValue $diag_cfg ".diagnose.$log.expose.depth" )
        : ${expose_depth:=1}

        expose_delete_before=$(getCfgValue $diag_cfg ".diagnose.$log.expose.delete_before" )
        if [ ! -z "$expose_delete_before" ]; then
            expose_delete_before_cmd="rm -f $expose_dir/$expose_delete_before;"
        else
            unset expose_delete_before_cmd
        fi

        expose_ttl=$(getCfgValue $diag_cfg ".diagnose.$log.expose.ttl" )
        : ${expose_ttl:=45}
        expose_access=$(getCfgValue $diag_cfg ".diagnose.$log.expose.access" )
        : ${expose_access:=+r}

        archive_dir=$(getCfgValue $diag_cfg ".diagnose.$log.archive.dir")

        archive_dir=$(getCfgValue $diag_cfg ".diagnose.$log.archive.dir" )
        : ${archive_dir:=oci_os://$bucket}

        archive_cycle=$(getCfgValue $diag_cfg ".diagnose.$log.archive.cycle" )
        : ${archive_cycle:="1 0 * * *"}
        archive_ttl=$(getCfgValue $diag_cfg ".diagnose.$log.archive.ttl" )
        : ${archive_ttl:=90}

        backup_root=$(getCfgValue $diag_cfg ".backup.dir" )
        : ${backup_root:=~/backup}
        backup_ttl=$(getCfgValue $diag_cfg ".backup.ttl" )
        : ${backup_ttl:=30}

        # not required here
        #oci_os_bucket=$(getCfgValue $diag_cfg ".diagnose.$log.archive.dir" | sed 's|oci_os://||')

        # keep diagnose.yaml next to archive file to make archive process be aware of config
	    org_umask=$(umask)
        umask 000
	    
        #mkdir -p $backup_dir/$(hostname)
        mkdir_force $backup_dir/$(hostname)
        umask $org_umask
	    #sudo chmod +x+w+r $backup_dir/$(hostname)
        cat $diag_cfg >$backup_dir/$(hostname)/$(basename $diag_cfg)

        #echo "$log, $src_dir, $type, $expose_dir, $expose_cycle, $expose_ttl"

        #
        # rsync files to central location
        #
        perform_rsync=yes
        echo "Source dir: $src_dir"
        echo "Expose dir: $expose_dir"
        if [ "$src_dir" == "$expose_dir" ]; then
            perform_rsync=no
        fi

        # chmod does not work properly on some rsync e.g. 3.0.6; added  umask to fix
        # umask 022 must be added to each cron

        if [ $perform_rsync == yes ]; then

            appendonly=no
            case $type in
            binary) ;;

            logrotate) ;;

            logappend)
                appendonly=yes
                ;;
            *) ;;

            esac

            case $appendonly in
            no)

                #
                # DO NOT USE % char i cron as ut has special meaning. % must be escaped by \% !!!!
                #

                # TODO: move $HOME/tmp/$diagname-$log.files to $expose_dir/$diagname-$log.inProgress

                cat >>diag_sync.cron <<EOF1
##############
# regular rsync: $log
##############

MAILTO=""
# rsync
$expose_cycle mkdir -p $expose_dir; if [ -f $HOME/tmp/$diagname-$log.files ]; then echo "\$(date +\%Y-\%m-\%dT\%H:\%M:\%S); rsync overload. Skipped this rsync round." >> $expose_dir/rsync.overload; else $expose_delete_before_cmd mkdir -p $HOME/tmp; cd $src_dir; find -maxdepth $expose_depth -mtime -$expose_age -type f > $HOME/tmp/$diagname-$log.files; umask 022; rsync  -t --chmod=Fu=r,Fgo=r,Dgo=rx,Du=rwx --files-from=$HOME/tmp/$diagname-$log.files $src_dir $expose_dir; rm  $HOME/tmp/$diagname-$log.files; fi

EOF1
                ;;

            yes)
                cat >>diag_sync.cron <<EOF2
##############
# append only rsync: $log
##############

MAILTO=""
# rsync
$expose_cycle mkdir -p $expose_dir; if [ -f $HOME/tmp/$diagname-$log.files ]; then echo "\$(date +\%Y-\%m-\%dT\%H:\%M:\%S); rsync overload. Skipped this rsync round." >> $expose_dir/rsync.overload; else $expose_delete_before_cmd mkdir -p $HOME/tmp; cd $src_dir; find -maxdepth $expose_depth -mtime -$expose_age -type f > $HOME/tmp/$diagname-$log.files; umask 022; rsync  -t --append --chmod=Fu=rw,Fgo=r,Dgo=rx --files-from=$HOME/tmp/$diagname-$log.files $src_dir $expose_dir; rm  $HOME/tmp/$diagname-$log.files; fi

EOF2
                ;;
            esac

        else

            cat >>diag_sync.cron <<EOF3
##############
# rsync not necessary as src dir is the same as expose dir. Taking care of chmod only.
##############

MAILTO=""
# chmod to give access to group and others
$expose_cycle chmod go+x${expose_access} $expose_dir; chmod go+${expose_access} $expose_dir/*; 

EOF3
        fi

        #
        # backup, and delete old files
        #


        cat >>diag_sync.cron <<EOF4
# backup, and delete old files
EOF4

        if [ "$ttl" != none ]; then

            # shift archive by a minute for each log entry. Note - will anyway run in parallel for different diag.yaml configs
            minute_shift=$(( $log_no % 60 ))
            echo $ttl | grep '\.' >/dev/null
            if [ $? -eq 0 ]; then
                archive_cycle_cron="$minute_shift */1 * * *"
            else
                archive_cycle_cron="$minute_shift 0 * * *"
            fi

            if [ -z $purge_src_dir ] || [ $purge_src_dir == '/' ] || [ $purge_src_dir == '~' ] || [ $purge_src_dir == "$HOME" ]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "purge_src_dir is empty or points to root / home directory! check configuration."
                exit 1
            fi

            if [[ $backup_dir != */x-ray/* ]]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "backup_dir must contain /x-ray/ subdirectory! check configuration."
                exit 1
            fi

            cat >>diag_sync.cron <<EOF5
MAILTO=""
$archive_cycle_cron ~/oci-tools/bin/x-ray_archive_source.sh $diagname $log $purge_src_dir $ttl $backup_dir

EOF5
        else
                cat >>diag_sync.cron <<EOF6
# archive skipped by configuration. archive_cycle is none.

EOF6
        fi

        #
        # permamanent delete from expose and backup locations
        #

        cat >>diag_sync.cron <<EOF8
# purge old files. files will be permanently delted
EOF8
        if [ "$expose_ttl" != none ]; then

            # shift purge start by a minute for each log entry. Note - will anyway run in parallel for different diag.yaml configs
            minute_shift=$(( $log_no % 60 ))

            echo $expose_ttl | grep '\.' >/dev/null
            if [ $? -eq 0 ]; then
                purge_cycle_cron="$minute_shift */1 * * *"
            else
                # add hour shift for different logs - it will distribute work a little 
                hour_shift=$(( $log_no % 12 ))
                purge_cycle_cron="$minute_shift $hour_shift * * *"
            fi

            # for expose dir with date, remove date part to operate on all dates
            expose_dir_no_date=$(echo $expose_dir | sed 's/\/\$todayiso8601//g')
            
            if [[ $expose_dir_no_date != */x-ray/* ]]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "expose_dir_no_date must contain /x-ray/ subdirectory! check configuration."
                exit 1
            fi

            if [[ $backup_dir != */x-ray/* ]]; then
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."
                echo "ERROR! BRAKING THE PROCEDURE."

                echo "backup_dir must contain /x-ray/ subdirectory! check configuration."
                exit 1
            fi

            cat >>diag_sync.cron <<EOF_purge_expose
# Archive old files from expose locations
MAILTO=""
$purge_cycle_cron ~/oci-tools/bin/x-ray_archive_expose.sh $diagname $log $expose_dir_no_date $expose_ttl $backup_dir

EOF_purge_expose

            cat >>diag_sync.cron <<EOF_purge_backup
# Archive old backup files locations (both source backup, and exspose backup).
MAILTO=""
$purge_cycle_cron ~/oci-tools/bin/x-ray_archive_backup.sh $diagname $log $backup_dir $backup_ttl

EOF_purge_backup

#
# purge archive
#
            cat >>diag_sync.cron <<EOF_purge_archive
# purge old archive files 
MAILTO=""
$purge_cycle_cron ~/oci-tools/bin/x-ray_archive_purge.sh $diagname $log $backup_dir $archive_ttl

EOF_purge_archive

        else
                cat >>diag_sync.cron <<EOF_purge_final
# purge skipped by configuration. expose_ttl is none.

EOF_purge_final

        fi

    # log loop
    done

    echo "#" >>diag_sync.cron
    echo "$cron_section_stop" >>diag_sync.cron


    if [ $run_mode == DEPLOY ]; then
        # 
        # update crontab
        #

        (
            crontab -l 2>/dev/null | sed "/$cron_section_start/,/$cron_section_stop/d"
            cat diag_sync.cron
        ) | crontab -

        #
        # cleanup
        #
        rm diag_sync.cron

        echo "=========================================="
        echo "Running in DEPLOY mode. Crontab  updated."
        echo "=========================================="
    else
        cat diag_sync.cron

        echo "=========================================="
        echo "Running in TEST mode. Crontab not updated."
        echo "=========================================="
    fi
}

# 1 - diag name
# 2 - action: create
# 3 - test run: yes | no
schedule_diag_sync $@
