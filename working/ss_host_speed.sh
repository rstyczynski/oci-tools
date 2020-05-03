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


function checkIfspeed_RH6() {
    delay=$1
    ifname=$2

    if [ -z "$delay" ]; then
        delay=1
    fi

    start_TX=$(ifconfig $ifname | grep TX | grep bytes | tr -s ' ' | cut -d' ' -f6 )
    start_RX=$(ifconfig $ifname | grep RX | grep bytes | tr -s ' ' | cut -d' ' -f6 )

    sleep $delay

    stop_TX=$(ifconfig $ifname | grep TX | grep bytes | tr -s ' ' | cut -d' ' -f6)
    stop_RX=$(ifconfig $ifname | grep RX | grep bytes | tr -s ' ' | cut -d' ' -f6)
    echo -n "TX speed [kB/s]:"
    echo -n "$(echo "($stop_TX - $start_TX)/$delay/1024" | bc), "
    echo -n "RX speed [kB/s]:"
    echo "$(echo "($stop_RX - $start_RX)/$delay/1024" | bc)"
}

function checkIfspeed_RH7() {
    delay=$1
    ifname=$2

    if [ -z "$delay" ]; then
        delay=1
    fi

    start_TX=$(ifconfig $ifname | grep TX | grep bytes | tr -s ' ' | cut -d' ' -f7 | cut -d: -f2)
    start_RX=$(ifconfig $ifname | grep RX | grep bytes | tr -s ' ' | cut -d' ' -f3 | cut -d: -f2)

    sleep $delay

    stop_TX=$(ifconfig $ifname | grep TX | grep bytes | tr -s ' ' | cut -d' ' -f7 | cut -d: -f2)
    stop_RX=$(ifconfig $ifname | grep RX | grep bytes | tr -s ' ' | cut -d' ' -f3 | cut -d: -f2)
    echo -n "TX speed [kB/s]:"
    echo -n "$(echo "($stop_TX - $start_TX)/$delay/1024" | bc), "
    echo -n "RX speed [kB/s]:"
    echo "$(echo "($stop_RX - $start_RX)/$delay/1024" | bc)"
}


