#!/bin/bash

function tcpdump_host() {
    pcap_filter=$1
    cmd=$2
    hostname=$3  
    dump_root=$4
    netif=$5

    : ${cmd:="status"}
    : ${hostname:=$(hostname)}
    : ${dump_root:="/mwlogs"} 
    : ${netif:="$(ip a | grep -i mtu | grep -v lo: | head -1 | tr -d ' ' | cut -f2 -d:)"}

    dump_dir=$dump_root/analysis/network

    tcp_file_pfx="tcpdump_host_${hostname}_filter_$(echo ${pcap_filter} | tr -c 'a-zA-Z0-9' '_')"

    dateISO=$(date -I)

    case $cmd in
    start)

        sudo mkdir -p $dump_root/analysis
        sudo chmod 777 $dump_root/analysis
        sudo mkdir -p $dump_root/analysis/network
        sudo chmod 777 $dump_root/analysis/network
        sudo mkdir -p ${dump_dir}/${hostname}
        sudo chmod 777 ${dump_dir}/${hostname}
        sudo mkdir -p ${dump_dir}/${hostname}/${dateISO}
        sudo chmod 777 ${dump_dir}/${hostname}/${dateISO}

        echo "Starting capture at $netif of traffic to ${pcap_filter}..."

        if [ $(ps aux | grep tcpdump | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then

            echo "Invoking command: tcpdump -i $netif -U -w ${dump_dir}/${hostname}/${dateISO}/${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' "
            sudo -- bash -c "umask o+r; nohup tcpdump -i $netif -U -w ${dump_dir}/${hostname}/${dateISO}/${tcp_file_pfx}_%Y%m%dT%H%M%S.pcap -G 3600 '${pcap_filter}' > ${dump_dir}/${hostname}/${dateISO}/${tcp_file_pfx}.out" &
            echo "Started. Use dump|tail to check traffic. Use stop to finish capture."
        else
            echo "Already running"
            ps aux | grep tcpdump | grep ${dump_dir}/${hostname} | grep ${tcp_file_pfx} 
        fi
        ;;
    stop)
        if [ $(ps aux | grep tcpdump | grep ${dump_dir}/${hostname} | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then
            echo "Capture not running."
        else
            echo -n "Stopping tdpdump at $netif of traffic to ${pcap_filter}..."
            sudo kill $(ps aux | grep tcpdump | grep ${dump_dir}/${hostname} | grep ${tcp_file_pfx} | grep -v grep | tr -s ' ' | cut -d' ' -f2)
            tcp_file=$(ls -t ${dump_dir}/${hostname}/*/${tcp_file_pfx}_* | head -1)
            echo "Done. Capture file: $tcp_file"
        fi
        ;;
    status)
        if [ $(ps aux | grep tcpdump | grep ${dump_dir}/${hostname} | grep ${tcp_file_pfx} | grep -v grep | wc -l) -eq 0 ]; then
            echo "Capture not running."
        else
            echo "Capture running"
            ps aux | grep tcpdump | grep ${dump_dir}/${hostname} | grep ${tcp_file_pfx} | grep -v grep
        fi
        ;;
    dump)
	echo "Dump of files from ${dump_dir}/${hostname}/${dateISO}:"	
    	for tcp_file in $(ls -t ${dump_dir}/${hostname}/${dateISO}/${tcp_file_pfx}_*; do
           tcpdump -A -nn -r  $tcp_file
	done
        ;;
    tail)
        tcp_file=$(ls -t ${dump_dir}/${hostname}/${dateISO}/${tcp_file_pfx}_* | head -1)
        echo "Tail of $tcp_file:"
        tcpdump -A -nn -r $tcp_file | tail 
        ;;
    '')
        echo "Usage: tcpdump_ftp ifname ftp_ip start|stop|dump|tail"
        ;;
    esac
}

if [ $0 != '-bash' ]; then
    tcpdump_host $@
fi
