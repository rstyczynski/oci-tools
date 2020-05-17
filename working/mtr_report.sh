

mtr_log=mtr_CPE_stat.log

# 2020-05-12_06:37:34;;1.;140.91.200.7;0.0%;300;0.2;0.2;0.2;1.5;0.1
# 2020-05-12_06:37:34;;2.;168.187.252.130;36.3%;300;135.1;134.9;134.5;136.1;0.2
# 2020-05-12_06:37:34;;3.;192.0.25.10;0.3%;300;137.5;140.5;137.0;183.4;7.8
# 2020-05-12_06:37:34;;4.;10.34.1.2;0.3%;300;137.2;141.5;136.8;192.0;9.2
# 2020-05-12_06:37:34;;5.;172.16.98.153;0.3%;300;135.1;135.1;134.6;138.3;0.3
cat $mtr_log | tr -s ' ' | tr ' ' ';' | grep -v HOST >/tmp/$$.mtr_all.csv

# cut dates
start_ts=2020-05-11_
stop_ts=2020-05-13_06:37

sed -n "/^$start_ts/,/^$stop_ts/p" /tmp/$$.mtr_all.csv > /tmp/$$.mtr.csv

# take unique dates
tstamps=$(cat /tmp/$$.mtr.csv | cut -d';' -f1 | sort -u)

# take unique hosts
hops=$(cat /tmp/$$.mtr.csv | cut -d';' -f3 | sort -un)


#
# latency
#

# print header
echo -n 'date;time;hops;probes;latency;'
for hop in $hops; do
    echo -n "hop no.$(echo $hop | tr -d '.');" 
done
echo

# print data row
for tstamp in $tstamps; do
    echo -n "$tstamp;" | tr '_' ';'
    grep "^$tstamp" /tmp/$$.mtr.csv  > /tmp/$$.mtr_now.csv
    hops_cnt=$(tail -1 /tmp/$$.mtr_now.csv | cut -d';' -f3 | tr -d '.')
    probes_cnt=$(tail -1 /tmp/$$.mtr_now.csv | cut -d';' -f6)
    latency=$(tail -1 /tmp/$$.mtr_now.csv | cut -d';' -f7)
    echo -n "$hops_cnt;$probes_cnt;$latency;"
    for hop in $hops; do
        avg=$(grep ";$hop;" /tmp/$$.mtr_now.csv  | cut -d';' -f7)
        : ${avg:=0}
        echo -n "$avg;"
    done
    echo 
done

#
# packet loss
#

# print header
echo -n 'date;time;hops;probes;loss;'
for hop in $hops; do
    echo -n "hop no.$(echo $hop | tr -d '.');" 
done
echo

# print data
for tstamp in $tstamps; do
    echo -n "$tstamp;" | tr '_' ';'
    grep "^$tstamp" /tmp/$$.mtr.csv  > /tmp/$$.mtr_now.csv
    hops_cnt=$(tail -1 /tmp/$$.mtr_now.csv | cut -d';' -f3 | tr -d '.')
    probes_cnt=$(tail -1 /tmp/$$.mtr_now.csv | cut -d';' -f6)
    loss_target=$(tail -1 /tmp/$$.mtr_now.csv | cut -d';' -f5 | tr -d '%')
    echo -n "$hops_cnt;$probes_cnt;$loss_target;"
    for hop in $hops; do
        loss=$(grep ";$hop;" /tmp/$$.mtr_now.csv  | cut -d';' -f5)
        : ${loss:=0}
        [ $loss == 100 ] && loss='100%'
        [ $loss == 100.0 ] && loss='100%'
        echo -n "$loss;" | tr -d '%'
    done
    echo 
done