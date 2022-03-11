
#
# x-ray log server reports
#

function x-ray_report_egress() {
  env=$1
  days=$2
  components=$3

  : ${days:=$(date -I | cut -d- -f1-2)}

  tcpdump_show_egress_format=CSV
  tcpdump_show_egress_header="date,env,component,host,direction,this,other,port"

  header_displayed=NO
  
  : ${components:=$(ls /mwlogs/x-ray/$env/)}

  for component in $components; do
    compute_instances=$(ls /mwlogs/x-ray/$env/$component/diag/hosts/)
    for compute_instance in $compute_instances; do
      for day in $(ls /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic | grep $days); do
        if [ "$header_displayed" == OK ]; then
          tcpdump_show_egress_header=" "
        fi
        tcpdump_show_egress_insert="$day,$env,$component,$compute_instance,"
        tcpdump_show_egress /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic/$day

        header_displayed=OK
      done
    done
  done

  unset tcpdump_show_egress_header
  unset tcpdump_show_egress_insert
}

function x-ray_report_ingress() {
  env=$1
  days=$2
  components=$3

  : ${days:=$(date -I | cut -d- -f1-2)}

  tcpdump_show_ingress_format=CSV
  tcpdump_show_ingress_header="date,env,component,host,direction,other,this,port"

  header_displayed=NO
  
  : ${components:=$(ls /mwlogs/x-ray/$env/)}

  for component in $components; do
    compute_instances=$(ls /mwlogs/x-ray/$env/$component/diag/hosts/)
    for compute_instance in $compute_instances; do
      for day in $(ls /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic | grep $days); do
        
        if [ "$header_displayed" == OK ]; then
          tcpdump_show_ingress_header=" "
        fi
        tcpdump_show_ingress_insert="$day,$env,$component,$compute_instance,"
        tcpdump_show_ingress /mwlogs/x-ray/$env/$component/diag/hosts/$compute_instance/traffic/$day
        header_displayed=OK
      done
    done
  done

  unset tcpdump_show_ingress_header
  unset tcpdump_show_ingress_insert
}


#
# network related functions
#

function get_cidr() {
  # compute host to CIDR mapping. Uses CIDR registry specified by CIDR_registry variable, having default value ~/network/etc/cidr_global_registry.csv
  host=$1

  : ${CIDR_registry:=~/network/etc/cidr_global_registry.csv}

  if [ ! -f $CIDR_registry ]; then
    >&2 echo "Error. CIDR registry file not found!"
    return 1
  fi

  type host2cidr 2>/dev/null
  if [ $? -eq 1 ]; then
    declare -gA host2cidr
  fi

  matched_cidr=${host2cidr[$host]}

  if [ ! -z "$matched_cidr" ]; then
    echo $matched_cidr
  else
    >&2 echo -n "Testing $host..."
    matched_cidr=""
    for cidr in $(cat $CIDR_registry | cut -d, -f1 | grep -v CIDR); do   
      grepcidr "$cidr" <(echo "$host") >/dev/null
      if [ $? -eq 0 ]; then
        matched_cidr="$(grep -P "^$cidr" $CIDR_registry)"
        host2cidr[$host]=$matched_cidr
        break
      fi
    done
    if [ ! -z "$matched_cidr" ]; then
      echo $matched_cidr
    else
      matched_cidr=$(grep -P "^254.254.254.254" $CIDR_registry | sed "s/UNKNOWN/$host\/32/")
      host2cidr[$host]=$matched_cidr
      echo "$matched_cidr"
    fi
  fi
}

