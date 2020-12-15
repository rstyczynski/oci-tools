

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

    if [ "$#" -ne 7 ]; then
        loginfo error "Error. oci_metric gets 7 mandatory parameters. Provided: $#"
    fi

    metric_timestamp=$1; shift
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

    : ${metric_namespace:=tmp_test}

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

           cat >>$oci_json_file <<EOF
                "dimensions": { 
                    "hostname": "$metric_host",
                    "$dimension_name": "$dimension_value"
                    },
EOF


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

rm -rf data.json

compartment_id=$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
telemetry_endpoint="https://telemetry-ingestion.$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.region').oraclecloud.com"


# oci_metric set_file data.json
# oci_metric start_array

# oci_metric $(utc::now) $(hostname) filesystem:/    diskspace  20 level expect_more
# oci_metric $(utc::now) $(hostname) filesystem:/u01 diskspace  75 level no_more

# cat data.json

# oci monitoring metric-data post --metric-data file://data.json \
# --endpoint $telemetry_endpoint

# https://docs.cloud.oracle.com/en-us/iaas/Content/Identity/Tasks/callingservicesfrominstances.htm
#--auth instance_principal
# gives error 404

# ---
# /mwlogs/x-ray/infra/infra-soaapp01/watch/obd/disk-space-mount1/state 

env_files=/mwlogs

declare -A envs
declare -A servers
envs_maybe=$(ls $env_files/x-ray)
for env_maybe in $envs_maybe; do
    servers_maybe=$(ls $env_files/x-ray/$env_maybe)
    for server_maybe in $servers_maybe; do
        if [ -d $env_files/x-ray/$env_maybe/$server_maybe/watch/obd ]; then
            servers[$server_maybe]=$env_maybe
        fi
    done
done

# set maximum number of records in oci telementry payload
batch_max=5

unset servers_batched
declare -A servers_batched

keep_sending=yes
batch_size=0
while [ $keep_sending == yes ]; do

    # initialize payload to be sent to oci metric
    rm -rf data.json
    oci_metric set_file data.json
    oci_metric start_array

    # go trough list of servers
    for server in ${!servers[@]}; do
        keep_sending=no

        # one readng per server; if not yet processed, do it now.
        echo $server, ${servers_batched[$server]}
        if [ -z ${servers_batched[$server]} ]; then
            

            # get data about the server
            timestamp=$(cat /mwlogs/x-ray/${servers[$server]}/$server/watch/obd/disk-space-mount1/state | grep timestamp | cut -f2 -d=)
            datetime=$(date -d @$timestamp +"%Y-%m-%dT%H:%M:%S.000Z")
            used=$(cat /mwlogs/x-ray/${servers[$server]}/$server/watch/obd/disk-space-mount1/state | grep capacity | cut -f2 -d=)  
            mounted_on=$(cat /mwlogs/x-ray/${servers[$server]}/$server/watch/obd/disk-space-mount1/state | grep mounted_on | cut -f2 -d=)  
            echo $datetime, ${servers[$server]}, $server, $mounted_on, $used

            # add server data to the payload
            oci_metric $datetime $server filesystem:$mounted_on diskspace $used level expect_more
            batch_size=$(( $batch_size + 1 ))
            
            # one readng per server; mark that the server was processed
            servers_batched[$server]=yes
            
            # send when number of records is equal to max allowed for one payload
            echo $batch_size of $batch_max 
            if [ $batch_size -eq $batch_max ]; then

                # add use this host just to close the payload
                oci_metric $(utc::now) $(hostname) filesystem:/ diskspace $(df --output=pcent / | tail -1 | tr -d ' %') level no_more

                # send
                oci monitoring metric-data post --metric-data file://data.json \
                --endpoint $telemetry_endpoint

                #cat data.json

                keep_sending=yes
                break
            fi
        fi
    done
done

# soem data may be in the payload here. use this host just to close the payload
oci_metric $(utc::now) $(hostname) filesystem:/ diskspace $(df --output=pcent / | tail -1 | tr -d ' %') level no_more

# send
oci monitoring metric-data post --metric-data file://data.json \
--endpoint $telemetry_endpoint

