#!/bin/bash


: ${SCRIPT_DEBUG:=0}

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
# data storage
#

declare -A metrics
declare -A variables


#
# compute stats
#

unset get_data_stats
function get_data_stats() {
  local data_file=$1
  local column=$2
  local precision=$3
  local multipliction=$4

  : ${precision:='%d'}
  : ${multipliction:=1}

  if [ ! -f $umcRoot/bin/csv_rewrite ]; then
    echo "Error. umc tool csv_rewrite not found. Initialize umc before running this tool."
  fi

  if [ -f "$data_file" ]; then

    #
    # Problem: too naive logic

    # hour_start_try=$hour_start
    # if [ $hour_start_try -lt 10 ]; then
    #   hour_start_search=0$hour_start_try
    # else 
    #   hour_start_search=$hour_start_try
    # fi
    

    # unset data
    # until [ ! -z "$data" ]; do
    #   >&2 echo "Trying $date_start $hour_start_try..."
    #   data=$(
    #     cat $data_file | 
    #     python3 $umcRoot/bin/csv_rewrite --columns=$column 2> /dev/null | 
    #     sed -n "/$date_start $hour_start_search:/,/$date $hour_stop:/p" | 
    #     cut -d, -f6 | 
    #     grep -v $column
    #   )
    #   hour_start_try=$(($hour_start_try - 1))
    #   if [ $hour_start_try -lt 10 ]; then
    #     if [ $hour_start_try -lt 0 ]; then
    #       >&2 echo "Warning. No data for $date_start! Can't continue. "

    #       data='n/a'
    #       count='n/a'
    #       avg='n/a'
    #       stddev='n/a'
    #       min='n/a'
    #       max='n/a'

    #       return
    #     else
    #       # 01, 03, 03, 04, ..., 09
    #       if [ $hour_start_try -lt 10 ]; then
    #         hour_start_search=0$hour_start_try
    #       else 
    #         hour_start_search=$hour_start_try
    #       fi
    #     fi
    #   fi
    # done

    #
    # Solution: row search based on timestamp

    timestamp_start=$(date -u -d "$date_start $hour_start:00:00" +%s)
    timestamp_stop=$(date -u -d "$date $hour_stop:00:00" +%s)

    data=$(
      cat $data_file | 
      python3 $umcRoot/bin/csv_rewrite --columns=$column 2> /dev/null | 
      awk -F, \
      -v timestamp_start=$timestamp_start \
      -v timestamp_stop=$timestamp_stop  '{
          if ($3 >= timestamp_start && $3 <= timestamp_stop ) {
            print $0
          }
        }'  |
      cut -d, -f6 | 
      grep -v $column
    )

    if [ ! -z "$data" ]; then
      # compute stats
      count=$(echo $data | tr ' ' '\n' | wc -l)
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
    else
      data='n/a'
      count='n/a'
      avg='n/a'
      stddev='n/a'
      min='n/a'
      max='n/a'
    fi
  else
    data='n/a'
    count='n/a'
    avg='n/a'
    stddev='n/a'
    min='n/a'
    max='n/a'
  fi

  # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.count]=$count
  # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.avg]=$avg
  # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.stddev]=$stddev
  # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.min]=$min
  # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.max]=$max

  #echo DEBUG: $env_code.$component.$software_category.$host.$metric_type.$metric_source.$column, $count, $avg, $stddev, $min, $max
  
}

#
# presentation
# 

