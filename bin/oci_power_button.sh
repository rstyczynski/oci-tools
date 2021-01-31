#!/bin/bash

#
# Process env - functions
#

# get all ip for env, product, component
function get_hosts_ip() {
    local inventory=$1
    local env=$2
    local product=$3
    local component=$4

    cat $inventory  | sed -n "/\[$env\]/,/\[/p" | 
    grep -v '^\[' | egrep -v '^#|^$' | grep -v 'host_type=jump' |
    grep "host_product=$product" | 
    grep "host_component=$component" |
    cut -f1 -d' ' 
}

function get_hosts_info() {
    local inventory=$1
    local env=$2
    local product=$3
    local component=$4

    cat $inventory | sed -n "/\[$env\]/,/\[/p" | 
    grep -v '^\[' | egrep -v '^#|^$' | grep -v 'host_type=jump' |
    grep "host_product=$product" | 
    grep "host_component=$component" 
}

function compute_power_button() {
    local private_ip=$1
    local action=$2
   
    region=$(get_compute_info $private_ip region)
    instance_id=$(get_compute_info $private_ip instance_id)

    export OCI_CLI_PROFILE=$region

    instance_state=$(oci compute instance get --instance-id $instance_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')
    case $action in
        softstop)
            case $instance_state in
                RUNNING)
                    oci compute instance action --action softstop --instance-id $instance_id >/dev/null
                    echo "Instance stop initiated."
                    ;;
                STOPPING)
                    echo "Instance already stopping."
                    ;;
                STOPPED)
                    echo "Instance already stopped."
                    ;;
                STARTING)
                    echo "Instance starting. Can't stop now."
                    ;;
            esac
        ;;
        start)
            case $instance_state in
                RUNNING)
                    echo "Instance already started."
                    ;;
                STOPPING)
                    echo "Instance stopping. Can't start now."
                    ;;
                STOPPED)
                    oci compute instance action --action start --instance-id $instance_id >/dev/null
                    echo "Instance start initiated."
                    ;;
                STARTING)
                    echo "Instance already starting."
                    ;;
            esac
        ;;
        *)
            echo "Action unknown: $action"
            ;;
    esac
}


function db_power_button() {
    local private_ip=$1
    local action=$2
   
    region=$(get_db_info $private_ip region)
    db_node_id=$(get_db_info $private_ip db_node_id)

    export OCI_CLI_PROFILE=$region

    db_node_state=$(oci db node get --db-node-id $db_node_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')

    case $action in
        stop)
            case $db_node_state in
                AVAILABLE)
                    oci db node stop --db-node-id $db_node_id  >/dev/null
                    echo "Database node stop initiated."
                    ;;
                STOPPING)
                    echo "Database node already stopping."
                    ;;
                STARTING)
                    echo "Database node starting. Can't stop now."
                    ;;
                STOPPED)
                    echo "Database node already stopped."
                    ;;
            esac
        ;;
        start)
            case $db_node_state in
                AVAILABLE)
                    echo "Database node already started."
                    ;;
                STARTING)
                    echo "Database node already starting."
                    ;;
                STOPPING)
                    echo "Database node stopping. Can't start now."
                    ;;
                STOPPED)
                    oci db node start --db-node-id $db_node_id  >/dev/null
                    echo "Database node start initiated."
                    ;;
            esac
        ;;
        *)
            echo "Action unknown: $action"
            ;;
    esac
}

