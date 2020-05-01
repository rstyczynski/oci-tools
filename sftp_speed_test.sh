#!/bin/bash

#
# requires
#
# sudo yum install -y expect

#
# functions
#

function get_set_cfg() {
    var_name=$1
    cfg_file=$2

    if [ ! -f $cfg_file ]; then touch $cfg_file; fi

    read $var_name <<<$(cat $cfg_file | grep $var_name | cut -f2 -d=)

    if [ -z "$(eval echo \$$var_name)" ]; then
        if [ "$var_name" == sftp_password ]; then
            read -s -p "$var_name:" $var_name
            echo
        else
            read -p "$var_name:" $var_name
        fi
        sed -i "/^$var_name/d" $cfg_file
        echo "$var_name=$(eval echo \$$var_name)" >>$cfg_file
    fi
}

function checkIfspeed() {
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

function run_with_ifspeed_start() {
    start_log=$(cat $sftp_test_home/$test_date/ifspeed_$seed.log | tail -1 | cut -f1,2 -d' ')
}
function run_with_ifspeed_stop() {
    sleep 1
    stop_log=$(cat $sftp_test_home/$test_date/ifspeed_$seed.log | tail -1 | cut -f1,2 -d' ')
    cat $sftp_test_home/$test_date/ifspeed_$seed.log | sed -n "/^$start_log/,/^$stop_log/p" >$sftp_test_home/$test_date/$test_file\_$test_name.ifspeed

    upload_max=$(cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed | cut -d: -f4 | cut -f1 -d, | awk '$1>max{max=$1}END{print max}')
    upload_std=$(cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed | cut -d: -f4 | cut -f1 -d, | awk '{delta=$1; avg+=$1/NR;} END {print sqrt(((delta-avg)^2)/NR);}')
    upload_avg=$(cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed | cut -d: -f4 | cut -f1 -d, | awk '{ total += $1; count++ } END { print total/count }')

    download_max=$(cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed | cut -d: -f5 | awk '$1>max{max=$1}END{print max}')
    download_std=$(cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed | cut -d: -f5 | awk '{delta=$1; avg+=$1/NR;} END {print sqrt(((delta-avg)^2)/NR);}')
    download_avg=$(cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed | cut -d: -f5 | awk '{ total += $1; count++ } END { print total/count }')

    rm -rf $sftp_test_home/$test_date/$test_file\_$test_name.stats
    echo "Put (max/stddev/avg) [kB]: $upload_max / $upload_std / $upload_avg" >>$sftp_test_home/$test_date/$test_file\_$test_name.stats
    echo "Get (max/stddev/avg) [kB]: $download_max / $download_std / $download_avg" >>$sftp_test_home/$test_date/$test_file\_$test_name.stats
    echo >>$sftp_test_home/$test_date/$test_file\_$test_name.stats

}

function run_with_ifspeed() {
    run_me=$1

    run_with_ifspeed_start
    $run_me
    run_with_ifspeed_stop
}

#
# TEST SECTION
#

function run_tests() {

    #
    test_name=download_internet
    #
    echo "========================"
    echo "=== $test_name "
    echo "========================"

    if [ -f $sftp_test_home/$test_file ]; then
        rm -f $sftp_test_home/$test_file
    fi
    cd $sftp_test_home
    run_with_ifspeed "timeout $network_time_limit wget http://ipv4.download.thinkbroadband.com/$test_file" >$sftp_test_home/$test_date/$test_file\_$test_name.wget 2>&1
    cd - >/dev/null

    echo
    echo "=== wget client session "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.wget
    echo
    echo "=== if speed "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed
    echo
    echo "=== if speed stats "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.stats

    sleep 5

    #
    test_name=upload
    #
    cat >$sftp_test_home/$test_date/sftp-test-put.exp <<EOF
set timeout 600
log_file $sftp_test_home/$test_date/$test_file\_$test_name.expect

spawn sftp -oPort=$sftp_port  $sftp_user@$sftp_server
expect "$sftp_user@$sftp_server's password:"
send "$sftp_password\n"
expect "sftp>"
send "put $sftp_test_home/$test_file $test_path/$test_file\n"
expect "sftp>"
send quit
EOF

    echo "========================"
    echo "=== $test_name "
    echo "========================"
    run_with_ifspeed "timeout $network_time_limit expect $sftp_test_home/$test_date/sftp-test-put.exp" 1>&2

    echo
    echo "=== sftp client session "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.expect | grep -v $sftp_password | grep ETA | sed 's/\r//g' | tr -s ' ' | sed 's/ETA/ETA\n/g'
    echo
    echo "=== if speed "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed
    echo
    echo "=== if speed stats "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.stats

    echo

    #
    test_name=download
    #
    cat >$sftp_test_home/$test_date/sftp-test-get.exp <<EOF
#!/usr/bin/expect
set timeout 60
log_file $sftp_test_home/$test_date/$test_file\_$test_name.expect

spawn sftp -oPort=$sftp_port $sftp_user@$sftp_server
expect "$sftp_user@$sftp_server's password:"
send "$sftp_password\n"
expect "sftp>"
send "get $test_path/$test_file /dev/null\n"
expect "sftp>"
send quit
EOF

    echo "========================"
    echo "=== $test_name "
    echo "========================"

    run_with_ifspeed "timeout $network_time_limit expect $sftp_test_home/$test_date/sftp-test-get.exp" 1>&2

    echo
    echo "=== sftp client session "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.expect | grep -v $sftp_password | grep ETA | sed 's/\r//g' | tr -s ' ' | sed 's/ETA/ETA\n/g'
    echo
    echo "=== if speed "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed
    echo
    echo "=== if speed stats "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.stats

    echo

    #
    test_name=download_tuned
    #
    cat >$sftp_test_home/$test_date/sftp-test-get-tuned.exp <<EOF
#!/usr/bin/expect
set timeout 60
log_file $sftp_test_home/$test_date/$test_file\_$test_name.expect

spawn sftp $sftp_tunings -oPort=$sftp_port $sftp_user@$sftp_server
expect "$sftp_user@$sftp_server's password:"
send "$sftp_password\n"
expect "sftp>"
send "get $test_path/$test_file /dev/null\n"
expect "sftp>"
send quit
EOF

    echo "========================"
    echo "=== $test_name "
    echo "========================"

    run_with_ifspeed "timeout $network_time_limit expect $sftp_test_home/$test_date/sftp-test-get-tuned.exp" 1>&2

    echo
    echo "=== sftp client session "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.expect | grep -v $sftp_password | grep ETA | sed 's/\r//g' | tr -s ' ' | sed 's/ETA/ETA\n/g'
    echo
    echo "=== if speed "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed
    echo
    echo "=== if speed stats "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.stats

    echo

    #
    test_name=download_x10
    #

    cat >$sftp_test_home/$test_date/sftp-test-get_nolog.exp <<EOF
#!/usr/bin/expect
set timeout 60

spawn sftp -oPort=$sftp_port $sftp_user@$sftp_server
expect "$sftp_user@$sftp_server's password:"
send "$sftp_password\n"
expect "sftp>"
send "get $test_path/$test_file /dev/null\n"
expect "sftp>"
send quit
EOF

    echo "========================"
    echo "=== $test_name "
    echo "========================"
    run_with_ifspeed_start
    unset pid_list
    for cnt in {1..3}; do
        timeout $network_time_limit expect $sftp_test_home/$test_date/sftp-test-get_nolog.exp 1>&2 &
        expect_pid=$!
        pid_list="$pid_list $expect_pid"
    done
    wait $pid_list
    unset pid_list

    run_with_ifspeed_stop
    echo
    echo "=== if speed "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed
    echo
    echo "=== if speed stats "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.stats

    #
    test_name=download_x20
    #

    echo "========================"
    echo "=== $test_name "
    echo "========================"
    run_with_ifspeed_start
    unset pid_list
    for cnt in {1..20}; do
        timeout $network_time_limit expect $sftp_test_home/$test_date/sftp-test-get_nolog.exp 1>&2 &
        expect_pid=$!
        pid_list="$pid_list $expect_pid"
    done
    wait $pid_list
    unset pid_list

    run_with_ifspeed_stop
    echo
    echo "=== if speed "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed
    echo
    echo "=== if speed stats "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.stats

    #
    test_name=download_x40
    #

    echo "========================"
    echo "=== $test_name "
    echo "========================"
    run_with_ifspeed_start
    unset pid_list
    for cnt in {1..40}; do
        timeout $network_time_limit expect $sftp_test_home/$test_date/sftp-test-get_nolog.exp 1>&2 &
        expect_pid=$!
        pid_list="$pid_list $expect_pid"
    done
    wait $pid_list
    unset pid_list

    run_with_ifspeed_stop
    echo
    echo "=== if speed "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.ifspeed
    echo
    echo "=== if speed stats "
    cat $sftp_test_home/$test_date/$test_file\_$test_name.stats

}

#
# START SECTION
#

function stop_test_sctivities() {

    # stop workers
    if [ ! -z "$pid_list" ]; then
        kill $pid_list
    fi

    # stop ifspeed
    kill $ifspeed_pid

    echo "Deamon logger, worker stopped." 1>&2
}

function build_short_report() {

    __main_header__ > $sftp_test_home/sftp_test_$test_date.report
    __main_params__ >> $sftp_test_home/sftp_test_$test_date.report

    echo >> $sftp_test_home/sftp_test_$test_date.report

    for stats_path in $(ls -rt $sftp_test_home/$test_date/*.stats); do
        stats_file=$(basename $stats_path)

        echo "=======================================" >> $sftp_test_home/sftp_test_$test_date.report
        echo "=== $stats_file " >> $sftp_test_home/sftp_test_$test_date.report
        echo "=======================================" >> $sftp_test_home/sftp_test_$test_date.report
        cat $stats_path >> $sftp_test_home/sftp_test_$test_date.report
    done

    echo End. >> $sftp_test_home/sftp_test_$test_date.report

}


function __main_header__() {

    echo "======================================="
    echo "========= SFTP test procedure ========="
    echo "======================================="
    echo "== host: $(hostname)"
    echo "== sftp_user: $(whoami)"
    echo "== date: $(date)"
    echo "======================================="

}

function __main_params__() {

    echo "======================================="
    echo "== sftp_server: $sftp_server"
    echo "== sftp_port: $sftp_port"
    echo "== sftp_tunings: $sftp_tunings"
    echo "======================================="
    echo "== sftp_user: $sftp_user"
    echo "== sftp_password: [$(echo $sftp_password | wc -c)]"
    echo "== test_path: $test_path"
    echo "== test_file: $test_file"
    echo "======================================="
    echo "== sftp_test_home: $(
        cd $sftp_test_home
        pwd
    )"
    echo "== network operations timeout: $network_time_limit"
    echo "======================================="
    echo "== ifname: $ifname"
    echo "======================================="
    echo "======================================="
    echo "======================================="
}

function __main__() {
    donot_ask=$1

    __main_header__

    mkdir -p ~/.sftp_test
    chmod 700 ~/.sftp_test

    get_set_cfg sftp_server ~/.sftp_test/config.ini
    get_set_cfg sftp_port ~/.sftp_test/config.ini
    get_set_cfg sftp_tunings ~/.sftp_test/config.ini
    get_set_cfg sftp_user ~/.sftp_test/config.ini
    get_set_cfg sftp_password ~/.sftp_test/config.ini
    get_set_cfg test_path ~/.sftp_test/config.ini
    get_set_cfg test_file ~/.sftp_test/config.ini
    get_set_cfg sftp_test_home ~/.sftp_test/config.ini
    get_set_cfg ifname ~/.sftp_test/config.ini
    get_set_cfg network_time_limit ~/.sftp_test/config.ini

    err_msg=''
    test -z "$sftp_server" && err_msg="$err_msg >>sftp_server must be set."
    test -z "$sftp_port" && err_msg="$err_msg >>sftp_port must be set."
    test -z "$sftp_user" && err_msg="$err_msg >>sftp_user must be set."
    test -z "$sftp_password" && err_msg="$err_msg >>sftp_password must be set."
    test -z "$test_path" && err_msg="$err_msg >>test_path must be set."
    test -z "$test_file" && err_msg="$err_msg >>test_file must be set."
    test -z "$sftp_test_home" && err_msg="$err_msg >>sftp_test_home must be set."
    test -z "$ifname" && err_msg="$err_msg >>ifname must be set."

    test -z "$network_time_limit" && network_time_limit=60

    if [ ! -z "$err_msg" ]; then
        echo "Not all required varaibles set. Error list: ($err_msg)"
        echo "Done with error"
        return 1
    else
        mkdir -p $sftp_test_home

        __main_params__

        if [ "$donot_ask" = auto ]; then
            run_tests_confirm=Y
        else
            unset run_tests_confirm
            read -p 'Proceed with test? [Y/n]' run_tests_confirm
        fi

        if [ "$run_tests_confirm" == Y ]; then

            #
            # INIT SECTION
            #
            mkdir -p $sftp_test_home/$test_date

            # init measure if speed
            seed=$RANDOM\_$$
            while [ 1 ]; do
                checkIfspeed 1 $ifname | sed "s/^/$(uname -n) $(date +%T) /g" >>$sftp_test_home/$test_date/ifspeed_$seed.log
            done &
            ifspeed_pid=$!

            # set trap for ctl-c /to stop measure if speed/
            trap stop_test_sctivities INT

            # run al tests
            run_tests
            stop_test_sctivities

            #prepre report
            build_short_report

            mv /tmp/$$.sftp_test_$test_date.report $sftp_test_home/$test_date/sftp_test_$test_date.log

            echo "Done." 1>&2
            echo 1>&2
            echo "Test report:" 1>&2
            cat $sftp_test_home/sftp_test_$test_date.report 1>&2

            echo "Test results in:" 1>&2
            echo " >> report: $sftp_test_home/sftp_test_$test_date.report" 1>&2
            echo " >> log: $sftp_test_home/$test_date/sftp_test_$test_date.log" 1>&2
            echo " >> partial results in directory: $sftp_test_home/$test_date." 1>&2

        else
            echo "Abandoned." 1>&2
        fi
    fi
}

test_date=$(date +%Y-%m-%d_%T)
__main__ $@ | tee /tmp/$$.sftp_test_$test_date.report