unset print_header
function print_header() {
  local columns=$1

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

      #echo DEBUG: $var_name, $var_value
    else
      get_data_stats $data_file $column $precision $multipliction
      sayatcell -n "$avg" 30

      # Store values to metrics hashmap
      # $env_code
      # $component
      # $host
      # $software_category=hosts
      # $metric_type=os
      # $metric_source=system-uptime
      # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.count]=$count
      # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.avg]=$avg
      # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.stddev]=$stddev
      # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.min]=$min
      # metrics[$env_code.$component.$software_category.$host.$metric_type.$metric_source.$column.max]=$max

      #echo DEBUG: $env_code.$component.$software_category.$host.$metric_type.$metric_source.$column, $count, $avg, $stddev, $min, $max
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
# dates aggregation
#


function get_date_list() {
  date_start=$1
  date_end=$2

  date_start_timestamp=$(date -d $date_start +%s)
  if [ $? -ne 0 ]; then
    >&2 echo "Error. Date start format not recognized." 
    return 1
  fi

  date_end_timestamp=$(date -d $date_end +%s)
  if [ $? -ne 0 ]; then
    >&2 echo "Error. Date end format not recognized." 
    return 1
  fi
  
  if [ "$date_start_timestamp" -gt "$date_end_timestamp" ]; then
      date_start_arg=$date_start
      date_start=$date_end
      date_end=$date_start_arg
  fi  

  unset date_list

  mid_date=$date_start
  until [ "$mid_date" == "$date_end" ]; do
    date_list="$date_list $mid_date"
    mid_date=$(date -d "$mid_date +24 hours" -I)
  done
  date_list="$date_list $date_end"
  echo $date_list
}


function get_data_files() {
  base_dir=$1
  data_filename=$2
  date_start=$3
  date_end=$4

  dates=$(get_date_list $date_start $date_end)

  for date in $dates; do

    if [ -f $base_dir/$date/$data_filename ]; then
      echo $base_dir/$date/$data_filename
    else
      : #>&2 echo "Warning. File not found: $base_dir/$date/$data_filename"
    fi
  done
}


#
# reports
#

unset build_data_file_os
function build_data_file_os() {
  data_dir=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type
  src_file=$metric_source.log
  
  #
  # one day report
  #
  #data_file=$data_dir/$date/$src_file

  #
  # multiple days
  #
  data_file=$xray_reports_tmp/$src_file
  rm -f $data_file
  rm -f $data_file.tmp
  for file in $(get_data_files $data_dir $src_file $date_start $date);do
    cat $file >> $data_file.tmp
    echo >> $data_file.tmp
  done

  if [ -f $data_file.tmp ]; then
    #
    # remove malformed lines
    #
    # Note: csv_rewrite puts header in first row, even if is later in the file 
    columns_cnt=$(cat $data_file.tmp | $umcRoot/bin/csv_rewrite | head -1 | awk -F, '{print NF}')
    cat $data_file.tmp | awk -F, -v columns_cnt=$columns_cnt  '{ if (NF == columns_cnt) {print $0} else { print "Ignoring malformed line:"$0 > "/dev/stderr"} }' > $data_file
    rm -f $data_file.tmp
  fi
}

unset report_OCI_instances
function report_OCI_instances() {
  env_code=$1
  component=$2
  get_last_hours=$3

  : ${xray_root:=/mwlogs/x-ray}

  date=$(date -u -I)
  hour_stop=$(date -u "+%H")
  hour_start=$(date -u -d "$get_last_hours hours ago" "+%H")
  date_start=$(date -u -d "$get_last_hours hours ago" -I)

  # if [ $date_start != $date ]; then
  #   echo "Report will be computed from $date 00:00:00"
  #   hour_start=00
  # fi

  # create tmp directory
  xray_reports_tmp=~/tmp/x-ray_reports
  mkdir -p $xray_reports_tmp

  # 
  software_category=hosts
  metric_type=os

  header1 "Compute instances" 
  echo "Time window from $date_start $hour_start:00:00 UTC to $date $hour_stop:00:00 UTC"

  hosts=$(ls $xray_root/$env_code/$component/diag/hosts)

  header2 "Load average"
  metric_source=system-uptime

  columns=_host,load1min,load5min,load15min
  echo; print_header $columns
  for host in $hosts; do
      build_data_file_os
      print_current_data $data_file $columns %0.2f
  done

  echo
  header2 "CPU"
  metric_source=system-vmstat
  columns=_host,CPUuser,CPUsystem,CPUidle,CPUwaitIO,CPUVMStolenTime
  echo; print_header $columns
  for host in $hosts; do
      #data_file=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type/$date/$metric_source.log
      build_data_file_os
      print_current_data $data_file $columns
  done
      
  columns=_host,ProcessRunQueue,ProcessBlocked
  echo; print_header $columns
  for host in $hosts; do
      #data_file=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type/$date/$metric_source.log
      build_data_file_os
      print_current_data $data_file $columns
  done

  columns=_host,Interrupts,ContextSwitches
  echo; print_header $columns
  for host in $hosts; do
      #data_file=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type/$date/$metric_source.log
      build_data_file_os
      print_current_data $data_file $columns
  done

  echo
  header2 "Memory"
      
  columns=_host,MemFree,MemBuff,MemCache
  echo; print_header $columns
  for host in $hosts; do
      #data_file=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type/$date/$metric_source.log
      build_data_file_os
      print_current_data $data_file $columns
  done

  echo
  header2 "Swap"
  columns=_host,MemSwpd,SwapReadBlocks,SwapWriteBlocks
  echo; print_header $columns
  for host in $hosts; do
      #data_file=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type/$date/$metric_source.log
      build_data_file_os
      print_current_data $data_file $columns
  done

  echo
  header2 "I/O"
  columns=_host,IOReadBlocks,IOWriteBlocks
  echo; print_header $columns
  for host in $hosts; do
      #data_file=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type/$date/$metric_source.log
      build_data_file_os
      print_current_data $data_file $columns
  done

  echo
  header2 "Boot volume space" 

  metric_source=disk-space-mount1
  columns=_host,capacity
  echo; print_header $columns
  for host in $hosts; do
      #data_file=$xray_root/$env_code/$component/diag/$software_category/$host/$metric_type/$date/$metric_source.log
      build_data_file_os
      print_current_data $data_file $columns
  done

  # delete tmp dir
  rm -fr $xray_reports_tmp
}

unset build_data_file_wls
function build_data_file_wls() {
  data_dir=$xray_root/$env_code/$component/diag/wls/dms/$domain
  src_file=$metric_source.log
  data_file=$xray_reports_tmp/$src_file
  rm -f $data_file.tmp
  for file in $(get_data_files $data_dir $src_file $date_start $date); do
    cat $file >> $data_file.tmp
    echo >> $data_file.tmp
  done

  #
  # remove malformed lines
  #
  # Note: csv_rewrite puts header in first row, even if is later in the file 
  columns_cnt=$(cat $data_file.tmp | $umcRoot/bin/csv_rewrite | head -1 | awk -F, '{print NF}')
  # Hack: NF == (columns_cnt+1)  because of possble value in column http,Default[http]
  cat $data_file.tmp | awk -F, -v columns_cnt=$columns_cnt  '{ if (NF == columns_cnt || NF == (columns_cnt+1) ) {print $0} else { print "Ignoring malformed line:"$0 > "/dev/stderr"} }' > $data_file
  rm -f $data_file.tmp

}

unset report_WLS
function report_WLS() {
  env_code=$1
  component=$2
  get_last_hours=$3

  : ${xray_root:=/mwlogs/x-ray}
  
  date=$(date -u -I)
  hour_stop=$(date -u "+%H")
  hour_start=$(date -u -d "$get_last_hours hours ago" "+%H")

  date_start=$(date -u -d "$get_last_hours hours ago" -I)
  # if [ $date_start != $date ]; then
  #   echo "Report will be computed fromm $date 00:00:00"
  #   hour_start=00
  # fi

  # create tmp directory
  xray_reports_tmp=~/tmp/x-ray_reports
  mkdir -p $xray_reports_tmp

  #
  header1 "WebLogic domains"
  echo "Time window from $date_start $hour_start:00:00 UTC to $date $hour_stop:00:00 UTC"

  echo
  header2 "General"

  columns=_domain,_server,thread_total,thread_idle,thread_hogging,thread_standby
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      metric_source=wls_general_$domain\_$server
      build_data_file_wls
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,heap_size,heap_free_pct
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      metric_source=wls_general_$domain\_$server
      build_data_file_wls
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,request_pending,request_troughput
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      metric_source=wls_general_$domain\_$server
      build_data_file_wls
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,request_completed
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      metric_source=wls_general_$domain\_$server
      build_data_file_wls
      if [ -f $data_file ]; then
        print_counter_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done

  columns=_domain,_server,sockets_open,sockets_opened
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_general_$domain\_$server.log
      metric_source=wls_general_$domain\_$server
      build_data_file_wls
      if [ -f $data_file ]; then
        print_current_data $data_file $columns
      else
        : # echo "(none)"
      fi
    done
  done



  echo
  header2 'Channels'
  
  columns=_domain,_server,_channel,accepts
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    for server in $servers; do

      channels=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_channel_$domain\_$server\_*   2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_channel_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )

      for channel in $channels; do

        servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)

          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 
          metric_source=wls_channel_$domain\_$server\_$channel
          build_data_file_wls

          if [ -f $data_file ]; then
            print_current_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done

  columns=_domain,_server,_channel,connections
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    for server in $servers; do

      channels=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_channel_$domain\_$server\_*   2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_channel_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )

      for channel in $channels; do

        servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)

          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 
          metric_source=wls_channel_$domain\_$server\_$channel
          build_data_file_wls
          if [ -f $data_file ]; then
            print_counter_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done

  columns=_domain,_server,_channel,bytesReceived,byteSent
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    for server in $servers; do

      channels=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_channel_$domain\_$server\_*   2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_channel_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )

      for channel in $channels; do

        servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)

          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log
          metric_source=wls_channel_$domain\_$server\_$channel
          build_data_file_wls
          if [ -f $data_file ]; then
            print_current_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done

  columns=_domain,_server,_channel,msgReceived,msgSent
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    for server in $servers; do

      channels=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_channel_$domain\_$server\_*   2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_channel_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )

      for channel in $channels; do

        servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)

          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_channel_$domain\_$server\_$channel.log 
          metric_source=wls_channel_$domain\_$server\_$channel
          build_data_file_wls
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

  columns=_domain,_server,_data_source,activeConnectionsAverage,capacity,numAvailable
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      data_sources=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_datasource_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_datasource_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )
      for data_source in $data_sources; do
          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_datasource_$domain\_$server\_$data_source.log
          metric_source=wls_datasource_$domain\_$server\_$data_source
          build_data_file_wls
          if [ -f $data_file ]; then
            print_current_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done

  columns=_domain,_server,_data_source,waitingForConnectionTotal
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do
      data_sources=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_datasource_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_datasource_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )
      for data_source in $data_sources; do
          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_datasource_$domain\_$server\_$data_source.log
          metric_source=wls_datasource_$domain\_$server\_$data_source
          build_data_file_wls
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
  

  columns=_domain,_server,_jms_server,destinations
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do

      jms_servers=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_jmsserver_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_jmsserver_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )
      for jms_server in $jms_servers; do
          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
          metric_source=wls_jmsserver_$domain\_$server\_$jms_server
          build_data_file_wls
          if [ -f $data_file ]; then
            print_current_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done

  columns=_domain,_server,_jms_server,messagesPending,bytesPending
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do

      jms_servers=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_jmsserver_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_jmsserver_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )
      for jms_server in $jms_servers; do
          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
          metric_source=wls_jmsserver_$domain\_$server\_$jms_server
          build_data_file_wls
          if [ -f $data_file ]; then
            print_current_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done

  columns=_domain,_server,_jms_server,messages,bytes
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do
    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do

      jms_servers=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_jmsserver_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_jmsserver_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )
      for jms_server in $jms_servers; do
          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
          metric_source=wls_jmsserver_$domain\_$server\_$jms_server
          build_data_file_wls
          if [ -f $data_file ]; then
            print_current_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done

  columns=_domain,_server,_jms_server,messagesReceived,bytesReceived
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

    servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
    for server in $servers; do

      jms_servers=$(
        cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
        ls wls_jmsserver_$domain\_$server\_* 2>/dev/null | 
        grep -v _dt.log | 
        sed "s/wls_jmsserver_$domain\_$server\_//g" | 
        sed "s/\.log//g"
        cd - >/dev/null
      )
      for jms_server in $jms_servers; do
          #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsserver_$domain\_$server\_$jms_server.log
          metric_source=wls_jmsserver_$domain\_$server\_$jms_server
          build_data_file_wls
          if [ -f $data_file ]; then
            print_current_data $data_file $columns
          else
            : # echo "(none)"
          fi
        done
    done
  done


  echo
  header2 "JMS Runtime"
  
  columns=_domain,_server,_jms_runtime,connections
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

      servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do

        jms_runtimes=$(
          cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
          ls wls_jmsruntime_$domain\_$server\_* 2>/dev/null | 
          grep -v _dt.log | 
          sed "s/wls_jmsruntime_$domain\_$server\_//g" | 
          sed "s/\.log//g"
          cd - >/dev/null
        )

        for jms_runtime in $jms_runtimes; do

            #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsruntime_$domain\_$server\_$jms_runtime.log
            metric_source=wls_jmsruntime_$domain\_$server\_$jms_runtime
            build_data_file_wls
            if [ -f $data_file ]; then
              print_current_data $data_file $columns
            else
              : # echo "(none)"
            fi
          done
    done
  done

  columns=_domain,_server,_jms_runtime,connectionsHigh
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

      servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do

        jms_runtimes=$(
          cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
          ls wls_jmsruntime_$domain\_$server\_* 2>/dev/null | 
          grep -v _dt.log | 
          sed "s/wls_jmsruntime_$domain\_$server\_//g" | 
          sed "s/\.log//g"
          cd - >/dev/null
        )

        for jms_runtime in $jms_runtimes; do

            #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsruntime_$domain\_$server\_$jms_runtime.log
            metric_source=wls_jmsruntime_$domain\_$server\_$jms_runtime
            build_data_file_wls
            if [ -f $data_file ]; then
              print_ceiling_data $data_file $columns
            else
              : # echo "(none)"
            fi
          done
    done
  done

  columns=_domain,_server,_jms_runtime,connectionsTotal
  echo; print_header $columns
  domains=$(ls $xray_root/$env_code/$component/diag/wls/dms)
  for domain in $domains; do

      servers=$(ls $xray_root/$env_code/$component/diag/wls/log/$domain)
      for server in $servers; do

        jms_runtimes=$(
          cd $xray_root/$env_code/$component/diag/wls/dms/$domain/$date
          ls wls_jmsruntime_$domain\_$server\_* 2>/dev/null | 
          grep -v _dt.log | 
          sed "s/wls_jmsruntime_$domain\_$server\_//g" | 
          sed "s/\.log//g"
          cd - >/dev/null
        )

        for jms_runtime in $jms_runtimes; do

            #data_file=$xray_root/$env_code/$component/diag/wls/dms/$domain/$date/wls_jmsruntime_$domain\_$server\_$jms_runtime.log
            metric_source=wls_jmsruntime_$domain\_$server\_$jms_runtime
            build_data_file_wls
            if [ -f $data_file ]; then
              print_counter_data $data_file $columns
            else
              : # echo "(none)"
            fi
          done
    done
  done

  #cleanup on exit
  rm -fr $xray_reports_tmp
}

