#!/bin/bash

function tcpdump_start() {

    if [ "$pcap_dir_handle" == "dynamic" ]; then
        pcap_dir=$HOME/x-ray/traffic/$(date -I)
    fi

    mkdir -p ${pcap_dir}
    chmod 777 ${pcap_dir}

    echo "Starting capture at $netif of traffic to ${pcap_filter}..."

    if [ $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then

        # write props file with additional info. IP adress for now
        echo "HOST_IP:$(hostname -i)" > ${pcap_dir}/${tcp_file_pfx}.props

        echo "Invoking command: tcpdump -i $netif -U -w ${pcap_dir}/${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' "
        umask o+rw
        sudo -- bash -c "umask o+rw
            cd ${pcap_dir}; nohup tcpdump -Z $USER -i $netif -U -w ${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' > ${tcp_file_pfx}.out 2> ${tcp_file_pfx}.err
            chmod o+rw ${pcap_dir}/${tcp_file_pfx}.out
            chown $USER ${pcap_dir}/${tcp_file_pfx}.out

            chmod o+rw ${pcap_dir}/${tcp_file_pfx}.err
            chown $USER ${pcap_dir}/${tcp_file_pfx}.err
            " &
        echo "Started. Use dump|tail to check traffic. Use stop to finish capture."
    else
        echo "Already running"
        ps aux | grep tcpdump | grep ${tcp_file_pfx} 
    fi
}

function tcpdump_stop() {
        if [ $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then
            echo "Capture not running."
        else

            if [ "$pcap_dir_handle" == "dynamic" ]; then
                pcap_dir=$(ps aux | grep tcpdump | grep -oP "cd ([/a-zA-Z0-9\-_]+)" | head -1 | cut -d' ' -f2)
            fi

            echo -n "Stopping tdpdump at $netif of traffic to ${pcap_filter}..."
            sudo kill $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | tr -s ' ' | cut -d' ' -f2)
            echo "Done. Capture files in : ${pcap_dir}"
        fi
}

function tcpdump_wrapper() {
    pcap_filter=$1
    cmd=$2 
    pcap_dir_parameter=$3
    netif=$4

    : ${cmd:=status}
    : ${netif:=$(ip a | grep -i mtu | grep -v lo: | head -1 | tr -d ' ' | cut -f2 -d:)}

    if [ -z "$pcap_dir_parameter" ]; then
        pcap_dir_handle=dynamic
    else
        pcap_dir_handle=given
        pcap_dir=$pcap_dir_parameter
    fi

    tcp_file_pfx=tcpdump_filter_$(echo ${pcap_filter} | tr -c 'a-zA-Z0-9' '_')

    case $cmd in
    start)
        tcpdump_start
        ;;
    stop)
        tcpdump_stop
        ;;
    restart)
        tcpdump_stop
        sleep 2
        tcpdump_start
        ;;
    status)
        if [ $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then
            echo "Capture not running."
        else
            echo "Capture running"
            ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep
        fi
        ;;
    dump)

        if [ "$pcap_dir_handle" == "dynamic" ]; then
            pcap_dir=$(ps aux | grep tcpdump | grep -oP "cd ([/a-zA-Z0-9\-_]+)" | head -1 | cut -d' ' -f2)
            : ${pcap_dir:=pcap_dir=$HOME/x-ray/traffic/$(date -I)}
        fi

        echo "Dump of files from ${pcap_dir}:"
        if [ $(ls -t ${pcap_dir}/${tcp_file_pfx}_* 2>/dev/null | wc -l) -gt 0 ]; then
           for tcp_file in $(ls -t ${pcap_dir}/${tcp_file_pfx}_* 2>/dev/null); do
             tcpdump -A -nn -r  $tcp_file
           done
        else
           echo None.
        fi
        ;;
    tail)

        if [ "$pcap_dir_handle" == "dynamic" ]; then
            pcap_dir=$(ps aux | grep tcpdump | grep -oP "cd ([/a-zA-Z0-9\-_]+)" | head -1 | cut -d' ' -f2)
            : ${pcap_dir:=pcap_dir=$HOME/x-ray/traffic/$(date -I)}
        fi

        if [ $(ls -t ${pcap_dir}/${tcp_file_pfx}_* 2>/dev/null | wc -l) -gt 0 ]; then
           tcp_file=$(ls -t ${pcap_dir}/${tcp_file_pfx}_* | head -1)
           echo "Tail of $tcp_file:"
           tcpdump -A -nn -r $tcp_file | tail 
        else
           echo None.
        fi
        ;;
    '')
        echo "Usage: tcpdump_host ifname filter start|stop|status|dump|tail"
        ;;
    esac
}

