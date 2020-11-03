#!/bin/bash

#
# API: https://docs.cloud.oracle.com/en-us/iaas/tools/oci-cli/2.12.10/oci_cli_docs/cmdref/vault/secret/update-base64.html
#

function ssh_key_get() {
    env=$1
    ssh_account=$2

    if [ -z $env ] || [ -z $ssh_account ]; then
        echo "Usage: store_ssh_key env account"
        return 100
    fi

    if [ -f ~/.oci/ssh_key.config ]; then
        source ~/.oci/ssh_key.config 
    else
        echo "Error. Configuration file not in place. Provide ~/.oci/ssh_key.config with compartment, vault, and master_key ocid."
        return 100
    fi

    secret_name=$env\_$ssh_account
    content_payload=$(base64 --wrap 0 $ssh_key)
    content_name="ssh_key"

    # discover
    vsid=$(oci vault secret list --compartment-id $compartment --raw-output --query "data[?\"secret-name\" == '$secret_name'].id" | jq -r .[0])

    if [ -z "$vsid" ]; then
        echo "Error. No such key found."
        return 1
    else
        oci secrets secret-bundle get --secret-id $vsid | tr - _ |
            jq -r '.data.secret_bundle_content.content' | base64 -d

        return 0
    fi
}

ssh_key_get $@
exit $?