function get_cidr2cidr_ports() {
  csv_file=$1

  CIDR_this_column=$(csv_column CIDR_this)
  CIDR_other_column=$(csv_column CIDR_other)
  desc_other_column=$(csv_column desc_other)
  port_column=$(csv_column port)

  columns=$(echo "$CIDR_this_column
  $CIDR_other_column
  $desc_other_column
  $port_column" | sort -n | tr '\n' , | tr -d ' ' | sed 's/,$//')

  columns_no_port=$(echo "$CIDR_this_column
  $CIDR_other_column
  $desc_other_column" | sort -n | tr '\n' , | tr -d ' ' | sed 's/,$//')

  echo $(csv_header | cut -d, -f$columns_no_port),ports
  IFS=$'\n'
  for cidr_meta in $(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | sort -u); do
    >&2 echo -n "."
    CIDR_pair_columns=$(echo $(csv_header | cut -d, -f$columns) | tr ',' '\n' | nl | tr -d ' ' | tr '\t' ' '  | grep CIDR | cut -f1 -d ' ' | tr '\n' ',' | sed 's/,$//')
    CIDR_pair=$(echo $cidr_meta | cut -d, -f$CIDR_pair_columns) 

    port_column=$(echo $(csv_header | cut -d, -f$columns) | tr ',' '\n' | nl | tr -d ' ' | tr '\t' ' '  | grep port | cut -f1 -d ' ' | tr '\n' ',' | sed 's/,$//')

    ports=$(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | grep $CIDR_pair | cut -d',' -f$port_column | sort -nu | tr '\n' ';' | sed 's/;$//')

    out_columns=$(echo $(csv_header | cut -d, -f$columns) | tr ',' '\n' | nl | tr -d ' ' | tr '\t' ' '  | egrep "CIDR|desc" | cut -f1 -d ' ' | tr '\n' ',' | sed 's/,$//')
    out=$(echo $cidr_meta | cut -d, -f$out_columns | grep $CIDR_pair)

    echo $out,$ports
  done | sort -u
  >&2 echo "."
  unset IFS
}


function get_cidr2cidr() {
  csv_file=$1

  CIDR_this_column=$(csv_column CIDR_this)
  CIDR_other_column=$(csv_column CIDR_other)
  desc_other_column=$(csv_column desc_other)

  columns=$(echo "$CIDR_this_column
  $CIDR_other_column
  $desc_other_column" | sort -n | tr '\n' , | tr -d ' ' | sed 's/,$//')

  echo $(csv_header | cut -d, -f$columns),count
  IFS=$'\n'
  for cidr_meta in $(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | sort -u); do
    count=$(cat $csv_file | grep -v "$(csv_header)" | cut -d, -f$columns | grep "$cidr_meta" | wc -l)
    echo $cidr_meta,$count
  done
  unset IFS
}

function enrich_Xgress_with_subnets() {
  info='Enriches engress/ingress report with subnet information stored in CIDR_registry with default value of  ~/network/etc/cidr_global_registry.csv'

  xgress_file=$1
  csv_file=$xgress_file # required by csv_* functions

  : ${CIDR_registry:=~/network/etc/cidr_global_registry.csv}

  if [ ! -f $CIDR_registry ]; then
    >&2 echo "Error. CIDR registry file not found!"
    return 1
  fi

  if [ ! -f "$xgress_file" ]; then
    >&2 echo "Error. xgress file not found!"
    return 2
  fi

  type=this
  this_header=$(head -1 $CIDR_registry | sed "s/,/_$type,/g")_$type
  this_column=$(csv_column this)

  type=other
  other_header=$(head -1 $CIDR_registry | sed "s/,/_$type,/g")_$type
  other_column=$(csv_column other)

  echo $(csv_header),$this_header,$other_header
  for xgress_socket in $(cat $xgress_file | grep -v '^$' | grep -v $(head -1 $csv_file)); do
    >&2 echo -n "."
    this=$(echo $xgress_socket | cut -d, -f$this_column)
    get_cidr $this >/dev/null # to put value in host2cidr; w/o this host2cidr was not updated (fork problem?) 
    this_cidr=$(get_cidr $this) # to get already discovered value from host2cidr

    other=$(echo $xgress_socket | cut -d, -f$other_column)
    get_cidr $other >/dev/null # to put value in host2cidr; w/o this host2cidr was not updated (fork problem?)
    other_cidr=$(get_cidr $other) # to get already discovered value from host2cidr
    echo $xgress_socket,$this_cidr,$other_cidr
  done
  >&2 echo "."
}

# list non registered destinatino ip
function get_not_registered_addresses() {
  data_files=$1
  component=$2

  if [ ! -z $component ]; then
    component_sfx=_$component
  else
    unset component_sfx
  fi

  csv_file=$data_files/traffic_egress_cidr2cidr_ports$component_sfx.csv

  CIDR_this_column=$(csv_column CIDR_this)
  ports_column=$(csv_column ports)

  csv_file=$data_files/traffic_egress_subnets$component_sfx.csv 
  other_column=$(csv_column other)

  echo "source,destination,port,whois_owner,whois_cidr,whois_network"
  for src_with_unknown in $(cat $data_files/traffic_egress_cidr2cidr_ports$component_sfx.csv | grep UNKNOWN | cut -d, -f$CIDR_this_column); do

    ports_raw=$(cat $data_files/traffic_egress_cidr2cidr_ports$component_sfx.csv  | grep $src_with_unknown | grep UNKNOWN | cut -d, -f$ports_column)
    # ports_egrep=",$(echo $ports_raw | sed 's/;/,|,/g'),"

    IFS=';'
    for port in $ports_raw; do
      #echo
      #echo "=========="
      #echo Host from subnet $src_with_unknown talks on port: $port to following not registered ip addreses:
      IFS=$'\n'
      for host in $(cat $data_files/traffic_egress_subnets$component_sfx.csv | grep ",$src_with_unknown," | grep UNKNOWN | grep ",$port," | cut -d, -f$other_column | sort -u); do
        owner=$(whois $host | grep OrgName | cut -d: -f2 | tr -s ' ' | head -1 | tr , ' ')
        : ${owner:=$(whois $host | grep descr | cut -d: -f2 | tr -s ' ' | head -1 | tr , ' ')}
        cidr=$(whois $host | grep CIDR | cut -d: -f2 | tr -s ' ' | head -1 | tr , ';')
        network=$(whois $host | grep inetnum | cut -d: -f2 | tr -s ' ' | head -1 | tr , ';')
        echo "$src_with_unknown, $host, $port,$owner, $cidr, $network"
      done
    done
    unset IFS
  done
}

#
# build global cidr registry combined out of main, oci, and host related registries
#
# combine OCI public registry and Alshaya registry to be available at ~/network/etc/cidr_global_registry.csv
# global file is sorted in such way that wider CIDRs are on bottom of the file
#
function build_CIDR_registry() {

  unset host2cidr # clear cache


cat > ~/network/etc/UNKNOWN_registry.csv <<EOF
CIDR,category,owner,system,region,desc,url,type,id,cidr_registry
254.254.254.254/32,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,UNKNOWN,~/network/etc/UNKNOWN_registry.csv
EOF

#
# build OCI public ranges registry 
# Source: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/addressranges.htm
# Source: https://stackoverflow.com/questions/26701538/how-to-filter-an-array-of-objects-based-on-values-in-an-inner-array-with-jq
#

test -f ~/network/etc/public_ip_ranges.json && mv ~/network/etc/public_ip_ranges.json ~/network/backup/etc/public_ip_ranges.json.$(date +%s)
curl -Ls https://docs.oracle.com/iaas/tools/public_ip_ranges.json > ~/network/etc/public_ip_ranges.json

OCI_ranges=~/network/etc/public_ip_ranges.json
OCI_ranges_csv=~/network/etc/OCI_public_ip_ranges.csv

echo 'CIDR,category,owner,system,region,desc,url,type,id,cidr_registry' > $OCI_ranges_csv
regions=$(cat $OCI_ranges| jq -r '.regions[].region')
for region in $regions; do
  for cidr in $(cat $OCI_ranges | jq -r ".regions[] | select (.region==\"$region\") | .cidrs[] | select (.tags[] | contains(\"OCI\")) | .cidr") ;do
    echo "$cidr,subnet,Oracle,OCI,$region,OCI public addresses,,Internet,,public_ip_ranges.json;OCI"
  done
done >> $OCI_ranges_csv

OBJECT_STORAGE_ranges_csv=~/network/etc/OBJECT_STORAGE_public_ip_ranges.csv

echo 'CIDR,category,owner,system,region,desc,url,type,id,cidr_registry' > $OBJECT_STORAGE_ranges_csv
regions=$(cat $OCI_ranges| jq -r '.regions[].region')
for region in $regions; do
  for cidr in $(cat $OCI_ranges | jq -r ".regions[] | select (.region==\"$region\") | .cidrs[] | select (.tags[] | contains(\"OBJECT_STORAGE\")) | .cidr") ;do
    echo "$cidr,subnet,Oracle,OBJECT_STORAGE,$region,Oracle Object Storage,,Internet,,public_ip_ranges.json;OBJECT_STORAGE"
  done
done >> $OBJECT_STORAGE_ranges_csv

OSN_ranges_csv=~/network/etc/OSN_public_ip_ranges.csv

echo 'CIDR,category,owner,system,region,desc,url,type,id,cidr_registry' > $OSN_ranges_csv
regions=$(cat $OCI_ranges| jq -r '.regions[].region')
for region in $regions; do
  for cidr in $(cat $OCI_ranges | jq -r ".regions[] | select (.region==\"$region\") | .cidrs[] | select (.tags[] | contains(\"OSN\")) | .cidr") ;do
    echo "$cidr,subnet,Oracle,OSN,$region,Oracle Services Network,,Internet,,public_ip_ranges.json;OSN"
  done
done | grep -v -f <(cat $OBJECT_STORAGE_ranges_csv | cut -d, -f1 | grep -v CIDR)  >> $OSN_ranges_csv


registry=oci_internal
registry_file=~/network/etc/$registry\_registry.csv
test -f $registry_file && mv $registry_file $registry_file.$(date +%s)
cat >  $registry_file <<EOF
CIDR,category,owner,system,region,desc,url,type,id,cidr_registry
169.254.0.0/16,subnet,Oracle OCI,OCI direct connection,,OCI internal,,,,$registry_file
EOF

  csv_file=~/network/etc/UNKNOWN_registry.csv 
  csv_header=$(csv_header)

  echo $csv_header > ~/network/tmp/cidr_global_registry.csv
  cat ~/network/etc/UNKNOWN_registry.csv | grep -v "$csv_header" >> ~/network/tmp/cidr_global_registry.csv

  if [ $TENANCY_REGISTRY == yes ]; then
    cat ~/network/etc/tenancy_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $OCI_INTERNAL_REGISTRY == yes ]; then
    cat ~/network/etc/oci_internal_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $OCI_PUBLIC_REGISTRY == yes ]; then
    cat $OBJECT_STORAGE_ranges_csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
    cat $OSN_ranges_csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
    cat $OCI_ranges_csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $CIDR_REGISTRY == yes ]; then
    cat ~/network/etc/cidr_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $HOST_REGISTRY == yes ]; then
    cat ~/network/etc/host_registry.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  if [ $ENV_REGISTRY == yes ]; then
    test  -f $HOME/network/data/$env/$(date -I)/registered_ingress.csv && cat $HOME/network/data/$env/$(date -I)/registered_ingress.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
    test  -f $HOME/network/data/$env/$(date -I)/registered_egress.csv && cat $HOME/network/data/$env/$(date -I)/registered_egress.csv | grep -v "$csv_header"  >> ~/network/tmp/cidr_global_registry.csv
  fi

  # sort all cidr and hosts 
  CIDR_registry=~/network/etc/cidr_global_registry.csv
  echo $csv_header > $CIDR_registry
  cat ~/network/tmp/cidr_global_registry.csv | grep -v $csv_header | sort -t . -k 1,1nr -k 2,2nr -k 3,3nr -k 4,4nr >> $CIDR_registry 
}

