#!/bin/bash

continue=false
interval=0
req_url=""
past_time=""
mpd_file="temp.mpd"
download_mpd=""
save_path=""
save_seg=0
seg_count=0
last_d=0
last_t=0
# mpd_type: 1:template, 2:timeline
mpd_type=1
current_time=0
list_url=0

function usage()
{
    echo "Usage: $0 <-f mpd_file|-u mpd_url> [options...]"
    echo "Options:"
    echo " -f mpd_file    parse local mpd file"
    echo " -u mpd_url     get mpd from URL."
    echo " -i interval    request segments interval, default value: segment duration"
    echo " -t timestamp   get the segment number at a given time(seconds since 1970-01-01 00:00:00 UTC)."
    echo " -w             download and save segments."
    echo " -l             list all segments t for timeline MPD."
    exit 0;
}



function get_current_num()
{
    if [ $mpd_type -eq 1 ]
	then
		current_number=$(($timeshift/($duration/$timescale) + $startNumber))
	fi
	
	if [ $mpd_type -eq 2 ]
	then
		handle_timeline
		current_number=$(($startNumber + $seg_count - 1 ))
	fi
	
	
}

function handle_timeline()
{
seg_start_pos=$(($(grep SegmentTimeline $mpd_file -n |head -1|awk -F: '{print $1}') + 1))
seg_end_pos=$(($(grep /SegmentTimeline $mpd_file -n |head -1|awk -F: '{print $1}') - 1 ))
sed -n "${seg_start_pos},${seg_end_pos}p" $mpd_file > timeline.temp
seg_count=0
next_t=0
while read line 
do 
    t=$(echo $line |sed 's/ /\n/g' |grep t= |cut -d "\"" -f 2)
    d=$(echo $line |sed 's/ /\n/g' |grep d= |cut -d "\"" -f 2)
    r=$(echo $line |sed 's/ /\n/g' |grep r= |cut -d "\"" -f 2)
    
	if [ -z $r ]
	then 
		r=0
	fi 
	if [ -z $t ]
	then 
		t=$next_t
	fi
    next_t=$(($t + $d*($r + 1)))
    seg_count=$(($seg_count + $r + 1))


done   < timeline.temp 
last_d=$d
last_t=$(($t + $d * $r))
echo "seg_count="$seg_count
echo "last_t="$last_t
echo "last_d="$last_d

}


function list_all_seg_url()
{
    seg_start_pos=$(($(grep SegmentTimeline $mpd_file -n |head -1|awk -F: '{print $1}') + 1))
    seg_end_pos=$(($(grep /SegmentTimeline $mpd_file -n |head -1|awk -F: '{print $1}') - 1 ))
    sed -n "${seg_start_pos},${seg_end_pos}p" $mpd_file > timeline.temp
    seg_count=0
    next_t=0
    while read line
    do
        t=$(echo $line |sed 's/ /\n/g' |grep t= |cut -d "\"" -f 2)
        d=$(echo $line |sed 's/ /\n/g' |grep d= |cut -d "\"" -f 2)
        r=$(echo $line |sed 's/ /\n/g' |grep r= |cut -d "\"" -f 2)

            if [ -z $r ]
            then
                    r=0
            fi
            if [ -z $t ]
            then
                    t=$next_t
            fi
        for idx in $(seq 0 $r)
        do
            seg_url=${video_rep_seg/\$Time\$/$t}
            echo $seg_url
            t=$(($t + $d))
        done
        next_t=$t
        seg_count=$(($seg_count + $r + 1))

    done   < timeline.temp
    last_d=$d
    last_t=$(($t + $d * $r))
    echo "seg_count="$seg_count

}


################################### main ###################################################################
while getopts f:ct:i:u:wlh OPTION; do
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
    l)
        list_url=1
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
    usage
exit 0
fi

echo $mpd_file
sed -i 's/\&amp;/\&/g' $mpd_file

if grep "type=\"static\"" $mpd_file > /dev/null 2>&1
then
    echo "mpd tpye is not dynamic. "
    exit 0;
fi


if grep SegmentTimeline $mpd_file > /dev/null 2>&1
then 
    mpd_type=2
fi
echo "mpd_type="$mpd_type

minimumUpdatePeriod=$(grep "<MPD " $mpd_file |sed 's/ /\n/g'|grep minimumUpdatePeriod|cut -d "\"" -f 2|tr -d "a-zA-Z")
echo "minimumUpdatePeriod="$minimumUpdatePeriod


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
if [ $mpd_type -eq 1 ]
then
    seg_duration=$(($duration/$timescale))
