function ss_host_speed() {
    host=$1
    sslog=$2
    csv=$3

    if [ -z "$sslog" ]; then
        sudo ss -tnoeip >/tmp/$$.ss.out
        sslog=/tmp/$$.ss.out
    fi

    bps_total=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host | perl -ne '/send (\d*\.*\d*)(\w*)/ && print($1, ".", $2 ,"$3\n")' | sort -n | sed 's/\.Mbps/*1024^2/g' | sed 's/\.Kbps/*1024/g' | tr '\n' '+' | sed 's/+$//' | bc 2>/dev/null)
    Kbps_total=$(echo $bps_total / 1024 | bc 2>/dev/null)
    Mbps_total=$(echo $bps_total / 1024^2 | bc 2>/dev/null)
    tcp_sessions=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host | grep -v '\--' | wc -l | tr -d ' ')
    mss=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host | perl -ne '/mss:(\d*)/ && print($1 ,"\n")' | sort -u)

    if [ ! -z "$bps_total" ]; then

        if [ -z "$csv" ]; then
            echo "ss filename:           $(basename $sslog)"
            echo "Measured TCP host(s):  $host"
            echo "Detected TCP sessions: $tcp_sessions"
            echo "MSS:                   $mss"
            echo "Mbps:                  $Mbps_total, MB/s: $(echo $Mbps_total / 8 | bc)"
            echo "Kbps:                  $Kbps_total, KB/s: $(echo $Kbps_total / 8 | bc)"
            echo "bps:                   $bps_total, B/s:   $(echo $bps_total / 8 | bc)"
        else
            echo "$(basename $sslog), $host, $tcp_sessions, $Mbps_total, $Kbps_total, $(echo $mss | tr '\n' ' ')"
        fi
    fi
    rm -f /tmp/$$.ss.out
}