#
#  reports
#

function tcpdump_show_egress() {
    pcap_dir=$1
    src_ip=$2

    : ${pcap_dir:=$HOME/x-ray/traffic/$(date -I)} 

    : ${tcpdump_show_egress_maxport:=15000}

    pcap_filter='tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0'
    tcp_file_pfx=tcpdump_filter_$(echo ${pcap_filter} | tr -c 'a-zA-Z0-9' '_')

    if [ "$tcpdump_show_egress_format" == CSV ]; then
        : ${tcpdump_show_egress_header:="direction,this,other,port"}
        echo $tcpdump_show_egress_header
    fi

    : ${src_ip:=$(cat ${pcap_dir}/${tcp_file_pfx}.props | grep -P "^HOST_IP:" | cut -d: -f2)}
    if [ -z "$src_ip" ]; then
        >&2 echo "Source IP not known. Specify as second parameter, after dirname with pcap files."
        return 1
    fi

    >&2 echo "Processing data from $src_ip stored at $pcap_dir"

    # TODO handle tmp properly
    tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null  |
    grep -P "^[\d:\.]+ IP $src_ip" |
    cut -d'>' -f2 |
    cut -d: -f1 |
    sort -u |
    cut -d'.' -f5 |
    sort -un >  /tmp/egress.ports

    random_ports_cnt=$(cat /tmp/egress.ports | awk "\$1 > $tcpdump_show_egress_maxport { print }" | wc -l)
    if [ $random_ports_cnt -gt 0 ];then
        >&2 echo 
        >&2 echo "Warning. High number of random destination ports detected. Possibly FTP communication."
        >&2 echo "         Report will be limited to low ports only. Set threshold using tcpdump_show_egress_maxport variable, having default value - 15000"
        >&2 echo 
    fi

    ports=$(cat /tmp/egress.ports | awk "\$1 < $tcpdump_show_egress_maxport { print }")
    rm /tmp/egress.ports

    if [ "$tcpdump_show_egress_format" == CSV ]; then
        for port in $ports; do
            hosts=$(tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
            grep -P "^[\d:\.]+ IP $src_ip" |
            cut -d'>' -f2 |
            cut -d: -f1 |
            sort -u |
            grep -P "$port$"|
            cut -d'.' -f1-4 |
            sort -u)
            for host in $hosts; do
                echo -n $tcpdump_show_egress_insert
                echo "egress,$src_ip,$host,$port"
                >&2 echo -n "."
            done
        done
        >&2 echo "."
    else
        for port in $ports; do
            echo -n " tcp $port:"
            tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
            grep -P "^[\d:\.]+ IP $src_ip" |
            cut -d'>' -f2 |
            cut -d: -f1 |
            sort -u |
            grep -P "$port$"|
            cut -d'.' -f1-4 |
            sort -u |
            tr '\n' ' '
            echo
        done
    fi
}