fi
if [ $mpd_type -eq 2 ]
then
    handle_timeline
    seg_duration=$(($last_d/$timescale))
fi
echo "seg_duration="$seg_duration

startNumber=$(grep SegmentTemplate $mpd_file |head -1|sed 's/ /\n/g'|grep startNumber |cut -d "\"" -f 2)
#startNumber=${startNumber//\"/}
echo "startNumber="$startNumber


video_media=$(awk '/="video/{video=1} {if(video==1 && /<SegmentTemplate/)print }' $mpd_file |head -1|sed 's/ /\n/g'|grep media= |cut -d "\"" -f 2)
#media=${media//\"/}
echo "video_media="$video_media

audio_media=$(awk '/="audio/{audio=1} {if(audio==1 && /<SegmentTemplate/)print }' $mpd_file |head -1|sed 's/ /\n/g'|grep media= |cut -d "\"" -f 2)
#media=${media//\"/}
echo "audio_media="$audio_media

video_Rep_id=$(awk '/="video/{video=1} {if(video==1 && /<Representation/)print }'  $mpd_file |head -1|sed 's/ /\n/g'|grep id= |cut -d "\"" -f 2)
#video_Rep_id=${video_Rep_id//\"/}
echo "video_Representation_id="$video_Rep_id

audio_Rep_id=$(awk '/="audio/{audio=1} {if(audio==1 && /<Representation/)print }'  $mpd_file |head -1|sed 's/ /\n/g'|grep id= |cut -d "\"" -f 2)
echo "audio_Representation_id="$audio_Rep_id

#Rep_id=$(grep "<Representation " $mpd_file |head -1|sed 's/ /\n/g'|grep id= |cut -d "\"" -f 2)




availabilityStartTime1=${availabilityStartTime/Z/}
availabilityStartTime1=${availabilityStartTime1/T/ }
#availabilityStartTime1=${availabilityStartTime1//\"/ }
#echo $availabilityStartTime1
AST=`date -d  "${availabilityStartTime1}" -u +%s`
echo "AST="$AST

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

#timeshift=$(($current_time - $AST))
#echo $timeshift
#current_number=$(($timeshift/($duration/$timescale) + $startNumber))
#if [ $mpd_type -eq 2 ]
#then
#    timeline
#    current_number=$(($startNumber + $seg_count - 1 ))
#fi
#get_current_num
#echo "current_number = "$current_number

#Rep_seg=${media/\$RepresentationID\$/$Rep_id}
video_rep_seg=${video_media/\$RepresentationID\$/$video_Rep_id}
audio_rep_seg=${audio_media/\$RepresentationID\$/$audio_Rep_id}
#current_seg=${Rep_seg/\$Number\$/$current_number}
#current_seg=${current_seg/\$Time\$/$last_t}
#echo "current_segment:"$current_seg

if [ $list_url -eq 1 ]
then 
    list_all_seg_url
    exit 0 
fi 


while true
do
current_time=`date -u +%s`
echo "current_time = "$current_time
timeshift=$(($current_time - $AST))
get_current_num #current_number=$(($timeshift/($duration/$timescale) + $startNumber))
echo "current_number = "$current_number

current_video_seg=${video_rep_seg/\$Number\$/$current_number}
current_video_seg=${current_video_seg/\$Time\$/$last_t}
video_seg_name=${current_video_seg%\?*}
echo "current_video_segment: "$video_seg_name
video_segment_url=$url_base"/"$current_video_seg
echo "segment_video_url: "$video_segment_url

current_audio_seg=${audio_rep_seg/\$Number\$/$current_number}
current_audio_seg=${current_audio_seg/\$Time\$/$last_t}
audio_seg_name=${current_audio_seg%\?*}
echo "current_audio_segment: "$audio_seg_name
audio_segment_url=$url_base"/"$current_audio_seg
echo "segment_audio_url: "$audio_segment_url


if [ $save_seg -eq 1 ]
then
    echo "downloading "${current_video_seg%%\?*}
    curl  $video_segment_url -o $video_seg_name  > /dev/null 2>1& 
    echo "downloading "${current_audio_seg%%\?*}
    curl  $audio_segment_url -o $audio_seg_name  > /dev/null 2>1& 
fi

sleep $interval

done 