#
# script processing
# 

function process_control_line() {
  local left=$1
  local operation=$2
  local right=$3


  # check left - metric or variable
  re_var='^var\.'
  if [[ $left =~ $re_var ]]; then
    left_src=variable
    left_value=$left
  else
    left_src=metric
    left_value=$left
  fi

  # is it number or need to get value?
  re_int='^[0-9]+$'
  if [[ $right =~ $re_int ]]; then
    right_src=int
    right_value=$right
  else
    if [[ $right =~ $re_var ]]; then
      right_src=variable
      right_value=${variables[$right]}
    else
      right_src=metric
      right_value=${metrics[$right]}
    fi
  fi

  if [ -z "$right_value" ]; then
      echo "Error. Right value is null." >&2
      return 12
  fi

  result=1
  if [ $left_src == variable ]; then
      case $operation in
      '=')
        if [ $left_src != variable ]; then
          echo "Error. Value assigment only possible to varaible. Left side type: $left_src" >&2
          return 11
        else

          case $right_src in
          int)
            variables[$left_value]=$right_value
            ;;
          metric)
            variables[$left_value]=$right_value
            ;;
          variable)
            variables[$left_value]=$right_value
            ;;
          *)
            echo "Error. Unknown right variable type" >&2
            return 10
            ;;
          esac

        fi
        ;;
      esac

  elif [ $left_src == metric ]; then
    # is it single or group metric name? 
    check_metrics=$(echo "${!metrics[@]}" | tr ' ' '\n'  | grep -Ei $left)
    for check_metric in $check_metrics; do
      # echo "Checking $check_metric..."

      case $operation in

      lt)
        if [ ${metrics[$check_metric]} -lt $right_value ]; then
          case $right_src in
          int)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} < $right_value." >&2
            result=0
            ;;
          metric)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} < $right having $right_value." >&2
            result=0
            ;;
          variable)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} < $right having $right_value." >&2
            result=0
            ;;
          *)
            echo "Error. Unknown right variable type" >&2
            result=10
            ;;
          esac
        fi
        ;;
      gt)
        if [ ${metrics[$check_metric]} -gt $right_value ]; then
          case $right_src in
          int)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} > $right_value." >&2
            result=0
            ;;
          metric)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} > $right having $right_value." >&2
            result=0
            ;;
          variable)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} > $right having $right_value." >&2
            result=0
            ;;
          *)
            echo "Error. Unknown right variable type" >&2
            result=10
            ;;
          esac
        fi
        ;;
      '==')
        if [ ${metrics[$check_metric]} -eq $right_value ]; then
          case $right_src in
          int)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} == $right_value." >&2
            result=0
            ;;
          metric)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} == $right having $right_value." >&2
            result=0
            ;;
          variable)
            [ $SCRIPT_DEBUG -eq 1 ] && echo "$check_metric with value ${metrics[$check_metric]} == $right having $right_value." >&2
            result=0
            ;;
          *)
            echo "Error. Unknown right variable type" >&2
            result=10
            ;;
          esac
        fi
        ;;
      *)
        echo "Error. Unknown operator"
        result=13
        ;;
      esac
    done
    return $result
  else
    echo "Error. Left side type unknown. Type: $left_src" >&2
    return 14
  fi
}

