#!/bin/bash

unset analyse_error_codes
function analyse_error_codes(){
  local c1xx=$1
  local c2xx=$2
  local c3xx=$3
  local c4xx=$4
  local c5xx=$5

  alert=OK
  alert_code=0
  warning=OK
  warning_code=0
  if [ $c5xx -gt $c2xx ]; then
    if [ $c2xx -eq 0 ]; then
      alert="All requsts failed."
      alert_code=1
    else
      alert="Majority of requsts failed."
      alert_code=2
    fi
  else
    if [ $c5xx -gt 0 ]; then
      warning="Some failures."
      warning_code=1
    fi
  fi

}

unset ohs_access_http_code
function ohs_access_http_code() {

env=$1

csv_delim=,

cvs_line_open=0
function csv_push_data {
  echo -n $csv_delim$@
  cvs_line_open=1
}

function csv_start_line() {
  if [ $cvs_line_open -eq 1 ]; then
    echo 
  fi
  echo -n $@
}

function prep_time_slot() {
  time=$1

  if [ -z "$time" ]; then
    time_slot="\d\d:\d\d:\d\d" 
  else
    # 
    # time slot
    time_mask=$(echo $time | tr '[0-9]' 9)
    case $time_mask in
    99:99:99)
      time_slot=$(echo $time | cut -b1-8) 
      ;;
    99:99:9)
      time_slot=$(echo $time  | cut -b1-7)
      time_slot="$time_slot\d"
      ;;
    99:99:)
      time_slot=$(echo $time  | cut -b1-5)
      time_slot="$time_slot:\d\d" 
      ;;
    99:99)
      time_slot=$(echo $time  | cut -b1-5)
      time_slot="$time_slot:\d\d" 
      ;;
    99:9)
      time_slot=$(echo $time  | cut -b1-4)
      time_slot="$time_slot\d:\d\d" 
      ;;
    99:)
      time_slot=$(echo $time  | cut -b1-2)
      time_slot="$time_slot:\d\d:\d\d" 
      ;;
    99)
      time_slot=$(echo $time  | cut -b1-2)
      time_slot="$time_slot:\d\d:\d\d" 
      ;;
    9)
      time_slot=$(echo $time  | cut -b1)
      time_slot="0$time_slot:\d\d:\d\d" 
      ;;
    esac
  fi

  echo $time_slot
}


tech_ULR="/console|/em|/servicebus|/OracleHTTPServer12c_files|/favicon.ico|/soa/composer|/integration/worklistapp|/wsm-pm|^/$|^/soa-infra$|^/soa-infra/$"

url_depth=100

: ${ohs_access_pos_url:=8}
: ${ohs_access_pos_code:=10}


: ${date:=$(date +"%Y-%m-%d")}

date_slot=$date
date_txt=$date_slot

