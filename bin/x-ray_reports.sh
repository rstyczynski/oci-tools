#!/bin/bash


#
# formating
# 

unset sayatcell
function sayatcell() {

    nl=yes
    if [ "$1" == '-n' ]; then
        nl=no
        shift
    fi

    fr=no
    if [ "$1" == '-f' ]; then
        fr=yes
        shift
    fi

    what="$1"; shift
    size=$1; shift

    back='____________________________________________________________________________________________________________'
    back='                                                                                                            '
    dots='............................................................................................................'

    what_lth=$(echo -n "$what" | wc -c)

    if [ $what_lth -lt $size ]; then
        pre=$(echo "($size - $what_lth)/2" | bc)
        post=$(echo "$size - $what_lth - $pre" | bc)
        
        if [ $pre -gt 0 ]; then 
            echo -n "$back" | cut -b1-$pre | tr -d '\n'
        fi

        echo -n "$what"
        
        if [ $post -gt 0 ]; then
            echo -n "$back" | cut -b1-$post | tr -d '\n'
        fi

    elif [ $what_lth -gt $size ]; then
        echo -n "$what" | cut -b1-$(( $size - 2 )) | tr -d '\n'
        echo -n "$dots" | cut -b1-2 | tr -d '\n'
    elif [ $what_lth -eq $size ]; then
        echo -n "$what" 
    fi

    if [ $nl == yes ]; then
        if [ $fr == yes ]; then
            echo '|'
        else
            echo
        fi
    elif [ $fr == yes ]; then
            echo -n '|'
    fi
}



unset header1
function header1() {

  for cnt in {1..3}; do
    echo -n '=================='
  done
  echo

  echo "========= $@"

  for cnt in {1..3}; do
    echo -n '=================='
  done
  echo
}

unset header2
function header2() {

  for cnt in {1..2}; do
    echo -n '=================='
  done
  echo

  echo "========= $@"

  for cnt in {1..2}; do
    echo -n '=================='
  done
  echo
}

unset header3
function header3() {

  for cnt in {1..1}; do
    echo -n '=================='
  done
  echo

  echo "========= $@"

  for cnt in {1..1}; do
    echo -n '=================='
  done
  echo
}

#
# compute 
#

unset get_data_stats
function get_data_stats() {
  local data_file=$1
  local column=$2
  local precision=$3
  local multipliction=$4

  : ${precision:='%d'}
  : ${multipliction:=1}

  if [ ! -f $umcRoot/bin/csv_rewrite.py ]; then
    echo "Error. umc tool csv_rewrite not found. Initialize umc before running this tool."
  fi

  data=$(
    cat $data_file | 
    python3 $umcRoot/bin/csv_rewrite.py --columns=$column 2> /dev/null | 
    sed -n "/$date $hour_start:/,/$date $hour_stop:/p" | 
    cut -d, -f6 | 
    grep -v $column
  )
  avg=$(echo $data | tr ' ' '\n' | awk "{ total += \$1 } END { printf \"$precision\", total/NR * $multipliction  }")
  stddev=$(echo $data | tr ' ' '\n'  | 
          awk "
              {for(i=1;i<=NF;i++) { sum[i] += \$i; sumsq[i] += (\$i)^2}} 
              END {for (i=1;i<=NF;i++) { 
                 val=(sumsq[i]-sum[i]^2/NR)/NR
                 if (val>0)
                  val=0
                 printf \"$precision\", sqrt(val) * $multipliction };
              }
              "
          )
  : ${stddev:=0}
  min=$(echo $data | tr ' ' '\n' | awk "BEGIN {min=2^52} {if (\$1<0+min) min=\$1} END {printf \"$precision\", min * $multipliction}")
  max=$(echo $data | tr ' ' '\n' | awk "BEGIN {max=0} {if (\$1>0+max) max=\$1} END {printf \"$precision\", max * $multipliction }")
}

unset print_header
function print_header() {
  local data_file=$1
  local columns=$2

  for column in $(echo $columns | tr , ' '); do
    column=$( echo $column | sed 's/^_//' )
    sayatcell -n "$column" 30
  done
  echo
}

unset print_current_data
function print_current_data() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  for column in $(echo $columns | tr , ' '); do
    if [[ $column == _* ]]; then
      var_name=$( echo $column | sed 's/^_//' )
      var_value=${!var_name}
      sayatcell -n "$var_value" 30
    else
      get_data_stats $data_file $column $precision $multipliction
      sayatcell -n "$avg" 30
    fi
  done
  echo
}