function check() {
  when=$1; shift
  process_control_line $@
}

function define() {
  process_control_line $@
}

function dump() {
  what=$1

  case $what in
  variables)
    for var in echo ${!variables[@]}; do
      echo $var = ${variables[$var]}
    done
    ;;
  metrics)
    for metric in echo ${!metrics[@]}; do
      echo $metric = ${metrics[$metric]}
    done
    ;;
  *)
    echo "Error. Unknown type. Available: variables, metrics." >&2
    ;;
  esac
}

function get() {
  what=$1; shift
  left=$1

  # check left - metric or variable
  re_var='^var\.'
  if [[ $left =~ $re_var ]]; then
    left_src=variable
    left_value=$left
  else
    left_src=metric
    left_value=$left
  fi

  case $what in
  value)
    case $left_src in
    metric)
      check_metrics=$(echo "${!metrics[@]}" | tr ' ' '\n'  | grep -Ei $left)
      for check_metric in $check_metrics; do
        echo ${metrics[$check_metric]}
      done
      ;;
    variable)
      check_variables=$(echo "${!variables[@]}" | tr ' ' '\n'  | grep -Ei $left)
      for check_variable in $check_variables; do
        echo ${variables[$check_metric]}
      done
      ;;
    esac
    ;;
  name)
    echo "${!metrics[@]}" | tr ' ' '\n'  | grep -Ei $left
    ;;
  type)
    echo $left_src
    ;;
  *)
    echo "Error. Unknown operation."
    ;;
  esac
}