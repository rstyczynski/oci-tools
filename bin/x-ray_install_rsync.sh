#!/bin/bash

function step() {
    step_title=$1

    echo 
    echo 
    echo "########################################################################"
    echo "########################################################################"
    echo "# "
    echo "# PROCEDURE: $(basename $0)"
    echo "# sTEP:      $step_title"
    echo "# "
    echo "########################################################################"
    echo "########################################################################"
}

step 'Starting...'
source ~/oci-tools/bin/config.sh

export env_files=$(getcfg x-ray env_files | tr [A-Z] [a-z])
export env=$(getcfg x-ray env | tr [A-Z] [a-z])
export component=$(getcfg x-ray component | tr [A-Z] [a-z])
export bucket=$(getcfg x-ray bucket | tr [A-Z] [a-z])

if [ -z "$env_files" ] || [ -z "$env" ] || [ -z "$component" ] || [ -z "$bucket" ]; then
    echo "Error. x-ray.config must has defined: env_files, env, component, bucket"
    exit 1
fi

export todayiso8601="\$(date -I)"
export hostname=$(hostname)

source ~/wls-tools/bin/discover_processes.sh 
discoverWLS

mkdir -p ~/.x-ray


step "10. Deploy log sync configuration files for WebLogic Admin servers"

for srvNo in ${!wls_admin[@]}; do
  export wls_server=$(getWLSjvmAttr ${wls_admin[$srvNo]} -Dweblogic.Name)
  export domain_home=$(getWLSjvmAttr ${wls_admin[$srvNo]} -Ddomain.home)
  export domain_name=$(basename $domain_home)

  echo "Processing: $domain_name/$wls_server at $domain_home"

  ~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-wls.yaml > ~/.x-ray/diagnose-$domain_name\_$wls_server.yaml
done

step "11. Deploy log sync configuration files for WebLogic Managed servers"

for srvNo in ${!wls_managed[@]}; do
  export wls_server=$(getWLSjvmAttr ${wls_managed[$srvNo]} -Dweblogic.Name)
  export domain_home=$(getWLSjvmAttr ${wls_managed[$srvNo]} -Ddomain.home)
  export domain_name=$(basename $domain_home)

  echo "Processing: $domain_name/$wls_server at $domain_home"

  ~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-wls.yaml > ~/.x-ray/diagnose-$domain_name\_$wls_server.yaml
done

step "12. Deploy log sync configuration files for OHS"

ohs_instances=$(ps aux | grep httpd | sed 's/-d /cfg=/g' | tr ' ' '\n' | grep cfg= | cut -f2 -d= | sort -u)
if [ -z "$ohs_instances" ]; then
    echo 'Error. OHS not detected'
else
    for ohs_instance in $ohs_instances; do
        export wls_server=$(basename $ohs_instance)
        export domain_name=$(echo $ohs_instance | grep -oP 'domains/.*/config' | cut -f2 -d/)
        export domain_home=$(echo $ohs_instance | grep -oP ".*/$domain_name")
        echo $wls_server, $domain_name, $domain_home

        ~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-wls.yaml > ~/.x-ray/diagnose-$domain_name\_$wls_server.yaml
    done
fi

step "13. Deploy log sync configuration files for APICS"

export domain_home=$(ps aux | grep "bin/startWebLogic.sh" | grep -v grep | tr -s ' ' | tr ' ' '\n' | grep startWebLogic.sh | sort -u | sed 's/\/bin\/startWebLogic.sh//g')
export domain_name=$(basename $domain_home)

if [ ! -d "$domain_home/apics/logs" ] || [ ! -d  "$domain_home/apics/analytics/logs" ]; then
    echo "Error. APICS not found."
else
    # Domain
    # $domain_home/apics/logs
    # $domain_home/apics/analytics/logs
    ~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-apics.yaml >~/.x-ray/diagnose-apics-$domain_name.yaml

    # AdminServer
    for srvNo in ${!wls_admin[@]}; do
        export wls_server=$(getWLSjvmAttr ${wls_admin[$srvNo]} -Dweblogic.Name)

        echo "Processing: $domain_name/$wls_server at $domain_home"
        ~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-wls.yaml >~/.x-ray/diagnose-apics-$domain_name\_$wls_server.yaml
    done

    # ManagedServer
    for srvNo in ${!wls_managed[@]}; do
        export wls_server=$(getWLSjvmAttr ${wls_managed[$srvNo]} -Dweblogic.Name)
        echo "Processing: $domain_name/$wls_server at $domain_home"
        ~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-wls.yaml >~/.x-ray/diagnose-apics-$domain_name\_$wls_server.yaml
    done
fi


step "14. Deploy log sync configuration files for umc"
~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-umc.yaml > ~/.x-ray/diagnose-umc.yaml

step "15. Deploy sync configuration files for jfr"
~/oci-tools/bin/tpl2data.sh ~/oci-tools/template/diagnose-jfr.yaml > ~/.x-ray/diagnose-jfr.yaml

step '16. Deploy sync configuration files for OSB Alerts'

~/wls-tools/bin/osb_alerts_export.sh install_x-ray_sync

step "17.  Perform initial load for all sync descriptors"
ls -l .x-ray/diagnose-*

for diag in $(ls .x-ray/diagnose-*); do
   echo "Inital data sync: $diag"
   ~/oci-tools/bin/x-ray_initial_load_rsync.sh $diag
done

step "18.  Deploy log sync crontabs for all sync descriptors"
ls -l .x-ray/diagnose-*

for diag in $(ls .x-ray/diagnose-*); do
   echo "Preparing: $diag"
   ~/oci-tools/bin/x-ray_make_cron_diagnose.sh $diag
done

step "19. Keep diagnose-*.yaml files at shared dir"

export backup_dir=$env_files/backup

source ~/wls-tools/bin/discover_processes.sh 
discoverWLS

os_user=$(getWLSjvmAttr ${wls_managed[0]} os_user) 
# admin only?
: ${os_user:=$(getWLSjvmAttr ${wls_admin[0]} os_user)}
# ohs only?
: ${os_user:=$(ps aux | grep weblogic.nodemanager | grep -v grep | cut -f1 -d' ')}

mkdir -p $backup_dir/$(hostname)

rm -rf $backup_dir/$(hostname)/diagnose-*

mwowner_home=$(cat /etc/passwd | grep "^$os_user:" | cut -d: -f6)

find $mwowner_home/.x-ray -name "diagnose-*" -exec cp -- "{}" $backup_dir/$(hostname) \;

ls -l  $backup_dir/$(hostname)/diagnose-*