unset print_current
function print_current() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  print_header $@
  print_current_data $@
}

unset print_counter_data
function print_counter_data() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  for column in $(echo $columns | tr , ' '); do
    if [[ $column == _* ]]; then
      var_name=$( echo $column | sed 's/^_//' )
      var_value=${!var_name}
      sayatcell -n "$var_value" 30
    else
      get_data_stats $data_file $column $precision $multipliction
      delta=$(( $max - $min ))
      minutes=$(( $get_last_hours * 60  ))

      dvdt=$(echo "scale=2; $delta/$minutes" | bc)

      sayatcell -n "$max | $dvdt /min" 30
    fi
  done
  echo
}

unset print_counter
function print_counter() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  print_header $@
  print_counter_data $@
}

unset print_ceiling_data
function print_ceiling_data() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  for column in $(echo $columns | tr , ' '); do
    if [[ $column == _* ]]; then
      var_name=$( echo $column | sed 's/^_//' )
      var_value=${!var_name}
      sayatcell -n "$var_value" 30
    else
      get_data_stats $data_file $column $precision $multipliction
      sayatcell -n "$max" 30
    fi
  done
  echo
}


unset print_ceiling
function print_ceiling() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  print_header $@
  print_ceiling_data $@
}


#
# reports
#

unset report_OCI_instances
function report_OCI_instances() {
  env_code=$1
  component=$2
  get_last_hours=$3

  date=$(date -I)
  hour_stop=$(date "+%H")
  hour_start=$(date -d "$get_last_hours hours ago" "+%H")

  date_start=$(date -d "$get_last_hours hours ago" -I)
  if [ $date_start != $date ]; then
    echo "Report will be computed fromm $date 00:00:00"
    hour_start=00
  fi

  header1 "Compute instances" 
  echo "Time window from $date $hour_start:00:00 UTC to $date $hour_stop:00:00 UTC"

  hosts=$(ls /mwlogs/x-ray/$env_code/$component/diag/hosts)

  header2 "Load average"

  columns=_host,load1min,load5min,load15min
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-uptime.log
      print_current_data $data_file $columns %0.2f
  done

  echo
  header2 "CPU"

  columns=_host,CPUuser,CPUsystem,CPUidle,CPUwaitIO,CPUVMStolenTime
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-vmstat.log
      print_current_data $data_file $columns
  done
      
  columns=_host,ProcessRunQueue,ProcessBlocked
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-vmstat.log
      print_current_data $data_file $columns
  done

  columns=_host,Interrupts,ContextSwitches
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-vmstat.log
      print_current_data $data_file $columns
  done

  echo
  header2 "Memory"
      
  columns=_host,MemFree,MemBuff,MemCache
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-vmstat.log
      print_current_data $data_file $columns
  done

  echo
  header2 "Swap"
  columns=_host,MemSwpd,SwapReadBlocks,SwapWriteBlocks
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-vmstat.log
      print_current_data $data_file $columns
  done

  echo
  header2 "I/O"
  columns=_host,IOReadBlocks,IOWriteBlocks
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-vmstat.log
      print_current_data $data_file $columns
  done

  echo
  header2 "Boot volume space" 
  columns=_host,capacity
  echo; print_header $data_file $columns
  for host in $hosts; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/disk-space-mount1.log
      print_current_data $data_file $columns
  done

}

