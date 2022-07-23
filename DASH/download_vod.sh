#!/bin/bash

continue=false
interval=-1
req_url=""
past_time=""
specified_rep_id=""
mpd_file="temp.mpd"
download_mpd=""
save_path=""
save_seg=0
seg_count=0
seg_duration=0
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
    echo " -f <mpd_file>    parse local mpd file"
    echo " -u <mpd_url>     get mpd from URL."
    echo " -i [interval]    request segments interval, default value: segment duration"
    echo " -w               download and save segments."
    echo " -l               list all segments t for timeline MPD."
    echo " -p <profile_id>  download specified profile only"
    exit 0;
}



function get_current_num()
{
    if [ $mpd_type -eq 1 ]
    then
        current_number=$(($startNumber + $seg_count))
        seg_count=$(($seg_count + 1))
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
    sed -n "${seg_start_pos},${seg_end_pos}p" $mpd_file > timeline.tmp
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
    done   < timeline.tmp 

    last_d=$d
    last_t=$(($t + $d * $r))
    echo "seg_count="$seg_count
    echo "last_t="$last_t
    echo "last_d="$last_d

}


function download_segment()
{
    file_name=${1%\?*}
    file_name=${file_name##*/}
    curl -s $1 -o $file_name  -w "$(date -u "+%Y-%m-%d_%H:%M:%S") %{http_code} $1 %{time_total}\n" |tee -a  download.log
}

function list_all_seg_url()
{
    rep_id=$1
    template_rep_seg=$2
    awk -v rep_id=rep_id '{if(start==1 && /<\/SegmentTimeline/){exit};if(find==1 && start==1)print;if(/<Representation.*id="'$rep_id'"/){find=1};if(find==1 && /<SegmentTimeline/){start=1}}' $mpd_file  > timeline.tmp
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
            seg_url=${template_rep_seg/\$Time\$/$t}
            if [ $save_seg -eq 1 ]
            then
                if [ ! -n "$url_base" ]
                then
                    echo "Invalid URL."
                    exit 0                    
                fi
                download_segment $url_base"/"$seg_url
            else
                echo $url_base"/"$seg_url
            fi
            t=$(($t + $d))
        done
        next_t=$t
        seg_count=$(($seg_count + $r + 1))

    done   < timeline.tmp
    last_d=$d
    last_t=$(($t + $d * $r))
    echo "seg_count="$seg_count

}

#todo: support timeline
################################### main ###################################################################
while getopts f:ct:i:p:u:wlh OPTION; do
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
    p)
        specified_rep_id=$OPTARG
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

if grep "type=\"dynamic\"" $mpd_file > /dev/null 2>&1
then
    echo "mpd is not static. "
    exit 0;
fi


if grep SegmentTimeline $mpd_file > /dev/null 2>&1
then 
    mpd_type=2
fi
echo "mpd_type="$mpd_type

mediaPresentationDuration=$(grep "<MPD " $mpd_file |sed 's/ /\n/g'|grep mediaPresentationDuration|cut -d "\"" -f 2|tr -d "a-zA-Z")
echo "mediaPresentationDuration="$mediaPresentationDuration

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

if [ -n "$specified_rep_id" ]
then
    specified_media=$(awk -v specified_rep_id=specified_rep_id  '{if(/<Representation.*id="'$specified_rep_id'"/){find=1};if(find==1 && /<SegmentTemplate/)print }' $mpd_file |head -1|sed 's/ /\n/g'|grep media= |cut -d "\"" -f 2)
    if [ -z "$specified_media" ]
    then
        echo "Cant find "$specified_rep_id
        exit 0
    fi

fi

