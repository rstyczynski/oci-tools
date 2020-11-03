#!/bin/bash

#
# API: https://docs.cloud.oracle.com/en-us/iaas/tools/oci-cli/2.12.10/oci_cli_docs/cmdref/vault/secret/update-base64.html
#

function ssh_key_store() {
    env=$1
    ssh_account=$2
    ssh_key=$3

    if [ -z $env ] || [ -z $ssh_account ] || [ -z $ssh_key ]; then
        echo "Usage: store_ssh_key env account key"
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
        # create
        oci vault secret create-base64 \
            --compartment-id $compartment \
            --vault-id $vault \
            --key-id $master_key \
            --secret-content-stage CURRENT \
            --secret-name "$secret_name" \
            --secret-content-content "$content_payload" \
            --secret-content-name "$content_name"

            echo "OK. Uploaded initial version."
            return 0
    else
        current_payload_hash=$(oci secrets secret-bundle get --secret-id $vsid | tr - _ |
            jq -r '.data.secret_bundle_content.content' | base64 -d | sha384sum | cut -f1 -d ' ')
        new_payload_hash=$(echo $content_payload | base64 -d | sha384sum | cut -f1 -d ' ')

        if [ "$new_payload_hash" != "$current_payload_hash" ]; then
            # add new version
            oci vault secret update-base64 \
                --secret-id $vsid \
                --secret-content-content "$content_payload"
            
            echo "OK. Uploaded new version."
            return 1
        else

            echo "OK. The same version already in vault."
            return 2
        fi
    fi
}

ssh_key_store $@
exit $?
