#
# configure
#

cat >.dns_config <<EOF
oci_vcn_cidrs="10.106.0.0/16;10.196.0.0/16"

customer_domain_name=alshaya.com
customer_cidrs="10.0.0.0/8; 172.16.0.0/16;192.0.0.0/16; 192.168.0.0/16"
customer_dsn_ips="172.16.98.12; 172.16.100.19"
customer_test_hostnames="aresdevem.alshaya.com aresdevem.alshaya.com aresdevem.alshaya.com aresdevem.alshaya.com hrmsdevdb.alshaya.com hrmsdevdb.alshaya.com hrmsdevdb.alshaya.com indentdb.alshaya.com"

# uncomment to install inter vcn dns
#dns_forwards[10.106.6.250]=10.196.3.250:uat-dns-server.netuatdmz.mhauatvcn.oraclevcn.com
#dns_forwards[10.196.3.250]=10.106.6.250:sit-dns-server.netprojdmzad1.mhaprojectvcn.oraclevcn.com

# this_vcn_dns_ip will be set automatially to *.251 for first node, *.252 for seconds node deducting from node name (suffix *-1 | *-2)
# if suffix is not in the node name (uname -n) adress of *.250 will be selected.
this_vcn_dns_mask=255.255.255.0

EOF

#
# functions
#

function pre_dns_prepare_config() {

    mkdir -p ~/.dns
    cat .dns_config >~/.dns/dns.config
    rm -f .dns_config

    # follow ip convention: 251 for first node, 252 for second node
    # first node name is anything1, second is anything2
    this_vcn_dns_node_no=$(uname -n | rev | cut -d- -f1 | rev)
    case $this_vcn_dns_node_no in
    1)
        this_vcn_dns_ip=$(hostname -i | cut -d. -f1-3).251
        ;;
    2)
        this_vcn_dns_ip=$(hostname -i | cut -d. -f1-3).252
        ;;
    *)
        this_vcn_dns_ip=$(hostname -i | cut -d. -f1-3).250
        ;;
    esac
    echo $this_vcn_dns_ip >>~/.dns/dns.config
    echo $this_vcn_dns_ip
}

#
# prepare data
#
function pre_dns_prepare_data() {
    echo "This VCN IP:           $this_vcn_dns_ip"

    if [ ! -z "${dns_forwards[$this_vcn_dns_ip]}" ]; then

        dns_install_type=two_vcn

        other_vcn_forward_via=$(echo ${dns_forwards[$this_vcn_dns_ip]} | cut -d: -f1)
        other_vcn_test_hostname=$(echo ${dns_forwards[$this_vcn_dns_ip]} | cut -d: -f2)
        other_vcn_name=$(echo ${dns_forwards[$this_vcn_dns_ip]} | cut -d: -f2 | rev | cut -f1-3 -d. | rev)

        echo "Other VCN domain name: $other_vcn_name"
        echo "Other VCN DNS:         $other_vcn_forward_via"
        echo "Other VCN test FQDN:   $other_vcn_test_hostname"
    else
        dns_install_type=one_vcn
        echo "Single VNC DNS. Other region not defined."
    fi
}

#
# secondary ip
#
function ip_cfg_secondary_ip() {
    secondary_ip=$1
    secondary_netmask=$2
    secondary_dev_no=$3

    secondary_dev_name=$(ip a | grep "^$secondary_dev_no:" | tr -d ' ' | cut -f2 -d':')

    ip addr add $secondary_ip/$secondary_netmask dev $secondary_dev_name:0

    cat >/etc/sysconfig/network-scripts/ifcfg-$secondary_dev_name:0 <<EOF_ip_cfg
DEVICE="$secondary_dev_name:0"
BOOTPROTO=static
IPADDR=$secondary_ip
NETMASK=$secondary_netmask
ONBOOT=yes
EOF_ip_cfg
}