video_media=$(awk '/contentType="video"/{video=1} {if(video==1 && /<SegmentTemplate/)print }' $mpd_file |head -1|sed 's/ /\n/g'|grep media= |cut -d "\"" -f 2)
#media=${media//\"/}
echo "video_media="$video_media
audio_media=$(awk '/contentType="audio"/{audio=1} {if(audio==1 && /<SegmentTemplate/)print }' $mpd_file |head -1|sed 's/ /\n/g'|grep media= |cut -d "\"" -f 2)
#media=${media//\"/}
echo "audio_media="$audio_media
subtitle_media=$(awk '/contentType="text"/{text=1} {if(text==1 && /<SegmentTemplate/)print }' $mpd_file |head -1|sed 's/ /\n/g'|grep media= |cut -d "\"" -f 2)
#media=${media//\"/}
echo "subtitle_media="$subtitle_media

video_Rep_id=$(awk '/contentType="video"/{video=1} {if(video==1 && /<Representation/)print }'  $mpd_file |head -1|sed 's/ /\n/g'|grep id= |cut -d "\"" -f 2)
#video_Rep_id=${video_Rep_id//\"/}
echo "video_Representation_id="$video_Rep_id

audio_Rep_id=$(awk '/contentType="audio"/{audio=1} {if(audio==1 && /<Representation/)print }'  $mpd_file |head -1|sed 's/ /\n/g'|grep id= |cut -d "\"" -f 2)
echo "audio_Representation_id="$audio_Rep_id

subtitle_Rep_id=$(awk '/contentType="text"/{text=1} {if(text==1 && /<Representation/)print }'  $mpd_file |head -1|sed 's/ /\n/g'|grep id= |cut -d "\"" -f 2)
echo "subtitle_Representation_id="$subtitle_Rep_id



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


if [ $interval -eq -1 ]
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

video_rep_seg=${video_media/\$RepresentationID\$/$video_Rep_id}
audio_rep_seg=${audio_media/\$RepresentationID\$/$audio_Rep_id}
subtitle_rep_seg=${subtitle_media/\$RepresentationID\$/$subtitle_Rep_id}
#current_seg=${Rep_seg/\$Number\$/$current_number}
#current_seg=${current_seg/\$Time\$/$last_t}
#echo "current_segment:"$current_seg

if [ $list_url -eq 1 ]
then 
    if [ $mpd_type -ne 2 ]
    then 
        echo "not support template MPD"
        exit 0
    fi
    if [ ! -z "$specified_rep_id" ]
    then
        list_all_seg_url $specified_rep_id $specified_media
    else
        list_all_seg_url $video_Rep_id $video_rep_seg
        list_all_seg_url $audio_Rep_id $audio_rep_seg
        if [ -n $subtitle_media ]
        then
            list_all_seg_url $subtitle_Rep_id $subtitle_rep_seg
        fi
    fi
    exit 0 
fi 

seg_count=0

while true
do
current_time=`date -u +%s`
#echo "current_time = "$current_time
timeshift=$(($current_time - $AST))
get_current_num #current_number=$(($timeshift/($duration/$timescale) + $startNumber))
#echo "current_number = "$current_number

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

if [ -n $subtitle_media ]
then
    current_subtitle_seg=${subtitle_rep_seg/\$Number\$/$current_number}
    current_subtitle_seg=${current_subtitle_seg/\$Time\$/$last_t}
    subtitle_seg_name=${current_subtitle_seg%\?*}
    echo "current_subtitle_segment: "$subtitle_seg_name
    subtitle_segment_url=$url_base"/"$current_subtitle_seg
    echo "segment_subtitle_url: "$subtitle_segment_url
fi


if [ $save_seg -eq 1 ]
then
    echo "downloading "${current_video_seg%%\?*}
    curl  $video_segment_url -o $video_seg_name  > /dev/null 2>1& 
    echo "downloading "${current_audio_seg%%\?*}
    curl  $audio_segment_url -o $audio_seg_name  > /dev/null 2>1& 
    if [ -n $subtitle_media ]
    then
        echo "downloading "${current_subtitle_seg%%\?*}
        curl  $subtitle_segment_url -o $subtitle_seg_name  > /dev/null 2>1&
    fi
fi

if [ $((seg_duration*seg_count)) -gt $mediaPresentationDuration ]
then
    exit 0
fi
sleep $interval

done 
