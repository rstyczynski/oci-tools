#!/bin/bash

# repository
oci_index=~/oci_index

function oci_compute_discovery() {
    date=$(date -I)

    rm -rf $oci_index/$date/compute

    mkdir -p $oci_index/$date/compute

    ln -s $oci_index/$date/compute $oci_index/latest

    #
    # Unload OCI information to directory structure
    #

    # set region name for file location purposes
    for oci_region in $regions; do

        echo "========================================"
        echo "=== Processing region $oci_region" 
        echo "========================================"

        # set region name for OCI CLI connection purposes
        export OCI_CLI_PROFILE=$oci_region

        # get instance list
        echo -n "Discovering compute instances..."
        compartment_id=$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
        instances=$(oci compute instance list  --compartment-id $compartment_id --all | jq -r .data[].id)
        echo Done.

        # get all public ip
        for instance_ocid in $instances; do
            echo $instance_ocid
            echo -n "Public:"
            public_ips=$(oci compute instance list-vnics --instance-id $instance_ocid | jq .data[] | grep public-ip | cut -d: -f2 | tr -d "[, ]" | tr -d '"')

            for public_ip in $public_ips; do
                case $public_ip in
                null)
                    echo "No public ip."
                    ;;
                *)
                    echo "Public ip detected. Processing $public_ip..."

                    wrk_dir=$oci_index/$date/compute/public_ip/$public_ip
                    mkdir -p $wrk_dir

                    echo "region=$oci_region" >> $wrk_dir/oci.info
                    echo "compartment_id=$compartment_id" >> $wrk_dir/oci.info
                    echo "instance_id=$instance_ocid" >> $wrk_dir/oci.info

                    # instance view
                    wrk_dir=$oci_index/$date/compute/instance/$instance_ocid
                    mkdir -p $wrk_dir

                    echo "region=$oci_region" >> $wrk_dir/oci.info
                    echo "compartment_id=$compartment_id" >> $wrk_dir/oci.info
                    echo "instance_id=$ocid" >> $wrk_dir/oci.info
                    echo "public_ip=$public_ip" >> $wrk_dir/oci.info

                    ;;
                esac
            done

            echo -n "Private:"
            private_ips=$(oci compute instance list-vnics --instance-id $instance_ocid | jq .data[] | grep private-ip | cut -d: -f2 | tr -d "[, ]" | tr -d '"'_)

            for private_ip in $private_ips; do
                case $private_ip in
                null)
                    echo "No private ip."
                    ;;
                *)
                    echo "Private ip detected. Processing $private_ip..."

                    wrk_dir=$oci_index/$date/compute/private_ip/$private_ip
                    mkdir -p $wrk_dir

                    echo "region=$oci_region" >> $wrk_dir/oci.info
                    echo "compartment_id=$compartment_id" >> $wrk_dir/oci.info
                    echo "instance_id=$instance_ocid" >> $wrk_dir/oci.info

                    # instance view
                    wrk_dir=$oci_index/$date/compute/instance/$instance_ocid
                    mkdir -p $wrk_dir

                    echo "region=$oci_region" >> $wrk_dir/oci.info
                    echo "compartment_id=$compartment_id" >> $wrk_dir/oci.info
                    echo "instance_id=$ocid" >> $wrk_dir/oci.info
                    echo "private_ip=$private_ip" >> $wrk_dir/oci.info

                    ;;
                esac
            done

        done
    done
}

