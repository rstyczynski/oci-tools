#!/bin/bash

function tcpdump_start() {
        mkdir -p ${pcap_dir}
        chmod 777 ${pcap_dir}

        echo "Starting capture at $netif of traffic to ${pcap_filter}..."

        if [ $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then

            # write props file with additional info. IP adress for now
            echo "HOST_IP:$(hostname -i)" > ${pcap_dir}/${tcp_file_pfx}.props

            echo "Invoking command: tcpdump -i $netif -U -w ${pcap_dir}/${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' "
            umask o+rw
            sudo -- bash -c "umask o+rw; cd ${pcap_dir}; nohup tcpdump -Z $USER -i $netif -U -w ${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' > ${tcp_file_pfx}.out 2> ${tcp_file_pfx}.err" &
            sudo chmod o+rw ${pcap_dir}/${tcp_file_pfx}.out
            sudo chown $USER ${pcap_dir}/${tcp_file_pfx}.out
            
            sudo chmod o+rw ${pcap_dir}/${tcp_file_pfx}.err
            sudo chown $USER ${pcap_dir}/${tcp_file_pfx}.err

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
            echo -n "Stopping tdpdump at $netif of traffic to ${pcap_filter}..."
            sudo kill $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | tr -s ' ' | cut -d' ' -f2)
            echo "Done. Capture files in : ${pcap_dir}"
        fi
}

function tcpdump_wrapper() {
    pcap_filter=$1
    cmd=$2 
    pcap_dir=$3
    netif=$4

    : ${cmd:=status}
    : ${pcap_dir:=$HOME/x-ray/traffic/$(date -I)} 
    : ${netif:=$(ip a | grep -i mtu | grep -v lo: | head -1 | tr -d ' ' | cut -f2 -d:)}

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

function tcpdump_show_egress() {
    pcap_dir=$1
    src_ip=$2

    : ${pcap_dir:=$HOME/x-ray/traffic/$(date -I)} 

    pcap_filter='tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0'
    tcp_file_pfx=tcpdump_filter_$(echo ${pcap_filter} | tr -c 'a-zA-Z0-9' '_')

    : ${src_ip:=$(cat ${pcap_dir}/${tcp_file_pfx}.props | grep -P "^HOST_IP:" | cut -d: -f2)}
    if [ -z "$src_ip" ]; then
        echo "source IP not known. Specify as second parameter, after dirname with pcap files."
        return 1
    fi

    ports=$(tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null  |
    grep -P "^[\d:\.]+ IP $src_ip" |
    cut -d'>' -f2 |
    cut -d: -f1 |
    sort -u |
    cut -d'.' -f5 |
    sort -un)

    for port in $ports; do
        echo -n " tcp $port:"
        tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
        grep -P "^[\d:\.]+ IP $src_ip" |
        cut -d'>' -f2 |
        cut -d: -f1 |
        sort -u |
        grep -P "$port$"|
        cut -d'.' -f1-4 |
        tr '\n' ' '
        echo
    done
}

function tcpdump_show_ingress() {
    pcap_dir=$1
    dest_ip=$2

    : ${pcap_dir:=$HOME/x-ray/traffic/$(date -I)} 

    pcap_filter='tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0'
    tcp_file_pfx=tcpdump_filter_$(echo ${pcap_filter} | tr -c 'a-zA-Z0-9' '_')

    : ${dest_ip:=$(cat ${pcap_dir}/${tcp_file_pfx}.props | grep -P "^HOST_IP:" | cut -d: -f2)}
    if [ -z "$dest_ip" ]; then
        echo "source IP not known. Specify as second parameter, after dirname with pcap files."
        return 1
    fi

    ports=$(tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null  |
        perl -ne "m/^[\d:\.]+ IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > $dest_ip\.(\d+)/ && print \"\$3\n\"" |  
        sort -un)

    for port in $ports; do
        echo -n " tcp $port:"
        tcpdump_wrapper "$pcap_filter" dump $pcap_dir 2> /dev/null |
        perl -ne "m/^[\d:\.]+ IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > $dest_ip\.(\d+)/ && print \"\$1\n\"" |
        sort -u |
        tr '\n' ' '
        echo
    done
}

