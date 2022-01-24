#!/bin/bash

function port_forward_set() {
    local fwd_ifname=$1
    local fwd_host=$(echo $2 | cut -f1 -d:)
    local fwd_port=$(echo $2 | cut -f2 -d:)
    local dst_host=$(echo $3 | cut -f1 -d:)
    local dst_port=$(echo $3 | cut -f2 -d:)

    # save state before change
    iptables-save > ~/iptables_$(date +%Y-%m-%d_%T).save

    iptables -I FORWARD -j ACCEPT -d $dst_host

    iptables -t nat -A PREROUTING -p tcp -d $fwd_host --dport $fwd_port -j DNAT --to-destination $dst_host:$dst_port
    iptables -t nat -A POSTROUTING -s $dst_host -p tcp --dport $fwd_port -j SNAT --to-source $fwd_host

    # save to survive reboot
    /sbin/service iptables save
}

function port_forward_del() {
    local fwd_ifname=$1
    local fwd_host=$(echo $2 | cut -f1 -d:)
    local fwd_port=$(echo $2 | cut -f2 -d:)
    local dst_host=$(echo $3 | cut -f1 -d:)
    local dst_port=$(echo $3 | cut -f2 -d:)

    # save state before change
    iptables-save > ~/iptables_$(date +%Y-%m-%d_%T).save

    iptables -D FORWARD -j ACCEPT -d $dst_host

    iptables -t nat -D PREROUTING -p tcp -d $fwd_host --dport $fwd_port -j DNAT --to-destination $dst_host:$dst_port
    iptables -t nat -D POSTROUTING -s $dst_host -p tcp --dport $fwd_port -j SNAT --to-source $fwd_host
    
    # save to survive reboot
    /sbin/service iptables save
}

function port_forward_prepare() {
    local fwd_ifname=$1


    sysctl -w net.ipv4.ip_forward=1
    # save to survive reboot
    echo "net.ipv4.ip_forward=1" >/etc/sysctl.d/port_forward.conf

    # save state before change
    iptables-save > ~/iptables_$(date +%Y-%m-%d_%T).save

    # delete default OCI forward drop 
    iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited

    # add masquarade on outgoing packets
    iptables -t nat -A POSTROUTING -o $fwd_ifname -j MASQUERADE

    # save to survive reboot
    /sbin/service iptables save
}

function port_forward_remove() {
    sysctl -w net.ipv4.ip_forward=0
    rm -f /etc/sysctl.d/port_forward.conf

    # save state before change
    iptables-save > ~/iptables_$(date +%Y-%m-%d_%T).save
    
    # delete default OCI forward drop 
    iptables -I FORWARD -j REJECT --reject-with icmp-host-prohibited

    # add masquarade on outgoing packets
    iptables -t nat -D POSTROUTING -o $fwd_ifname -j MASQUERADE

    # save to survive reboot
    /sbin/service iptables save
}


function port_forward_monitor() {
    iptables -nvL
    iptables -t nat -L -n -v
}


### only once

# port_forward_prepare

### activate port forward 

# port_forward_set eth0 10.196.3.41:80 172.16.98.153:21

# look into stats

### port_forward_monitor

# delete port forward

### port_forward_del eth0 10.196.3.41:80 172.16.98.153:21

# deactivate

### port_forward_remove
