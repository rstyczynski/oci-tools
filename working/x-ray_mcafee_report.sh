 

function format() {
    tr '\n' '\t' | sed 's/date/\ndate/g'
    echo
}

function getvalue() {
    from=$1
    what=$2
     
    row=$(cat $from | grep $what 2>/dev/null)
    if [ $? -ne 0 ]; then
        value=''
        return 1
    else
        value=$(echo $row | cut -d= -f2)
    fi

    echo $value
}

# to stop per from complains about locale
export LC_CTYPE=en_US.UTF-8
export LC_ALL=en_US.UTF-8

env_files=/mwlogs
env=infra

states=$(ls $env_files/x-ray/*/*/watch/hosts/*/malware/*/state)
for state in $states; do
    env=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w-_\.]+)\/malware\/([\w-_\.]+)\/state/$1/')
    component=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w-_\.]+)\/malware\/([\w-_\.]+)\/state/$2/')
    hostname=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w-_\.]+)\/malware\/([\w-_\.]+)\/state/$3/')
    scan_name=$(echo $state | perl -pe's/\/mwlogs\/x-ray\/(\w+)\/(\w+)\/watch\/hosts\/([\w-_\.]+)\/malware\/([\w-_\.]+)\/state/$4/')

    timestamp=$(getvalue $state timestamp)
    Totalfiles=$(getvalue $state Totalfiles)

    if [ ! -z $Totalfiles ]; then
        Clean=$(getvalue $state Clean)
        NotScanned=$(getvalue $state NotScanned)
        PossiblyInfected=$(getvalue $state PossiblyInfected)
        Time=$(getvalue $state Time)

        scan_time=$(echo "$(echo $Time | cut -d: -f1) * 3600 + $(echo $Time | cut -d: -f2) * 60 + $(echo $Time | cut -d: -f3)" | bc)

        thousend_files_msec=$( echo "$scan_time * 1000 / $Totalfiles" | bc)

        echo $env $component $hostname $scan_name $timestamp $Totalfiles $Clean $NotScanned $PossiblyInfected $Time $scan_time $thousend_files_msec
    fi
done
