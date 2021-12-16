#!/bin/bash

# Reference: https://docs.oracle.com/en-us/iaas/Content/Monitoring/Tasks/publishingcustommetrics.htm

#
# helpers
#

function clean() {
    rm -rf ~/tmp/$$\_OCI_Telementry_$script_name
}
trap clean SIGINT EXIT

#
# main functions
#

function oci_metric() {

    #
    # Script context discovery
    #

    script_pathname=$0
    if [ -f $script_pathname ]; then
      script_dir=$(dirname $script_pathname)
      script_name=$(basename $script_pathname)
      script_mode=SCRIPT
    else
      script_dir=$PWD
      script_name=OCI_telemetry
      script_mode=CLI
    fi

    : ${SCRIPT_DEBUG:=0}

    if [ "$1" == "initialize" ]; then
        if [ -z "$telemetry_endpoint" ]; then
          compartment_id=$(curl  --connect-timeout 1 -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
          if [ ! -z "$compartment_id" ]; then
            telemetry_endpoint="https://telemetry-ingestion.$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.region').oraclecloud.com"
            if [ -z "$telemetry_endpoint" ]; then
              logger -t $script_name -s -p local3.err "Error. Telemetry endpoint not set. Cannot continue w/o telemetry_endpoint set."
              return 1
            fi
          else
            logger -t $script_name -s -p local3.err "Error. compartment_id not set. Cannot continue w/o compartment_id set."
            return 1
          fi
        fi
        
        tmp=~/tmp/$$\_OCI_Telementry_$script_name; mkdir -p $tmp
        
        oci_json_file=$tmp/data.json

        oci_json_array_started=YES
        echo '[' > $oci_json_file

        batch_max=45
        batch_size=0

        declare -A dimensions
        
        logger -t $script_name -s -p local3.notice "Started to report data to $telemetry_endpoint"

        oci_metric_status=INITIALIZED
        return
    fi

    if [ -z "$telemetry_endpoint" ]; then
      logger -t $script_name -s -p local3.err "Error. Telemetry endpoint not set. Cannot continue. Cannot continue w/o telemetry_endpoint set."
      return 1
    fi

    if [ -z "$compartment_id" ]; then
      logger -t $script_name -s -p local3.err "Error. compartment_id not set. Cannot continue w/o compartment_id set."
      return 1
    fi

    if [ "$1" == "clean" ]; then
        rm -rf ~/tmp/$$\_OCI_Telementry_$script_name
        unset oci_json_array_started
        return
    fi


    if [ "$1" == "close" ]; then
      if [ $batch_size -gt 0 ]; then
          forward_data_to_OCI
          oci_metric clean
      fi

      return
    fi


    if [ "$#" -lt 4 ]; then
        logger -t $script_name -s -p local3.err "Error. oci_metric takes 4 mandatory parameters. Provided: $#"
        return 1
    fi

    metric_namespace=$1; shift
    metric_timestamp=$1; shift
    metric_name=$1; shift
    metric_value=$1; shift
    metric_unit=$1; shift

    : ${metric_unit:=level}

    if [ -z $oci_json_file ]; then
        logger -t $script_name -s -p local3.err "Error. oci_json_file not set. Use oci_metric initialize file first."
        return 1
    fi

    if [ -z $oci_json_array_started ]; then
        logger -t $script_name -s -p local3.err "Error. oci_json_array_started not set. Use oci_metric initialize first."
        return 1
    fi

    if [ $oci_metric_status == BUFFERING ]; then
      echo ', ' >>$oci_json_file
    fi

    oci_metric_status=BUFFERING

    cat >>$oci_json_file <<EOF
        {
                "namespace": "$metric_namespace",
                "compartmentId": "$compartment_id",
                "name": "$metric_name",
EOF

    echo "                \"dimensions\": { " >>$oci_json_file
    for dimension in ${!dimensions[@]}; do
      echo "                \"$dimension\":\"${dimensions[$dimension]}\"," >>$oci_json_file
    done      
    echo "                \"$dimension\":\"${dimensions[$dimension]}\"" >>$oci_json_file 
    echo "                }," >>$oci_json_file
                   
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


    #
    # check batch size, and send if already needed.
    #
    batch_size=$(( $batch_size + 1 ))
    # send when number of records is equal to max allowed for one payload
    [ $SCRIPT_DEBUG -eq 1 ] && echo $batch_size of $batch_max 
    if [ $batch_size -eq $batch_max ]; then
        # close current batch and send data
        forward_data_to_OCI

        # initialize next batch payload to be sent to oci metric
        oci_metric clean
        oci_metric initialize
    fi

}

function forward_data_to_OCI() {

    if [ -z "$telemetry_endpoint" ]; then
      logger -t $script_name -s -p local3.err "Error. Telemetry endpoint not set. Cannot continue."
      return 1
    fi

    if [ "$oci_json_array_started" == "YES" ]; then
        echo ']' >>$oci_json_file
        unset oci_json_array_started
    fi

    # send
    oci monitoring metric-data post --metric-data file://$tmp/data.json \
    --endpoint $telemetry_endpoint > $tmp/response.json
    if [ $? -eq 0 ];then
        logger -t $script_name -s -p local3.notice "Data sent. Data: $(cat $tmp/response.json)"
        oci_metric_status=SENT
    else
        logger -t $script_name -s -p local3.err "Error sending data. Data: $(cat $tmp/response.json)"
        oci_metric_status=SEND_ERROR
        return 1
    fi    
}


#
# test
#

function oci_telemetry_test() {
  oci_metric initialize 

  # specify namespace name as you wish
  namespace=my_telemetry

  # add any dimensions you need
  dimensions[env]=iot
  dimensions[component]=gateway
  dimensions[hostname]=$(hostname)
  dimensions[probe]=test
  dimensions[test]=test1

  # keep this date format. The datapoint timestamps must be between 2 hours ago and 10 minutes from now.
  datetime=$(date +"%Y-%m-%dT%H:%M:%S.000Z")  

  # send data with 45 data points buffer. last parameter is unit as specified by OCI, you my skip it to use defaut "level".
  oci_metric $namespace $datetime random1 $RANDOM  
  oci_metric $namespace $datetime random2 $RANDOM level 

  # flush buffer anf forward all to OCI
  oci_metric close
}