function tcpdump_show_ingress() {
    pcap_dir=$1
    dest_ip=$2

    : ${pcap_dir:=$HOME/x-ray/traffic/$(date -I)} 
    
    : ${tcpdump_show_ingress_maxport:=15000}

    pcap_filter='tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0'
    tcp_file_pfx=tcpdump_filter_$(echo ${pcap_filter} | tr -c 'a-zA-Z0-9' '_')

    if [ "$tcpdump_show_ingress_format" == CSV ]; then
        : ${tcpdump_show_ingress_header:="direction,other,this,port"}
        echo $tcpdump_show_ingress_header
    fi

    : ${dest_ip:=$(cat ${pcap_dir}/${tcp_file_pfx}.props | grep -P "^HOST_IP:" | cut -d: -f2)}
    if [ -z "$dest_ip" ]; then
        >&2 echo "Source IP not known. Specify as second parameter, after dirname with pcap files." 
        return 1
    fi

    >&2 echo "Processing data directed to $src_ip stored at $pcap_dir"

    # TODO fix tmp
    tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null  |
        perl -ne "m/^[\d:\.]+ IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > $dest_ip\.(\d+)/ && print \"\$3\n\"" |  
        sort -un > /tmp/ingress.ports

    random_ports_cnt=$(cat /tmp/ingress.ports | awk "\$1 > $tcpdump_show_ingress_maxport { print }" | wc -l)
    if [ $random_ports_cnt -gt 0 ];then
        >&2 echo 
        >&2 echo "Warning. High number of random destination ports detected. Possibly FTP communication."
        >&2 echo "         Report will be limited to low ports only. Set threshold using tcpdump_show_ingress_maxport variable, having default value - 15000"
        >&2 echo 
    fi

    ports=$(cat /tmp/ingress.ports | awk "\$1 < $tcpdump_show_ingress_maxport { print }")
    rm /tmp/ingress.ports

    if [ "$tcpdump_show_ingress_format" == CSV ]; then

        for port in $ports; do
            hosts=$(tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
                perl -ne "m/^[\d:\.]+ IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > $dest_ip\.(\d+)/ && print \"\$1\n\"" |
                sort -u)
            for host in $hosts; do
                echo -n $tcpdump_show_ingress_insert
                echo "ingress,$host,$dest_ip,$port"
                >&2 echo -n "."
            done
        done
        >&2 echo "."
    else
        for port in $ports; do
            echo -n " tcp $port:"
            tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
            perl -ne "m/^[\d:\.]+ IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > $dest_ip\.(\d+)/ && print \"\$1\n\"" |
            sort -u |
            tr '\n' ' '
            echo
        done
    fi
}

#
# x-ray log server reports
#

function x-ray_report_egress() {
  env=$1
  days=$2
  components=$3

  : ${days:=$(date -I | cut -d- -f1-2)}

  tcpdump_show_egress_format=CSV
  tcpdump_show_egress_header="date,env,component,host,direction,this,other,port"

  header_displayed=NO
  
  : ${components:=$(ls /mwlogs/x-ray/$env/)}

  for component in $components; do
    compute_instances=$(ls /mwlogs/x-ray/$env/$component/diag/hosts/)
    for compute_instance in $compute_instances; do
      for day in $(ls /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic | grep $days); do
        if [ "$header_displayed" == OK ]; then
          tcpdump_show_egress_header=" "
        fi
        tcpdump_show_egress_insert="$day,$env,$component,$compute_instance,"
        tcpdump_show_egress /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic/$day

        header_displayed=OK
      done
    done
  done

  unset tcpdump_show_egress_header
  unset tcpdump_show_egress_insert
}

function x-ray_report_ingress() {
  env=$1
  days=$2
  components=$3

  : ${days:=$(date -I | cut -d- -f1-2)}

  tcpdump_show_ingress_format=CSV
  tcpdump_show_ingress_header="date,env,component,host,direction,other,this,port"

  header_displayed=NO
  
  : ${components:=$(ls /mwlogs/x-ray/$env/)}

  for component in $components; do
    compute_instances=$(ls /mwlogs/x-ray/$env/$component/diag/hosts/)
    for compute_instance in $compute_instances; do
      for day in $(ls /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic | grep $days); do
        
        if [ "$header_displayed" == OK ]; then
          tcpdump_show_ingress_header=" "
        fi
        tcpdump_show_ingress_insert="$day,$env,$component,$compute_instance,"
        tcpdump_show_ingress /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic/$day
        header_displayed=OK
      done
    done
  done

  unset tcpdump_show_ingress_header
  unset tcpdump_show_ingress_insert
}