months=(none Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

date_y=$(echo $date_txt | cut -b1-4)
date_m=$(echo $date_txt | cut -b6-7)
date_m_int=$(echo $date_m | tr -d 0)
date_d=$(echo $date_txt | cut -b9-10)

date_txt_ohs=$date_d/${months[$date_m_int]}/$date_y


time=$(date +"%H" | cut -b1-2)

if [ -z "$time" ]; then

  if [ $date == $(date +"%Y-%m-%d") ]; then
    # now
    #
    time=$(date +"%H:%M" | cut -b1-4)
    time_slot=$(prep_time_slot $time)
  else
    #
    # full day
    time_slot="\d\d:\d\d:\d\d"
  fi
else
  if [ $time == 'day' ]; then
    time_slot="\d\d:\d\d:\d\d"
  else
    time_slot=$(prep_time_slot $time)
  fi
fi

# HEADER

csv_start_line date_slot
csv_push_data time_slot 
csv_push_data service 
csv_push_data calls 
csv_push_data c1xx 
csv_push_data c2xx
csv_push_data c3xx
csv_push_data c4xx
csv_push_data c5xx
csv_push_data c1xx_pct
csv_push_data c2xx_pct
csv_push_data c3xx_pct
csv_push_data c4xx_pct
csv_push_data c5xx_pct
csv_push_data warning_code
csv_push_data warning
csv_push_data alert_code
csv_push_data alert

declare -A ohs_log
declare -A log_service

# DATA
cd /mwlogs/x-ray/$(echo $env | tr [A-Z] [a-z])/soa/diag/wls/log

services=$(grep -P "$date_txt_ohs:$time_slot\s+" ./*/ohs*/$date_txt/access* | tr '?' ' ' | cut -f$ohs_access_pos_url -d' '| egrep -v "$tech_ULR"| cut -f1-$url_depth -d '/' | sort | uniq )

for service in $services; do

  log_service[$service]=$service

  calls=$(grep -P "$date_txt_ohs:$time_slot\s+" ./*/ohs*/$date_txt/access* | grep $service | wc -l)
  code_count=$(grep -P "$date_txt_ohs:$time_slot\s+" ./*/ohs*/$date_txt/access* | grep $service | cut -f$ohs_access_pos_code -d' ' | sort | cut -b1 | grep -P '\d' | uniq -c | sed 's/$/xx/g' | sed 's/^\s*//g' | tr ' ' ';')

  c1xx=$(echo $code_count | tr ' ' '\n' | grep "1xx" | cut -f1 -d';')
  : ${c1xx:=0}
  c2xx=$(echo $code_count | tr ' ' '\n' | grep "2xx" | cut -f1 -d';')
  : ${c2xx:=0}
  c3xx=$(echo $code_count | tr ' ' '\n' | grep "3xx" | cut -f1 -d';')
  : ${c3xx:=0}
  c4xx=$(echo $code_count | tr ' ' '\n' | grep "4xx" | cut -f1 -d';')
  : ${c4xx:=0}
  c5xx=$(echo $code_count | tr ' ' '\n' | grep "5xx" | cut -f1 -d';')
  : ${c5xx:=0}

  ohs_log[$service\_calls]=$calls 
  ohs_log[$service\_c1xx]=$c1xx 
  ohs_log[$service\_c2xx]=$c2xx 
  ohs_log[$service\_c3xx]=$c3xx 
  ohs_log[$service\_c4xx]=$c4xx 
  ohs_log[$service\_c5xx]=$c5xx 

  if [ $calls -gt 0 ]; then
    ohs_log[$service\_c1xx_pct]=$(( $c1xx / $calls * 100 ))
    ohs_log[$service\_c2xx_pct]=$(( $c2xx / $calls * 100 ))
    ohs_log[$service\_c3xx_pct]=$(( $c3xx / $calls * 100 ))
    ohs_log[$service\_c4xx_pct]=$(( $c4xx / $calls * 100 ))
    ohs_log[$service\_c5xx_pct]=$(( $c5xx / $calls * 100 ))
  else
    ohs_log[$service\_c1xx_pct]=0
    ohs_log[$service\_c2xx_pct]=0
    ohs_log[$service\_c3xx_pct]=0
    ohs_log[$service\_c4xx_pct]=0
    ohs_log[$service\_c5xx_pct]=0
  fi

  # analyse
  analyse_error_codes $c1xx $c2xx $c3xx $c4xx $c5xx

# print row

  csv_start_line $date_txt
  csv_push_data  $time_slot 
  csv_push_data $service 
  csv_push_data ${ohs_log[$service\_calls]} 
  csv_push_data ${ohs_log[$service\_c1xx]} 
  csv_push_data ${ohs_log[$service\_c2xx]} 
  csv_push_data ${ohs_log[$service\_c3xx]} 
  csv_push_data ${ohs_log[$service\_c4xx]} 
  csv_push_data ${ohs_log[$service\_c5xx]} 
  csv_push_data ${ohs_log[$service\_c1xx_pct]} 
  csv_push_data ${ohs_log[$service\_c2xx_pct]} 
  csv_push_data ${ohs_log[$service\_c3xx_pct]} 
  csv_push_data ${ohs_log[$service\_c4xx_pct]} 
  csv_push_data ${ohs_log[$service\_c5xx_pct]} 
  csv_push_data $warning_code
  csv_push_data $warning
  csv_push_data $alert_code
  csv_push_data $alert
done

}

#access_ohs_code $@

source ~/umc/bin/umc.h
ohs_access_http_code prod | csv2obd --resource csv:3 --resource_log_prefix ~/log/$(date +%Y-%m-%d)/ohs_service --status_root=~/x-ray/watch/services

cat ~/obd/*/state | egrep "service=|alert=" | tr -d '\n' | sed 's/service=/\nservice=/g' | sed 's/alert=/ alert=/g'
