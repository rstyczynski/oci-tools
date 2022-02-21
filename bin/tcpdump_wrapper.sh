#!/bin/bash

function tcpdump_start() {
        sudo mkdir -p ${pcap_dir}
        sudo chmod 777 ${pcap_dir}

        echo "Starting capture at $netif of traffic to ${pcap_filter}..."

        if [ $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then

            echo "Invoking command: tcpdump -i $netif -U -w ${pcap_dir}/${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' "
            sudo -- bash -c "umask o+r; nohup tcpdump -i $netif -U -w ${pcap_dir}/${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' > ${pcap_dir}/${tcp_file_pfx}.out 2> ${pcap_dir}/${tcp_file_pfx}.err" &
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
    : ${pcap_dir:=$HOME/x-ray/net/traffic/$(date -I)} 
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

