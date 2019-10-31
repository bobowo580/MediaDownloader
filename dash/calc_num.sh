#!/bin/bash

if [[ $# -lt 2 ]]; then
echo "Usage: "$0" -f x.mpd"
echo $#
exit 0
fi
continue=false
interval=1

while getopts f:ct:i: OPTION; do
    case $OPTION in
    f)
      mpd_file=$OPTARG
    ;;
    c)
	continue=true
    ;;
    i)
	interval=$OPTARG
    ;;
    ?)
        echo "get a non option $OPTARG and OPTION is $OPTION"
    ;;
    esac
done

if [ ! -f $mpd_file ]
then
echo "Can not open mpd file $mpd_file."
exit 0
fi

echo $mpd_file
availabilityStartTime=$(grep availabilityStartTime $mpd_file |sed 's/ /\n/g'|grep availabilityStartTime|awk -F"=" '{print $2}')
echo "availabilityStartTime="$availabilityStartTime

duration=$(grep SegmentTemplate $mpd_file |head -1|sed 's/ /\n/g'|grep duration |awk -F"=" '{print $2}')
duration=${duration//\"/}
echo "duration="$duration

timescale=$(grep SegmentTemplate $mpd_file |head -1|sed 's/ /\n/g'|grep timescale |awk -F"=" '{print $2}')
timescale=${timescale//\"/}
echo "timescale="$timescale

startNumber=$(grep SegmentTemplate $mpd_file |head -1|sed 's/ /\n/g'|grep startNumber |awk -F"=" '{print $2}')
startNumber=${startNumber//\"/}
echo "startNumber="$startNumber

availabilityStartTime1=${availabilityStartTime/Z/}
availabilityStartTime1=${availabilityStartTime1/T/ }
availabilityStartTime1=${availabilityStartTime1//\"/ }
#echo $availabilityStartTime1
AST=`date -d  "${availabilityStartTime1}" -u +%s`
echo "AST="$AST
current_time=`date -u +%s`
echo "current_time = "$current_time

timeshift=$(($current_time - $AST))
#echo $timeshift
current_number=$(($timeshift/($duration/$timescale + $startNumber)))
echo "current_number = "$current_number

while true
do
current_time=`date -u +%s`
echo "current_time = "$current_time
timeshift=$(($current_time - $AST))
current_number=$(($timeshift/($duration/$timescale + $startNumber)))
echo "current_number = "$current_number

sleep $interval

done 

