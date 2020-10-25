#!/bin/bash

function cfg_kernel_tcp() {

    project=$1
    : ${project:=custom}

    #
    # set values
    #

    kB=1024
    MB=$((1024 * 1024))

    # read buffers - keep it big
    read_min=$((512 * $kB))   #512kB
    read_default=$((2 * $MB)) #2MB
    read_max=$((6 * $MB))     #6MB

    # write buffers - keep it big
    write_min=$((512 * $kB))
    write_default=$((2 * $MB))
    write_max=$((6 * $MB))

    cat <<EOF
Kernel will be tuned with following computed settings:
1. tcp_rmem=$read_min $read_default $read_max
2. tcp_wmem=$write_min $write_default $write_max
EOF

    #
    # persist configuration
    #

    cat >/etc/sysctl.d/$project\_tcp_tune.conf <<EOF

# read buffers - keep it big
net.ipv4.tcp_rmem=$read_min $read_default $read_max
net.core.rmem_default=$read_default
net.core.rmem_max=$read_max

# write buffers - keep it big
net.ipv4.tcp_wmem=$write_min $write_default $write_max
net.core.wmem_default=$write_default
net.core.wmem_max=$write_max

# slow start
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_slow_start_after_idle = 0

# keepalive
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# other
net.core.optmem_max = 65536
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
EOF

    # References:
    # https://wiki.archlinux.org/index.php/sysctl
}

function cfg_kernel_mem() {

    project=$1
    : ${project:=custom}

    #
    # prepare variables
    #
    kB=1024
    MB=$(($kB * 1024))
    GB=$(($MB * 1024))

    #
    # check available memory
    #
    memorytotal_B=$(free -b | grep Mem: | tr -s ' ' | cut -f2 -d" ")
    memorytotal_kB=$((memorytotal_B / $kB))
    memorytotal_MB=$((memorytotal_B / $MB))
    memorytotal_GB=$((memorytotal_B / $GB))

    echo "Memory total: $memorytotal_GB GB"

    #
    # request to have 3% o RAM always available
    #
    set_min_free_kbytes=yes
    mem_min_free_kbytes_requested_kB=$(($memorytotal_B * 3 / 100 / $kB))
    mem_min_free_kbytes_current_kB=$(cat /proc/sys/vm/min_free_kbytes)
    if [ $mem_min_free_kbytes_current_kB -gt $mem_min_free_kbytes_requested_kB ]; then
        mem_min_free_kbytes_requested_kB=$mem_min_free_kbytes_current_kB
    fi

    echo "Mem min free requested $mem_min_free_kbytes_requested_kB kB with current $mem_min_free_kbytes_current_kB kB"

    #
    # Cache ratio
    #
    if [ $memorytotal_GB -gt 30 ]; then
        vm_dirty_ratio=20
        vm_dirty_background_ratio=10
    fi
    if [ $memorytotal_GB -gt 50 ]; then
        vm_dirty_ratio=10
        vm_dirty_background_ratio=5
    fi
    if [ $memorytotal_GB -gt 100 ]; then
        vm_dirty_ratio=5
        vm_dirty_background_ratio=3
    fi
    echo "Disk cache: $(($memorytotal_GB * $vm_dirty_ratio / 100))GB $vm_dirty_ratio $vm_dirty_background_ratio"

    #
    # Minimize swapiness
    #
    vm_swappiness=1

    #
    # Write cfg file
    #
    cat >/etc/sysctl.d/$project\_mem_tune.conf <<EOF
# keep minimal amount of available ram
vm.min_free_kbytes=$mem_min_free_kbytes_requested_kB

# disk cache size
vm.dirty_ratio=$vm_dirty_ratio
vm.dirty_background_ratio=$vm_dirty_background_ratio

# minimise swap activity
vm.swappiness=$vm_swappiness
EOF

    # drop all cache to let cache grow as requested
    echo 3 >/proc/sys/vm/drop_caches

    # References:
    # https://discuss.aerospike.com/t/how-to-tune-the-linux-kernel-for-memory-performance/4195
    # https://www.suse.com/support/kb/doc/?id=000017857
    # vide: "4. Linux kernel tunings, version 1"
    # https://docs.oracle.com/database/nosql-12.1.3.5/AdminGuide/linuxcachepagetuning.html
    #https://www.vertica.com/kb/Tuning-Linux-Dirty-Data-Parameters-for-Vertica/Content/BestPractices/Tuning-Linux-Dirty-Data-Parameters-for-Vertica.htm
    # https://lonesysadmin.net/2013/12/22/better-linux-disk-caching-performance-vm-dirty_ratio/

}

#
# generate cfg
#
cfg_kernel_tcp
cfg_kernel_mem

#
# apply configuration
#
sysctl --system

