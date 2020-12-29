#!/bin/bash

function loginfo() {
    echo $@
}

# date
function utc::now() {
    #date +'%d%m%YT%H%M'
    date -u +"%Y-%m-%dT%H:%M:%S.000Z"
}

function oci_metric() {

    if [ "$1" == "set_file" ]; then
        oci_json_file=$2
        echo -n >$oci_json_file
        return
    fi

    if [ "$1" == "start_array" ]; then
        oci_json_array_started=YES
        echo '[' >>$oci_json_file
        return
    fi

    if [ "$#" -ne 9 ]; then
        loginfo error "Error. oci_metric gets 9 mandatory parameters. Provided: $#"
    fi

    metric_timestamp=$1; shift
    metric_env=$1; shift
    metric_comp=$1; shift
    metric_host=$1; shift
    metric_dimension=$1; shift
    metric_name=$1; shift
    metric_value=$1; shift
    metric_unit=$1; shift
    metric_more=$1; shift

    if [ -z $oci_json_file ]; then
        loginfo error "Error. oci_json_file not set. Use oci_metric set_file file first."
        return
    fi

    if [ -z $oci_json_array_started ]; then
        loginfo error "Error. oci_json_array_started not set. Use oci_metric start_array first."
        return
    fi

    dimension_name=$(echo $metric_dimension | cut -f1 -d:)
    dimension_value=$(echo $metric_dimension | cut -f2 -d:)

    if [ -z $dimension_name ] || [ -z $dimension_value ]; then
        loginfo error "Error. Provide metric_dimension in format name:value."
        return
    fi

    cat >>$oci_json_file <<EOF
        {
                "namespace": "$metric_namespace",
                "compartmentId": "$compartment_id",
                "name": "$metric_name",
EOF

if [ ! -z "$dimension_name" ]; then
    cat >>$oci_json_file <<EOF
                "dimensions": { 
                    "environment": "$metric_env",
                    "component": "$metric_comp",
                    "hostname": "$metric_host",
                    "$dimension_name": "$dimension_value"
                    },
EOF
else
    cat >>$oci_json_file <<EOF
                "dimensions": { 
                    "environment": "$metric_env",
                    "component": "$metric_comp",
                    "hostname": "$metric_host"
                    },
EOF
fi


    cat >>$oci_json_file <<EOF
                "metadata": { "unit": "$metric_unit" },
                "datapoints": [
                    {
                        "timestamp": "$metric_timestamp",
                        "value": $metric_value
                    }
                ]
            }
EOF

    if [ "$metric_more" == "expect_more" ]; then
        echo ', ' >>$oci_json_file
    else
        if [ "$oci_json_array_started" == "YES" ]; then
            echo ']' >>$oci_json_file
            unset oci_json_array_started
        fi
    fi
}

function forward_data_to_OCI() {
    # some data may be in the payload here. use this host just to close the payload
    oci_metric $(utc::now) $env $component $(hostname) filesystem:/ diskspace $(df --output=pcent / | tail -1 | tr -d ' %') level no_more

    # send
    oci monitoring metric-data post --metric-data file://$tmp/data.json \
    --endpoint $telemetry_endpoint > $tmp/response.json
    if [ $? -eq 0 ];then
        logger -t $script_name -s "Data sent. Data: $(cat $tmp/response.json)"
    else
        logger -t $script_name -s "Error sending data. Data: $(cat $tmp/response.json)"
    fi    
}

function send_data_final() {
    if [ $batch_size -gt 0 ]; then
        forward_data_to_OCI
    fi
}

function send_data() {
    batch_size=$(( $batch_size + 1 ))
    # send when number of records is equal to max allowed for one payload
    [ $SCRIPT_DEBUG -eq 1 ] && echo $batch_size of $batch_max 
    if [ $batch_size -eq $batch_max ]; then
        # close current batch and send data
        forward_data_to_OCI

        # initialize next batch payload to be sent to oci metric
        batch_size=0
        rm -rf $tmp/data.json
        oci_metric set_file $tmp/data.json
        oci_metric start_array
    fi
}

# get data
function extract_data_form_path_os(){
    # get data about the server from PATH
    env=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w\d-_\.]+)\/os\/obd\/([\w\d-_\.]+)\/state/$1/')
    component=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w\d-_\.]+)\/os\/obd\/([\w\d-_\.]+)\/state/$2/')
    hostname=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w\d-_\.]+)\/os\/obd\/([\w\d-_\.]+)\/state/$3/')
    probe=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w\d-_\.]+)\/os\/obd\/([\w\d-_\.]+)\/state/$4/')    
}

function extract_timestamp(){
    timestamp=$(cat $state| grep timestamp | cut -f2 -d=)
    datetime=$(date -d @$timestamp +"%Y-%m-%dT%H:%M:%S.000Z")    
}

#
#
#

function quit() {
    rm -rf ~/tmp/$$
}
trap quit SIGINT EXIT

#
# Logic start
#

script_pathname=$0
script_dir=$(dirname $script_pathname)
script_name=$(basename $script_pathname)

: ${SCRIPT_DEBUG:=0}

tmp=~/tmp/$$
mkdir -p $tmp

compartment_id=$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
telemetry_endpoint="https://telemetry-ingestion.$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.region').oraclecloud.com"

logger -t $script_name -s "Started to report data to $telemetry_endpoint"

# to stop per from complains about locale
export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

source $script_dir/config.sh
env_files=$(getcfg x-ray env_files)
if [ -z "$env_files" ]; then
    echo "Error. env_files must be set. Use "setcfg x-ray env_files VALUE" to store right value for x-ray file repository"
    exit 1
fi

# set maximum number of records in oci telementry payload
batch_max=45

# initialize first batch payload to be sent to oci metric
batch_size=0
rm -rf $tmp/data.json
oci_metric set_file $tmp/data.json
oci_metric start_array

#
# metric namespace
#
metric_namespace=x-ray_os
metric_namespace=tmp_os

#
# disk space
#
states=$(ls $env_files/x-ray/*/*/watch/hosts/*/os/obd/disk-space-mount1/state)
for state in $states; do
    extract_data_form_path_os
    # get details from state file
    extract_timestamp
    [ $SCRIPT_DEBUG -eq 1 ] && echo  -n "$datetime, $env, $component, $hostname, $probe"

    ### CUSTOM OS code - START
    used=$(cat $state | grep capacity | cut -f2 -d=)  
    mounted_on=$(cat $state | grep mounted_on | cut -f2 -d=) 
    [ $SCRIPT_DEBUG -eq 1 ] && echo ", $mounted_on, $used"
    ### CUSTOM OS code - STOP

    # add server data to the payload
    oci_metric $datetime $env $component $hostname filesystem:$mounted_on diskspace $used level expect_more

    send_data
done

#
#  CPU utlization
#
states=$(ls $env_files/x-ray/*/*/watch/hosts/*/os/obd/system-vmstat/state)
for state in $states; do
    extract_data_form_path_os
    # get details from state file
    extract_timestamp
    [ $SCRIPT_DEBUG -eq 1 ] && echo  -n "$datetime, $env, $component, $hostname, $probe"

    ### CUSTOM OS code - START
    cpu_idle=$(cat $state | grep CPUidle | cut -f2 -d=)
    cpu_used=$(( 100 - $cpu_idle ))
    [ $SCRIPT_DEBUG -eq 1 ] && echo ", $cpu_used"
    ### CUSTOM OS code - STOP

    # add server data to the payload
    oci_metric $datetime $env $component $hostname : cpu $cpu_used level expect_more

    send_data
done

# close final batch and send data
send_data_final

quit