#
# network related functions
#

function get_cidr() {
  # compute host to CIDR mapping. Uses CIDR registry specified by CIDR_registry variable, having default value ~/network/etc/cidr_global_registry.csv
  host=$1

  : ${CIDR_registry:=~/network/etc/cidr_global_registry.csv}

  if [ ! -f $CIDR_registry ]; then
    >&2 echo "Error. CIDR registry file not found!"
    return 1
  fi

  type host2cidr 2>/dev/null
  if [ $? -eq 1 ]; then
    declare -gA host2cidr
  fi

  matched_cidr=${host2cidr[$host]}

  if [ ! -z "$matched_cidr" ]; then
    echo $matched_cidr
  else
    >&2 echo -n "Testing $host..."
    matched_cidr=""
    for cidr in $(cat $CIDR_registry | cut -d, -f1 | grep -v CIDR); do   
      grepcidr "$cidr" <(echo "$host") >/dev/null
      if [ $? -eq 0 ]; then
        matched_cidr="$(grep -P "^$cidr" $CIDR_registry)"
        host2cidr[$host]=$matched_cidr
        break
      fi
    done
    if [ ! -z "$matched_cidr" ]; then
      echo $matched_cidr
    else
      matched_cidr=$(grep -P "^254.254.254.254" $CIDR_registry | sed "s/UNKNOWN/$host\/32/")
      host2cidr[$host]=$matched_cidr
      echo "$matched_cidr"
    fi
  fi
}