unset report_WLS
function report_WLS() {
  env_code=$1
  component=$2
  get_last_hours=$3

  date=$(date -I)
  hour_stop=$(date "+%H")
  hour_start=$(date -d "$get_last_hours hours ago" "+%H")

  date_start=$(date -d "$get_last_hours hours ago" -I)
  if [ $date_start != $date ]; then
    echo "Report will be computed fromm $date 00:00:00"
    hour_start=00
  fi

  header1 "WebLogic domains"
  echo "Time window from $date $hour_start:00:00 UTC to $date $hour_stop:00:00 UTC"

  echo
  header2 "General"

  columns=_domain,_server,thread_total,thread_idle,thread_hogging,thread_standby
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,heap_size,heap_free_pct
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,request_pending,request_troughput
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,request_completed
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      if [ -f $data_file ]; then
        print_counter_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,sockets_open,sockets_opened
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done



  echo
  header2 'Channels'
  
  channels=$(
    cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
    ls wls_channel_$domain\_$server\_*   2>/dev/null | 
    grep -v _dt.log | 
    sed "s/wls_channel_$domain\_$server\_//g" | 
    sed "s/\.log//g"
    cd - >/dev/null
  )


  columns=_domain,_server,_channel,accepts
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for channel in $channels; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_channel,connections
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for channel in $channels; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 
        if [ -f $data_file ]; then
          print_counter_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_channel,bytesReceived,byteSent
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for channel in $channels; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_channel,msgReceived,msgSent
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for channel in $channels; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done



  echo
  header2 "Data sources"

  data_sources=$(
    cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
    ls wls_datasource_$domain\_$server\_* 2>/dev/null | 
    grep -v _dt.log | 
    sed "s/wls_datasource_$domain\_$server\_//g" | 
    sed "s/\.log//g"
    cd - >/dev/null
  )

  columns=_domain,_server,_data_source,activeConnectionsAverage,capacity,numAvailable
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for data_source in $data_sources; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_datasource_$domain\_$server\_$data_source.log
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_data_source,waitingForConnectionTotal
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for data_source in $data_sources; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_datasource_$domain\_$server\_$data_source.log
        if [ -f $data_file ]; then
          print_counter_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done


  echo
  header2 "JMS Server"
  
  jms_servers=$(
    cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
    ls wls_jmsserver_$domain\_$server\_* 2>/dev/null | 
    grep -v _dt.log | 
    sed "s/wls_jmsserver_$domain\_$server\_//g" | 
    sed "s/\.log//g"
    cd - >/dev/null
  )

  columns=_domain,_server,_jms_server,destinations
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for jms_server in $jms_servers; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_jms_server,messagesPending,bytesPending
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for jms_server in $jms_servers; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_jms_server,messages,bytes
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for jms_server in $jms_servers; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_jms_server,messagesReceived,bytesReceived
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for jms_server in $jms_servers; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
        if [ -f $data_file ]; then
          print_counter_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done


  echo
  header2 "JMS Runtime"
  
  jms_runtimes=$(
    cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
    ls wls_jmsruntime_$domain\_$server\_* 2>/dev/null | 
    grep -v _dt.log | 
    sed "s/wls_jmsruntime_$domain\_$server\_//g" | 
    sed "s/\.log//g"
    cd - >/dev/null
  )

  columns=_domain,_server,_jms_runtime,connections
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for jms_runtime in $jms_runtimes; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
        if [ -f $data_file ]; then
          print_current_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_jms_runtime,connectionsHigh
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    for jms_runtime in $jms_runtimes; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
        if [ -f $data_file ]; then
          print_ceiling_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done

  columns=_domain,_server,_jms_runtime,connectionsTotal
  echo; print_header $data_file $columns
  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

     for jms_runtime in $jms_runtimes; do

      servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do
        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
        if [ -f $data_file ]; then
          print_counter_data $data_file $columns
        else
          : # echo "(none)"
        fi
      done
    done
  done


}