#
# sanity check
#
function pre_dns_sanity_check() {
    timeout 5 curl ifconfig.me
    echo
    uname -n
    hostname -s
    hostname -f
    hostname -A
    cat /etc/hosts | grep $(hostname -i)
}

#
# install bind
#
function pre_dns_install() {
    yum install -y bind
}

#
# firewall
#
dns_cfg_firewall() {
    firewall-cmd --zone=public --add-port=53/udp --permanent
    firewall-cmd --reload
}

#
# bind
#
function dns_cfg_bind() {

    cat >/etc/named.conf <<EOF_named_conf
options {
    directory "/var/named";
    listen-on port 53 {any;};
    allow-query    {
        localhost; 
        $oci_vcn_cidrs;
        $customer_cidrs; 
    };
    forward        only;
    forwarders     {
        169.254.169.254; 
    };
    recursion yes;
};

zone "$customer_domain_name" {
    type           forward;
    forward    only;
    forwarders { 
        $customer_dsn_ips; 
    };
};
EOF_named_conf

    if [ "$dns_install_type" == two_vcn ]; then

        cat >>/etc/named.conf <<EOF_named_conf_two_vcn
zone "$other_vcn_name" {
        type       forward;
        forward    only;
        forwarders { $other_vcn_forward_via; };
};
EOF_named_conf_two_vcn
    fi

}

function dns_service_update() {
    #
    # let bind restart after crash
    #
    sed -i 's/Restart=on-failure//g;s/\[Install\]/Restart=on-failure\n\n[Install]/g' /usr/lib/systemd/system/named.service

    #
    # update system
    #
    systemctl daemon-reload
    systemctl disable named
    systemctl enable named
    systemctl stop named >/dev/null 2>&1
    systemctl start named
    systemctl status named
}

function dns_test_restart() {
    #
    # test restart after crash
    #
    named_pid=$(systemctl status named | grep "Main PID" | tr -d '[ a-zA-Z:()]')
    kill -9 $named_pid
    systemctl status named
    sleep 2
    systemctl status named
}

#
# check
#
function dns_check_this_vcn_setup() {
    echo "Addresses listening on port 53"
    netstat -ln | grep ':53'

    err=no
    echo
    echo "Testng search name resolution."
    dig @$this_vcn_dns_ip $(hostname -s) +noall +answer +search | grep -v DiG | grep $(hostname -s) | tr -d '\n'
    if [ $? -eq 0 ]; then
        echo "> $(hostname -s) OK"
    else
        echo "> $(hostname -s) FAILED"
        err=yes
    fi

    echo
    echo "Testng VCN name resolution."
    for fqdn in $(hostname -f); do
        dig @$this_vcn_dns_ip $fqdn +noall +answer | grep -v DiG | grep $fqdn | tr -d '\n'
        if [ $? -eq 0 ]; then
            echo "> $fqdn OK"
        else
            echo "> $fqdn FAILED"
            err=yes
        fi
    done

    echo
    echo "Testng internet name resolution."
    for fqdn in oracle.com google.com; do
        dig @$this_vcn_dns_ip $fqdn +noall +answer | grep -v DiG | grep $fqdn | tr -d '\n'
        if [ $? -eq 0 ]; then
            echo "> $fqdn OK"
        else
            echo "> $fqdn FAILED"
            err=yes
        fi
    done

    case $dns_install_type in
    two_vcn)
        echo
        echo "Testng other VCN name resolution."
        for fqdn in $other_vcn_test_hostname; do
            dig @$this_vcn_dns_ip $fqdn +noall +answer | grep -v DiG | grep $fqdn | tr -d '\n'
            if [ $? -eq 0 ]; then
                echo "> $fqdn OK"
            else
                echo "> $fqdn FAILED"
                err=yes
            fi
        done
        ;;
    esac

    echo
    echo "Testng on premise name resolution."
    for fqdn in $customer_test_hostnames; do
        dig @$this_vcn_dns_ip $fqdn +noall +answer | grep -v DiG | grep $fqdn | tr -d '\n'
        if [ $? -eq 0 ]; then
            echo "> $fqdn OK"
        else
            echo "> $fqdn FAILED"
            err=yes
        fi
    done

    if [ $err != no ]; then
        echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
        echo '!!! Execution errors. Check output.'
        echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    fi
}