function get_cidr2cidr_ports() {
  csv_file=$1

  CIDR_this_column=$(csv_column CIDR_this)
  CIDR_other_column=$(csv_column CIDR_other)
  desc_other_column=$(csv_column desc_other)
  port_column=$(csv_column port)

  columns=$(echo "$CIDR_this_column
  $CIDR_other_column
  $desc_other_column
  $port_column" | sort -n | tr '\n' , | tr -d ' ' | sed 's/,$//')

  columns_no_port=$(echo "$CIDR_this_column
  $CIDR_other_column
  $desc_other_column" | sort -n | tr '\n' , | tr -d ' ' | sed 's/,$//')

  echo $(csv_header | cut -d, -f$columns_no_port),ports
  IFS=$'\n'
  for cidr_meta in $(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | sort -u); do
    >&2 echo -n "."
    CIDR_pair_columns=$(echo $(csv_header | cut -d, -f$columns) | tr ',' '\n' | nl | tr -d ' ' | tr '\t' ' '  | grep CIDR | cut -f1 -d ' ' | tr '\n' ',' | sed 's/,$//')
    CIDR_pair=$(echo $cidr_meta | cut -d, -f$CIDR_pair_columns) 

    port_column=$(echo $(csv_header | cut -d, -f$columns) | tr ',' '\n' | nl | tr -d ' ' | tr '\t' ' '  | grep port | cut -f1 -d ' ' | tr '\n' ',' | sed 's/,$//')

    ports=$(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | grep $CIDR_pair | cut -d',' -f$port_column | sort -nu | tr '\n' ';' | sed 's/;$//')

    out_columns=$(echo $(csv_header | cut -d, -f$columns) | tr ',' '\n' | nl | tr -d ' ' | tr '\t' ' '  | egrep "CIDR|desc" | cut -f1 -d ' ' | tr '\n' ',' | sed 's/,$//')
    out=$(echo $cidr_meta | cut -d, -f$out_columns | grep $CIDR_pair)

    echo $out,$ports
  done | sort -u
  >&2 echo "."
  unset IFS
}


function get_cidr2cidr() {
  csv_file=$1

  CIDR_this_column=$(csv_column CIDR_this)
  CIDR_other_column=$(csv_column CIDR_other)
  desc_other_column=$(csv_column desc_other)

  columns=$(echo "$CIDR_this_column
  $CIDR_other_column
  $desc_other_column" | sort -n | tr '\n' , | tr -d ' ' | sed 's/,$//')

  echo $(csv_header | cut -d, -f$columns),count
  IFS=$'\n'
  for cidr_meta in $(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | sort -u); do
    count=$(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | grep "$cidr_meta" | wc -l)
    echo $cidr_meta,$count
  done
  unset IFS
}

function enrich_Xgress_with_subnets() {
  info='Enriches engress/ingress report with subnet information stored in CIDR_registry with default value of  ~/network/etc/cidr_global_registry.csv'

  xgress_file=$1
  csv_file=$xgress_file # required by csv_* functions

  : ${CIDR_registry:=~/network/etc/cidr_global_registry.csv}

  if [ ! -f $CIDR_registry ]; then
    >&2 echo "Error. CIDR registry file not found!"
    return 1
  fi

  if [ ! -f "$xgress_file" ]; then
    >&2 echo "Error. xgress file not found!"
    return 2
  fi

  type=this
  this_header=$(head -1 $CIDR_registry | sed "s/,/_$type,/g")_$type
  this_column=$(csv_column this)

  type=other
  other_header=$(head -1 $CIDR_registry | sed "s/,/_$type,/g")_$type
  other_column=$(csv_column other)

  echo $(csv_header),$this_header,$other_header
  for xgress_socket in $(cat $xgress_file | grep -v '^$' | grep -v $(head -1 $csv_file)); do
    >&2 echo -n "."
    this=$(echo $xgress_socket | cut -d, -f$this_column)
    get_cidr $this >/dev/null # to put value in host2cidr; w/o this host2cidr was not updated (fork problem?) 
    this_cidr=$(get_cidr $this) # to get already discovered value from host2cidr

    other=$(echo $xgress_socket | cut -d, -f$other_column)
    get_cidr $other >/dev/null # to put value in host2cidr; w/o this host2cidr was not updated (fork problem?)
    other_cidr=$(get_cidr $other) # to get already discovered value from host2cidr
    echo $xgress_socket,$this_cidr,$other_cidr
  done
  >&2 echo "."
}


#
# build global cidr registry combined out of main, oci, and host related registries
#
# combine OCI public registry and Alshaya registry to be available at ~/network/etc/cidr_global_registry.csv
# global file is sorted in such way that wider CIDRs are on bottom of the file
#
function bulid_CIDR_registry() {

  unset host2cidr # clear cache

  csv_file=~/network/etc/UNKNOWN_registry.csv 
  csv_header=$(csv_header)

  echo $csv_header > ~/network/tmp/cidr_global_registry.csv
  cat ~/network/etc/UNKNOWN_registry.csv | grep -v "$csv_header" >> ~/network/tmp/cidr_global_registry.csv

  if [ $TENANCY_REGISTRY == yes ]; then
    cat ~/network/etc/tenancy_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $OCI_INTERNAL_REGISTRY == yes ]; then
    cat ~/network/etc/oci_internal_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $OCI_PUBLIC_REGISTRY == yes ]; then
    cat $OBJECT_STORAGE_ranges_csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
    cat $OSN_ranges_csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
    cat $OCI_ranges_csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $CIDR_REGISTRY == yes ]; then
    cat ~/network/etc/cidr_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $HOST_REGISTRY == yes ]; then
    cat ~/network/etc/host_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $ENV_REGISTRY == yes ]; then
    test  -f $HOME/network/data/$env/$(date -I)/registered_ingress.csv && cat $HOME/network/data/$env/$(date -I)/registered_ingress.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
    test  -f $HOME/network/data/$env/$(date -I)/registered_egress.csv && cat $HOME/network/data/$env/$(date -I)/registered_egress.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  # sort all cidr and hosts 
  CIDR_registry=~/network/etc/cidr_global_registry.csv
  echo $csv_header > $CIDR_registry
  cat ~/network/tmp/cidr_global_registry.csv | grep -v $csv_header | sort -t . -k 1,1nr -k 2,2nr -k 3,3nr -k 4,4nr >> $CIDR_registry 
}

