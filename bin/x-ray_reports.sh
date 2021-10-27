#!/bin/bash

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


function get_data_stats() {
  local data_file=$1
  local column=$2
  local precision=$3
  local multipliction=$4

  : ${precision:='%d'}
  : ${multipliction:=1}

  data=$(
    cat $data_file | 
    python3 ~/csv_rewrite.py --columns=$column 2> /dev/null | 
    sed -n "/$date $hour_start:/,/$date $hour_stop:/p" | 
    cut -d, -f6 | 
    grep -v $column
  )
  avg=$(echo $data | tr ' ' '\n' | awk "{ total += \$1 } END { printf \"$precision\", total/NR * $multipliction  }")
  stddev=$(echo $data | tr ' ' '\n'  | awk "{for(i=1;i<=NF;i++) {sum[i] += \$i; sumsq[i] += (\$i)^2}} 
          END {for (i=1;i<=NF;i++) { printf \"$precision\", sqrt((sumsq[i]-sum[i]^2/NR)/NR) * $multipliction } }")
  min=$(echo $data | tr ' ' '\n' | awk "BEGIN {min=2^52} {if (\$1<0+min) min=\$1} END {printf \"$precision\", min * $multipliction}")
  max=$(echo $data | tr ' ' '\n' | awk "BEGIN {max=0} {if (\$1>0+max) max=\$1} END {printf \"$precision\", max * $multipliction }")
}

function print_avg() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  for column in $(echo $columns | tr , ' '); do
    sayatcell -n "$column" 30
  done
  echo
  for column in $(echo $columns | tr , ' '); do
    get_data_stats $data_file $column
    sayatcell -n "$avg" 30
  done
  echo
}

function print_max() {
  local data_file=$1
  local columns=$2
  local precision=$3
  local multipliction=$4

  for column in $(echo $columns | tr , ' '); do
    sayatcell -n "$column" 30
  done
  echo
  for column in $(echo $columns | tr , ' '); do
    get_data_stats $data_file $column
    sayatcell -n "$max" 30
  done
  echo
}

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
    hour_start=0
  fi

  sayatcell '=================================================' 100
  sayatcell " Compute instances" 100
  sayatcell '=================================================' 100

  hosts=$(ls /mwlogs/x-ray/$env_code/$component/diag/hosts)
  for host in $hosts; do
      echo
      sayatcell '=================================================' 100
      sayatcell " Compute instance: $host" 100
      sayatcell '=================================================' 100

      sayatcell '=================================================' 100
      sayatcell "Load average" 100
      sayatcell '=================================================' 100

      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-uptime.log
      columns=load1min,load5min,load15min
      print_avg $data_file $columns


      sayatcell '=================================================' 100
      sayatcell "CPU" 100
      sayatcell '=================================================' 100
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/system-vmstat.log

      columns=CPUuser,CPUsystem,CPUidle,CPUwaitIO,CPUVMStolenTime 
      print_avg $data_file $columns

      columns=ProcessRunQueue,ProcessBlocked
      print_avg $data_file $columns

      columns=Interrupts,ContextSwitches
      print_avg $data_file $columns

      sayatcell '=================================================' 100
      sayatcell "Memory" 100
      sayatcell '=================================================' 100
      columns=MemFree,MemBuff,MemCache
      print_avg $data_file $columns

      sayatcell '=================================================' 100
      sayatcell "Swap" 100
      sayatcell '=================================================' 100
      columns=MemSwpd,SwapReadBlocks,SwapWriteBlocks
      print_avg $data_file $columns

      sayatcell '=================================================' 100
      sayatcell "I/O" 100
      sayatcell '=================================================' 100
      columns=IOReadBlocks,IOWriteBlocks
      print_avg $data_file $columns

      sayatcell '=================================================' 100
      sayatcell "Boot volume space" 100
      sayatcell '=================================================' 100
      columns=capacity
      data_file=/mwlogs/x-ray/$env_code/$component/diag/hosts/$host/os/$date/disk-space-mount1.log
      print_avg $data_file $columns

  done

}


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
    hour_start=0
  fi

  sayatcell '=================================================' 100
  sayatcell "WebLogic domains" 100
  sayatcell '=================================================' 100

  domains=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    
    echo
    sayatcell '=================================================' 100
    sayatcell "$domain" 100
    sayatcell '=================================================' 100

    servers=$(ls /mwlogs/x-ray/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do

      echo
      sayatcell '=================================================' 100
      sayatcell "$domain / $server" 100
      sayatcell '=================================================' 100

      sayatcell '==================' 100
      sayatcell "General" 100
      sayatcell '==================' 100
      data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log

      if [ -f $data_file ]; then

        columns=thread_total,thread_idle,thread_hogging,thread_standby
        print_avg $data_file $columns

        columns=heap_size,heap_free_pct
        print_avg $data_file $columns

        columns=request_pending,request_completed,request_troughput
        print_avg $data_file $columns
    
        columns=request_completed
        print_max $data_file $columns

        columns=sockets_open,sockets_opened
        print_avg $data_file $columns
      else
        echo "      None"
      fi

      sayatcell '==================' 100
      sayatcell "Channels" 100
      sayatcell '==================' 100

      channels=$(
        cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_channel_$domain\_$server\_*   2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_channel_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )
      for channel in $channels; do
        sayatcell '==================' 100
        sayatcell "$channel" 100
        sayatcell '==================' 100

        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 

        if [ -f $data_file ]; then

          columns=accepts,connections
          print_max $data_file $columns

          columns=bytesReceived,byteSent
          print_max $data_file $columns

          columns=msgReceived,msgSent
          print_max $data_file $columns

        else
          echo "      None"
        fi

      done

      sayatcell '==================' 100
      sayatcell "Data sources" 100
      sayatcell '==================' 100

      data_sources=$(
        cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_datasource_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_datasource_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )

      for data_source in $data_sources; do

        sayatcell '==================' 100
        sayatcell "$data_source" 100
        sayatcell '==================' 100

        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_datasource_$domain\_$server\_$data_source.log

        if [ -f $data_file ]; then

          columns=activeConnectionsAverage,capacity,numAvailable
          print_avg $data_file $columns

          columns=waitingForConnectionTotal
          print_max $data_file $columns

        else
          echo "      None"
        fi
      done

      sayatcell '==================' 100
      sayatcell "JMS Server" 100
      sayatcell '==================' 100

      jms_servers=$(
        cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_jmsserver_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_jmsserver_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )

      for jms_server in $jms_servers; do
        sayatcell '==================' 100
        sayatcell "$jms_server" 100
        sayatcell '==================' 100

        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log

        if [ -f $data_file ]; then

          columns=destinations
          print_avg $data_file $columns

          columns=messagesPending,bytesPending
          print_avg $data_file $columns

          columns=messages,bytes
          print_avg $data_file $columns

          columns=messagesReceived,bytesReceived
          print_max $data_file $columns
        else
          echo "      None"
        fi
      done

      sayatcell '==================' 100
      sayatcell "JMS Runtime" 100
      sayatcell '==================' 100

      jms_runtimes=$(
        cd /mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_jmsruntime_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_jmsruntime_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )

      for jms_runtime in $jms_runtimes; do
        sayatcell '==================' 100
        sayatcell "$jms_runtime" 100
        sayatcell '==================' 100

        data_file=/mwlogs/x-ray/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsruntime_$domain\_$server\_$jms_runtime.log

        if [ -f $data_file ]; then

          columns=connections,connectionsHigh
          print_avg $data_file $columns

          columns=connectionsTotal
          print_max $data_file $columns
        else
          echo "      None"
        fi
      done

    done
  done
}



