function ss_host_speed() {
    local host=$1
    local csv=$2
    local sslog=$3

    if [ -z "$sslog" ]; then
        sudo ss -tnoeipm >/tmp/$$.ss.out
        sslog=/tmp/$$.ss.out
    fi

    bps_total=$(echo $(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host | perl -ne '/send (\d*\.*\d*)(\w*)/ && print($1, ".", $2 ,"$3\n")' | 
    sort -n | sed 's/\.Mbps/*1024^2/g' | sed 's/\.Kbps/*1024/g' | tr '\n' '+' | sed 's/+$//') | bc 2>/dev/null)
    Kbps_total=$(echo $bps_total / 1024 | bc 2>/dev/null)
    Mbps_total=$(echo $bps_total / 1024^2 | bc 2>/dev/null)
    tcp_sessions=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host | grep -v '\--' | wc -l | tr -d ' ')
    mss=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host | perl -ne '/mss:(\d*)/ && print($1 ,"\n")' | sort -nr | uniq -c | sort -nr)

    rtt=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host  | perl -ne '/ rtt:(\d+)/ && print(int($1/10)*10 ,"\n")' | sort -nr | uniq -c | sort -nr )
    rmem=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host  | perl -ne '/skmem:\(\w+,rb(\d+)/ && print($1 ,"\n")' | sort -nr | uniq -c | sort -nr)
    wmem=$(cat $sslog | grep -A1 ESTAB | grep -A1 $host | grep -v $host | perl -ne '/skmem:\(\w+,rb\d+,\w+,tb(\d+)/ && print($1 ,"\n")' | sort -nr | uniq -c | sort -nr)

    if [ ! -z "$bps_total" ]; then

        if [ -z "$csv" ]; then
            echo "ss filename:           $(basename $sslog)"
            echo "Measured TCP host(s):  $host"
            echo "Detected TCP sessions: $tcp_sessions"
            echo "Total speed:           $Mbps_total Mbps, $(echo $Mbps_total / 8 | bc) MB/s:, $(echo $Kbps_total / 8 | bc) KB/s:, $(echo $bps_total / 8 | bc) B/s"
            echo "MSS:                   "; echo "$mss"
            echo "RTT:                   "; echo "$rtt"
            echo "read buffer:           "; echo "$rmem"
            echo "write buffer:          "; echo "$wmem"
        else
            echo "$(basename $sslog), $host, $tcp_sessions, $Mbps_total, $Kbps_total, $(echo $mss | tr '\n' ' '), $(echo $rtt | tr '\n' ' '), $(echo $rmem | tr '\n' ' '), $(echo $wmem | tr '\n' ' '"))
        fi
    fi
    rm -f /tmp/$$.ss.out
}


function checkIfspeed_RH7() {
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

function checkIfspeed_RH6() {
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


# while [ 1 ]; do checkIfspeed_RH6 5 eth0; done