#
# Stop env
#
function shutdown_environment() {
    local inventory=$1
    local env=$2

    products=$(get_hosts_info $inventory $env | tr ' ' '\n' | grep host_product | cut -f2 -d= | sort -u)

    for product in $products; do
        echo "Stopping $env/$product...."
        echo '---'
        for private_ip in $(get_hosts_ip $inventory $env $product ohs); do
            echo "Processing OHS at $private_ip"
            compute_power_button $private_ip softstop
        done

        for private_ip in $(get_hosts_ip $inventory $env $product wls); do
            echo "Processing WLS at $private_ip"
            compute_power_button $private_ip softstop
        done

        # wait for status STOPPED
        for private_ip in $(get_hosts_ip $inventory $env $product wls); do
            echo -n "Waiting for compute instance node at $private_ip to be stopped..."

            region=$(get_compute_info $private_ip region)
            export OCI_CLI_PROFILE=$region
            instance_id=$(get_compute_info $private_ip instance_id)
            instance_state=$(oci compute instance get --instance-id $instance_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')
            
            wait_time=0
            max_wait_time=300
            wait_secs=5
            while [ $instance_state != STOPPED ]; do
                sleep $wait_secs
                echo -n .
                instance_state=$(oci compute instance get --instance-id $instance_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')

                wait_time=$(( $wait_time + $wait_secs ))
                if [ $wait_time -gt $max_wait_time ]; then
                    break
                fi
            done
            if [ $wait_time -gt $max_wait_time ]; then
                echo Timeout
            else
                echo OK
            fi
        done

        for private_ip in $(get_hosts_ip $inventory $env $product db); do
            echo "Processing DB at $private_ip"
            db_power_button $private_ip stop
        done
    done
}

#
# Start env
#
function startup_environment() {
    local inventory=$1
    local env=$2

    products=$(get_hosts_info $inventory $env | tr ' ' '\n' | grep host_product | cut -f2 -d= | sort -u)

    for product in $products; do
        echo "Starting $env/$product...."
        echo '---'

        for private_ip in $(get_hosts_ip $inventory $env $product db); do
            echo "Processing DB at $private_ip"
            db_node_id=$(get_db_info $private_ip db_node_id)
            db_power_button $private_ip start
        done

        # wait for status AVAILABLE
        for private_ip in $(get_hosts_ip $inventory $env $product db); do
            echo -n "Waiting for db node at $private_ip to be available..."

            db_node_id=$(get_db_info $private_ip db_node_id)
            db_node_state=$(oci db node get --db-node-id $db_node_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')

            wait_time=0
            max_wait_time=300
            wait_secs=5
            while [ $db_node_state != AVAILABLE ]; do
                sleep $wait_secs
                echo -n .
                db_node_state=$(oci db node get --db-node-id $db_node_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')

                wait_time=$(( $wait_time + $wait_secs ))
                if [ $wait_time -gt $max_wait_time ]; then
                    break
                fi
            done
            if [ $wait_time -gt $max_wait_time ]; then
                echo Timeout
            else
                echo OK
            fi
        done

        for private_ip in $(get_hosts_ip $inventory $env $product wls); do
            echo "Processing WLS at $private_ip"
            compute_power_button $private_ip start
        done

        # wait for status STARTED
        for private_ip in $(get_hosts_ip $inventory $env $product wls); do
            echo -n "Waiting for compute instance node at $private_ip to be available..."

            region=$(get_compute_info $private_ip region)
            export OCI_CLI_PROFILE=$region
            instance_id=$(get_compute_info $private_ip instance_id)
            instance_state=$(oci compute instance get --instance-id $instance_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')
            
            wait_time=0
            max_wait_time=300
            wait_secs=5
            while [ $instance_state != RUNNING ]; do
                sleep $wait_secs
                echo -n .
                instance_state=$(oci compute instance get --instance-id $instance_id | jq '.' | grep "lifecycle-state" | cut -f2 -d: | tr -d '," ')

                wait_time=$(( $wait_time + $wait_secs ))
                if [ $wait_time -gt $max_wait_time ]; then
                    break
                fi
            done
            if [ $wait_time -gt $max_wait_time ]; then
                echo Timeout
            else
                echo OK
            fi
        done

        for private_ip in $(get_hosts_ip $inventory $env $product ohs); do
            echo "Processing OHS at $private_ip"
            compute_power_button $private_ip start
        done
    done
}

#
# run
#

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
source $SCRIPTPATH/oci_discovery.sh

inventory=$1
env=$2
action=$3

case $action in
    start)
        startup_environment $inventory $env
        ;;
    stop)
        shutdown_environment $inventory $env
        ;;
    *)
        echo "Usage: oci_power_button.sh inventory env action"
        ;;
esac
