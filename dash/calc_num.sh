#!/bin/bash

continue=false
interval=0
req_url=""
past_time=""
mpd_file="temp.mpd"
download_mpd=""
save_path=""
save_seg=0

function usage()
{
    echo "Usage: $0 <-f mpd_file|-u mpd_url> [options...]"
    echo "Options:"
    echo " -f mpd_file    parse local mpd file"
    echo " -u mpd_url     get mpd from URL."
    echo " -i interval    request segments interval, default value: segment duration"
    exit 0;
}

while getopts f:ct:i:u:wh OPTION; do
    case $OPTION in
    f)
        mpd_file=$OPTARG
    ;;
    u)
	req_url=$OPTARG
    ;;
    i)
	interval=$OPTARG
    ;;
    t)
        past_time=$OPTARG
    ;;
    w)
        save_seg=1
    ;;
    h)
        usage
    ;;
    ?)
        echo "Wrong parameter."
        exit 0
    ;;
    esac
done

if [ -n "$req_url" ]
then
    mpd_file="download.mpd"
    rm -f $mpd_file
    curl -v $req_url -o $mpd_file --connect-timeout 2 2>curl.result
    resp=$(grep "< HTTP/.*200" curl.result)
    if [ -z "$resp" ]
    then 
        echo "Can not get MPD. "$req_url
        #grep "< HTTP/" curl.result
        cat curl.result
        exit 0
    fi

    url_base=${req_url%/*}
    #echo $url_base 
fi

if [ ! -f $mpd_file ]
then
    echo "Can not open mpd file $mpd_file."
exit 0
fi

echo $mpd_file

if grep "type=\"static\"" $mpd_file > /dev/null 2>&1
then
    echo "mpd tpye is not dynamic. "
    exit 0;
fi



minimumUpdatePeriod=$(grep "<MPD " $mpd_file |sed 's/ /\n/g'|grep minimumUpdatePeriod|cut -d "\"" -f 2|tr -d "a-zA-Z")
echo "minimumUpdatePeriod="$minimumUpdatePeriod

if [ $interval -ne 0 ]
then 
    minimumUpdatePeriod=$interval
fi 

availabilityStartTime=$(grep availabilityStartTime $mpd_file |sed 's/ /\n/g'|grep availabilityStartTime|cut -d "\"" -f 2)
echo "availabilityStartTime="$availabilityStartTime

duration=$(grep SegmentTemplate $mpd_file |head -1|sed 's/ /\n/g'|grep duration |cut -d "\"" -f 2)
#duration=${duration//\"/}
echo "duration="$duration

timescale=$(grep SegmentTemplate $mpd_file |head -1|sed 's/ /\n/g'|grep timescale |cut -d "\"" -f 2)
#timescale=${timescale//\"/}
if [ -z $timescale ]
then
    timescale=1
fi
echo "timescale="$timescale

seg_duration=$(($duration/$timescale))


startNumber=$(grep SegmentTemplate $mpd_file |head -1|sed 's/ /\n/g'|grep startNumber |cut -d "\"" -f 2)
#startNumber=${startNumber//\"/}
echo "startNumber="$startNumber

media=$(grep SegmentTemplate.*media $mpd_file |head -1|sed 's/ /\n/g'|grep media= |cut -d "\"" -f 2)
#media=${media//\"/}
echo "media="$media

Rep_id=$(grep "<Representation " $mpd_file |head -1|sed 's/ /\n/g'|grep id= |cut -d "\"" -f 2)
#Rep_id=${Rep_id//\"/}
echo "Representation_id="$Rep_id


availabilityStartTime1=${availabilityStartTime/Z/}
availabilityStartTime1=${availabilityStartTime1/T/ }
#availabilityStartTime1=${availabilityStartTime1//\"/ }
#echo $availabilityStartTime1
AST=`date -d  "${availabilityStartTime1}" -u +%s`
echo "AST="$AST
current_time=`date -u +%s`
echo "current_time = "$current_time

if [ -n "$past_time" ]
then
    timeshift=$(($past_time - $AST))
    echo $timeshift
    past_number=$(($timeshift/($duration/$timescale) + $startNumber))
    echo "number = "$past_number
    exit 0
fi


if [ $interval -eq 0 ]
then
    interval=$seg_duration
fi



timeshift=$(($current_time - $AST))
#echo $timeshift
current_number=$(($timeshift/($duration/$timescale) + $startNumber))
echo "current_number = "$current_number

Rep_seg=${media/\$RepresentationID\$/$Rep_id}
current_seg=${Rep_seg/\$Number\$/$current_number}
echo $current_seg

while true
do
current_time=`date -u +%s`
echo "current_time = "$current_time
timeshift=$(($current_time - $AST))
current_number=$(($timeshift/($duration/$timescale) + $startNumber))
echo "current_number = "$current_number
current_seg=${Rep_seg/\$Number\$/$current_number}
echo $current_seg
segment_url=$url_base"/"$current_seg
echo "segment url:"$segment_url
echo ${current_seg%%\?*}

if [ $save_seg -eq 1 ]
then
    echo "downloading "${current_seg%%\?*}
    curl  $segment_url -o ${current_seg%%\?*}  > /dev/null 2>1& 
fi

sleep $interval

done 