function oci_db_discovery() {
    date=$(date -I)

    rm -rf $oci_index/$date

    mkdir -p $oci_index/$date

    ln -s $oci_index/$date $oci_index/latest

    # set region name for file location purposes
    for oci_region in $regions; do

        echo "========================================"
        echo "=== Processing region $oci_region"
        echo "========================================"

        # set region name for OCI CLI connection purposes
        export OCI_CLI_PROFILE=$oci_region

        # get instance list
        echo "Discovering database systems..."
        compartment_id=$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
        db_system_ids=$(oci db database list -c $compartment_id | jq ".data[]" | grep 'db-system-id' | cut -f2 -d: | tr -d '," ')

        for db_system_id in $db_system_ids; do
            echo "Database id: $db_system_id"

            db_list=$(oci db database list -c $compartment_id | jq ".data[]")

            db_info=$(echo $db_list | sed s/db-system-id/db_system_id/g | jq "select(.db_system_id==\"$db_system_id\")")

            # {
            # "character-set": "AL32UTF8",
            # "compartment-id": "ocid1.compartment.oc1..aaaaaaaai3ynjnzj5v4wizepnfosvcd4ntv2jgctqh4wpymhcn3odhuw6luq",
            # "connection-strings": {
            #     "all-connection-strings": {
            #     "cdbDefault": "uat-ribdb01.netuatdb.mhauatvcn.oraclevcn.com:1521/ribuat_lhr3gg.netuatdb.mhauatvcn.oraclevcn.com",
            #     "cdbIpDefault": "(DESCRIPTION=(CONNECT_TIMEOUT=5)(TRANSPORT_CONNECT_TIMEOUT=3)(RETRY_COUNT=3)(ADDRESS_LIST=(LOAD_BALANCE=on)(ADDRESS=(PROTOCOL=TCP)(HOST=10.196.1.33)(PORT=1521)))(CONNECT_DATA=(SERVICE_NAME=ribuat_lhr3gg.netuatdb.mhauatvcn.oraclevcn.com)))"
            #     },
            #     "cdb-default": "uat-ribdb01.netuatdb.mhauatvcn.oraclevcn.com:1521/ribuat_lhr3gg.netuatdb.mhauatvcn.oraclevcn.com",
            #     "cdb-ip-default": "(DESCRIPTION=(CONNECT_TIMEOUT=5)(TRANSPORT_CONNECT_TIMEOUT=3)(RETRY_COUNT=3)(ADDRESS_LIST=(LOAD_BALANCE=on)(ADDRESS=(PROTOCOL=TCP)(HOST=10.196.1.33)(PORT=1521)))(CONNECT_DATA=(SERVICE_NAME=ribuat_lhr3gg.netuatdb.mhauatvcn.oraclevcn.com)))"
            # },
            # "db-backup-config": {
            #     "auto-backup-enabled": true,
            #     "auto-backup-window": null,
            #     "backup-destination-details": null,
            #     "recovery-window-in-days": 30
            # },
            # "db-home-id": "ocid1.dbhome.oc1.uk-london-1.abwgiljtzaq5bq5vgtmaidulpcannsrugfktt4jvgnbwq6khjymwueb6clnq",
            # "db-name": "ribuat",
            # "db-system-id": "ocid1.dbsystem.oc1.uk-london-1.abwgiljtm363jfrmduegc2rr24eqid3oq7tymrd75sq4ntyvapynlx6hloba",
            # "db-unique-name": "ribuat_lhr3gg",
            # "db-workload": "OLTP",
            # "defined-tags": {},
            # "freeform-tags": {
            #     "env": "UAT"
            # },
            # "id": "ocid1.database.oc1.uk-london-1.abwgiljt2pfpui7bseafyvvkawbyoyb647u3njnueo3uyms3kcpnhauowa5q",
            # "lifecycle-details": null,
            # "lifecycle-state": "AVAILABLE",
            # "ncharacter-set": "AL16UTF16",
            # "pdb-name": "ribpuat",
            # "time-created": "2020-03-18T18:37:57.115000+00:00",
            # "vm-cluster-id": null
            # }
            db_name=$(echo $db_info | jq . | grep '"db-name":' | cut -f2 -d: | tr -d '," ')
            echo " - processing db: $db_name"
            echo " - getting list of nodes"
            db_node_list=$(oci db node list -c $compartment_id --db-system-id $db_system_id)
            # {
            # "data": [
            #     {
            #     "additional-details": null,
            #     "backup-vnic-id": null,
            #     "db-system-id": "ocid1.dbsystem.oc1.uk-london-1.abwgiljrpluxv3jjvedvfjbkqgi4sqydlgjavku2koavm35ffk4wdvx4dwqa",
            #     "fault-domain": "FAULT-DOMAIN-1",
            #     "hostname": "preprodmftdb2",
            #     "id": "ocid1.dbnode.oc1.uk-london-1.abwgiljregrigoapdvbw2svvf6dpeuoqae2bu4tkfv7n2radmmc2zyovgv3q",
            #     "lifecycle-state": "AVAILABLE",
            #     "maintenance-type": null,
            #     "software-storage-size-in-gb": 200,
            #     "time-created": "2019-06-25T04:16:53.689000+00:00",
            #     "time-maintenance-window-end": null,
            #     "time-maintenance-window-start": null,
            #     "vnic-id": "ocid1.vnic.oc1.uk-london-1.abwgiljrpkx2j7znycr3a5vc6tmlju7b4j2b5kczkepcwhyycor4yomrw3jq"
            #     },
            #     {
            #     "additional-details": null,
            #     "backup-vnic-id": null,
            #     "db-system-id": "ocid1.dbsystem.oc1.uk-london-1.abwgiljrpluxv3jjvedvfjbkqgi4sqydlgjavku2koavm35ffk4wdvx4dwqa",
            #     "fault-domain": "FAULT-DOMAIN-3",
            #     "hostname": "preprodmftdb1",
            #     "id": "ocid1.dbnode.oc1.uk-london-1.abwgiljryiyw43fh5rgcnieec2ksekcj22ynluyitdnmc2mrklulqiwjvwsq",
            #     "lifecycle-state": "AVAILABLE",
            #     "maintenance-type": null,
            #     "software-storage-size-in-gb": 200,
            #     "time-created": "2019-06-25T04:16:53.688000+00:00",
            #     "time-maintenance-window-end": null,
            #     "time-maintenance-window-start": null,
            #     "vnic-id": "ocid1.vnic.oc1.uk-london-1.abwgiljrq5uch2bxjilk3mvakl7dfo37by6jr5mg7ktfpewx2dngzri7wfga"
            #     }
            # ]
            # }

            node_ids=$(echo $db_node_list | jq -r '.data[].id')

            unset private_ips
            for node_id in $node_ids; do

                db_node=$(echo $db_node_list | jq '.data[]' | jq "select(.id==\"$node_id\")")
                vnic_id=$(echo $db_node | jq . | grep '"vnic-id":' | cut -f2 -d: | tr -d '," ')

                echo " - processing node $node_id"

                vnic_info=$(oci network vnic get --vnic-id $vnic_id)
                # {
                # "data": {
                #     "availability-domain": "JVtM:UK-LONDON-1-AD-1",
                #     "compartment-id": "ocid1.compartment.oc1..aaaaaaaai3ynjnzj5v4wizepnfosvcd4ntv2jgctqh4wpymhcn3odhuw6luq",
                #     "defined-tags": {},
                #     "display-name": "ocid1.dbnode.oc1.uk-london-1.abwgiljryiyw43fh5rgcnieec2ksekcj22ynluyitdnmc2mrklulqiwjvwsq",
                #     "freeform-tags": {},
                #     "hostname-label": "preprodmftdb1",
                #     "id": "ocid1.vnic.oc1.uk-london-1.abwgiljrq5uch2bxjilk3mvakl7dfo37by6jr5mg7ktfpewx2dngzri7wfga",
                #     "is-primary": true,
                #     "lifecycle-state": "AVAILABLE",
                #     "mac-address": "02:00:17:00:2F:30",
                #     "nsg-ids": [],
                #     "private-ip": "10.196.1.12",
                #     "public-ip": null,
                #     "skip-source-dest-check": false,
                #     "subnet-id": "ocid1.subnet.oc1.uk-london-1.aaaaaaaaoswri2yzjgyql7se4mlwfs37ogyt2a4cdjcq34rh7oi2cdr72gaa",
                #     "time-created": "2019-06-25T04:17:02.475000+00:00"
                # },
                # "etag": "4d7cfa3d"
                # }

                private_ip=$(echo $vnic_info | jq . | grep 'private-ip' | cut -f2 -d: | tr -d '," ')

                # by private ip
                wrk_dir=$oci_index/$date/db/private_ip/$private_ip
                mkdir -p $wrk_dir

                echo $db_info | jq . >$wrk_dir/db_info.json
                echo $db_node | jq . >$wrk_dir/db_node_info.json
                echo $vnic_info | jq . >$wrk_dir/vnic_info.json

                echo "region=$oci_region" >>$wrk_dir/oci.info
                echo "compartment_id=$compartment_id" >>$wrk_dir/oci.info
                echo "db_system_id=$db_system_id" >>$wrk_dir/oci.info
                echo "db_name=$db_name" >>$wrk_dir/oci.info
                echo "db_node_id=$node_id" >>$wrk_dir/oci.info
                echo "private_ip=$private_ip" >>$wrk_dir/oci.info

                if [ -z "$private_ips" ]; then
                    private_ips="$private_ip"
                else
                    private_ips="$private_ips, $private_ip"
                fi
            done

            # by system id
            wrk_dir=$oci_index/$date/db/system_id/$db_system_id
            mkdir -p $wrk_dir

            echo $db_info | jq . >$wrk_dir/db_info.json
            echo $db_node_list | jq . >$wrk_dir/db_node_list_info.json

            echo "region=$oci_region" >>$wrk_dir/oci.info
            echo "compartment_id=$compartment_id" >>$wrk_dir/oci.info
            echo "db_system_id=$db_system_id" >>$wrk_dir/oci.info
            echo "db_name=$db_name" >>$wrk_dir/oci.info
            echo "private_ips=$private_ips" >>$wrk_dir/oci.info

            # by name
            wrk_dir=$oci_index/$date/db/name/$db_name
            mkdir -p $wrk_dir

            echo $db_info | jq . >$wrk_dir/db_info.json
            echo $db_node_list | jq . >$wrk_dir/db_node_list_info.json

            echo "region=$oci_region" >>$wrk_dir/oci.info
            echo "compartment_id=$compartment_id" >>$wrk_dir/oci.info
            echo "db_system_id=$db_system_id" >>$wrk_dir/oci.info
            echo "db_name=$db_name" >>$wrk_dir/oci.info
            echo "private_ips=$private_ips" >>$wrk_dir/oci.info

        done
        echo Done.
    done
}


#
# get info
# 

function get_compute_info() {
    local private_ip=$1
    local element=$2
    
    if [ -f $oci_index/latest/compute/private_ip/$private_ip/oci.info ]; then
        cat $oci_index/latest/compute/private_ip/$private_ip/oci.info | grep "$element=" | cut -f2 -d=
    fi
}

function get_db_info() {
    local private_ip=$1
    local element=$2
    
    if [ -f $oci_index/latest/db/private_ip/$private_ip/oci.info ]; then
        cat $oci_index/latest/db/private_ip/$private_ip/oci.info | grep "$element=" | cut -f2 -d=
    fi
}

#
# run
#

cmd=$1
regions=$2

case $cmd in
    compute)
        oci_compute_discovery
        ;;
    db)
        oci_db_discovery
        ;;
    all)
        oci_compute_discovery
        oci_db_discovery
        ;;
esac