#
# block oci dhcp options, and set host to own dns
#
function oci_block_dhcp_dns_cfg() {
    sed -i 's/PRESERVE_HOSTINFO=[0-9]/PRESERVE_HOSTINFO=2/g' /etc/oci-hostname.conf

    # below is ok, but unnecessary. dhcp should do this.

    # sed -i "/search /d" /etc/resolv.conf

    # fqdn_pos=2
    # echo -n "search " >> /etc/resolv.conf
    # while [ $fqdn_pos -le $(hostname -f | tr -cd '.' | wc -c) ]; do
    #     echo -n " $(hostname -f | rev | cut -d. -f1-$fqdn_pos | rev)" >> /etc/resolv.conf
    #     fqdn_pos=$(( $fqdn_pos + 1 ))
    # done

    sed -i "s/^nameserver 169.254.169.254/#nameserver 169.254.169.254/g" /etc/resolv.conf
    sed -i "/nameserver $(hostname -i)/d" /etc/resolv.conf
    sed -i "/nameserver $this_vcn_dns_ip/d" /etc/resolv.conf

    echo "nameserver $this_vcn_dns_ip" >>/etc/resolv.conf
}

#
# save functions as a script
#
mkdir -p ~/bin

cat >~/bin/dns_setup.h <<EOF
#/bin/bash
declare -A dns_forwards
EOF
for fn_name in pre_dns_prepare_data ip_cfg_secondary_ip pre_dns_sanity_check pre_dns_install dns_cfg_firewall dns_cfg_bind dns_service_update dns_test_restart dns_check_this_vcn_setup oci_block_dhcp_dns_cfg; do

    echo "#" >>~/bin/dns_setup.h
    echo "# $fn_name" >>~/bin/dns_setup.h
    echo "#" >>~/bin/dns_setup.h

    declare -f $fn_name >>~/bin/dns_setup.h
done

#
# update .bash_profile
#
dns_init_header="# dns_setup init"
grep "$dns_init_header" ~/.bash_profile >/dev/null
if [ $? -ne 0 ]; then
    echo "$dns_init_header" >>~/.bash_profile
    echo "source ~/bin/dns_setup.h" >>~/.bash_profile
    echo "source ~/.dns/dns.config" >>~/.bash_profile
    echo "pre_dns_prepare_data" >>~/.bash_profile
    echo "echo" >>~/.bash_profile
    echo "echo" >>~/.bash_profile
    echo "echo" >>~/.bash_profile
    echo "dns_check_this_vcn_setup" >>~/.bash_profile
    echo "echo" >>~/.bash_profile
    echo "echo" >>~/.bash_profile
    echo "echo" >>~/.bash_profile
    echo "echo Use: dns_check_this_vcn_setup to check known DNS hosts." >>~/.bash_profile
fi

#
# install & cfg. bind
#

sudo bash <<EOF
declare -A dns_forwards
pre_dns_prepare_config

source /home/opc/.dns/dns.config
source /home/opc/bin/dns_setup.h

pre_dns_prepare_data

ip_cfg_secondary_ip $this_vcn_dns_ip $this_vcn_dns_mask 2

pre_dns_sanity_check
pre_dns_install
dns_cfg_firewall
dns_cfg_bind
dns_service_update
dns_test_restart
dns_check_this_vcn_setup

oci_block_dhcp_dns_cfg

EOF
# Based on: https://linuxconfig.org/how-to-setup-a-named-dns-service-on-redhat-7-linux-server
