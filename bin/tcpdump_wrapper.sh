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

    mkdir -p ~/network/tmp/$$

    >&2 echo "Processing data from $src_ip stored at $pcap_dir"

    tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null  |
    grep -P "^[\d:\.]+ IP $src_ip" |
    cut -d'>' -f2 |
    cut -d: -f1 |
    sort -u |
    cut -d'.' -f5 |
    sort -un >  ~/network/tmp/$$/egress.ports

    random_ports_cnt=$(cat ~/network/tmp/$$/egress.ports | awk "\$1 > $tcpdump_show_egress_maxport { print }" | wc -l)
    if [ $random_ports_cnt -gt 0 ];then
        >&2 echo 
        >&2 echo "Warning. High number of random destination ports detected. Possibly FTP communication."
        >&2 echo "         Report will be limited to low ports only. Set threshold using tcpdump_show_egress_maxport variable, having default value - 15000"
        >&2 echo "         Number of discovered ports: $random_ports_cnt, first 100 ports: $(cat ~/network/tmp/$$/egress.ports | sort -nu | head -100 | tr '\n' ' ')"
        >&2 echo "         Current value of tcpdump_show_egress_maxport: $tcpdump_show_egress_maxport"
    fi

    ports=$(cat ~/network/tmp/$$/egress.ports | awk "\$1 < $tcpdump_show_egress_maxport { print }")
    rm ~/network/tmp/$$/egress.ports

    
    tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
        grep -P "^[\d:\.]+ IP $src_ip" |
        cut -d'>' -f2 |
        cut -d: -f1 |
        sort -u > ~/network/tmp/$$/egress.dump

    if [ "$tcpdump_show_egress_format" == CSV ]; then
        for port in $ports; do
            hosts=$(grep -P "$port$" ~/network/tmp/$$/egress.dump |
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
            cat ~/network/tmp/$$/egress.dump |
            grep -P "$port$"|
            cut -d'.' -f1-4 |
            sort -u |
            tr '\n' ' '
            echo
        done
    fi

    rm ~/network/tmp/$$/egress.dump
    rmdir ~/network/tmp/$$
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

    mkdir -p ~/network/tmp/$$

    >&2 echo "Processing data directed to $src_ip stored at $pcap_dir"

    tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null  |
        perl -ne "m/^[\d:\.]+ IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > $dest_ip\.(\d+)/ && print \"\$3\n\"" |  
        sort -un > ~/network/tmp/$$/ingress.ports

    random_ports_cnt=$(cat ~/network/tmp/$$/ingress.ports | awk "\$1 > $tcpdump_show_ingress_maxport { print }" | wc -l)
    if [ $random_ports_cnt -gt 0 ];then
        >&2 echo 
        >&2 echo "Warning. High number of random destination ports detected. Possibly FTP communication."
        >&2 echo "         Report will be limited to low ports only. Set threshold using tcpdump_show_ingress_maxport variable, having default value - 15000"
        >&2 echo "         Number of discovered ports: $random_ports_cnt, first 100 ports: $(cat ~/network/tmp/$$/ingress.ports | sort -nu | head -100 | tr '\n' ' ')"
        >&2 echo "         Current value of tcpdump_show_egress_maxport: $tcpdump_show_ingress_maxport"
    fi

    ports=$(cat ~/network/tmp/$$/ingress.ports | awk "\$1 < $tcpdump_show_ingress_maxport { print }")
    rm ~/network/tmp/$$/ingress.ports

    
    tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
        perl -ne "m/^[\d:\.]+ IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > $dest_ip\.(\d+)/ && print \"\$1\n\"" |
        sort -u > ~/network/tmp/$$/ingress.dump

    if [ "$tcpdump_show_ingress_format" == CSV ]; then

        for port in $ports; do
            hosts=$(cat ~/network/tmp/$$/ingress.dump)
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
            cat ~/network/tmp/$$/ingress.dump |
            tr '\n' ' '
            echo
        done
    fi

    rm ~/network/tmp/$$/ingress.dump
}
