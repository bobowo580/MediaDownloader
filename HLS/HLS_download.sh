#!/bin/bash


function usage()
{
    echo "Usage: $0 <-u media_url> [options...]"
    echo "Options:"
    echo " -u media_url     m3u8 index URL."
    echo " -i interval    request segments interval, default value: segment duration"
    echo " -w             download and save segments."
    exit 0;
}

trap 'onCtrlC' INT
function onCtrlC () 
{
    rm m3u8.tmp rate_list.tmp seg_list.tmp > /dev/null 2>&1
    rm *m3u8.list *.m3u8 > /dev/null 2>&1
    exit 0
}

function download_vod_seg()
{
    rate_m3u8=${1%\?*}
    seg_list=$rate_m3u8".list"
    curl -s $url_base"/"$1 -o $rate_m3u8 -w "$(date -u "+%Y-%m-%d_%H:%M:%S") %{http_code} $1 %{time_total}\n" |tee -a download.log
    cat $rate_m3u8 |grep -E "#EXT-X-MAP.*URI" | awk -F 'URI="' '{print $2}' |awk -F '"' '{print $1}' |sort|uniq  > $seg_list
    cat $rate_m3u8 |grep -v "#EXT" |sort|uniq >> $seg_list
    dos2unix $seg_list > /dev/null 2>&1
    cat $seg_list |while read seg
    do
        curl -s $url_base"/"$seg -o ${seg%\?*} -w "$(date -u "+%Y-%m-%d_%H:%M:%S") %{http_code} $seg %{time_total}\n" |tee -a download.log
    done

}

function download_vod()
{
    echo "Start to download..."
    while read rate_m3u8;
    do
        download_vod_seg $rate_m3u8 & 
    done < rate_list.tmp
    wait

}

function download_live_seg()
{
    rate_m3u8=$1
    m3u8=${rate_m3u8%\?*}
    last_seg="."
    while true
    do
        curl -s $url_base"/"$rate_m3u8 -o $m3u8 -w "$(date -u "+%Y-%m-%d_%H:%M:%S") %{http_code} $rate_m3u8 %{time_total}\n" >> download.log 
        seg=$(grep -v "#EXT" $m3u8|grep $last_seg -A1|tail -1 |dos2unix)
        seg_name=${seg%\?*}
        if [ ! -f $seg_name ]; then
            curl -s $url_base"/"$seg -o $seg_name -w "$(date -u "+%Y-%m-%d_%H:%M:%S") %{http_code} $seg %{time_total}\n" |tee -a  download.log &
            last_seg=$seg_name
        fi
        sleep $((target_duration/2))
    done
        
}


function download_live()
{
    echo "Start to download..."
    while read rate_m3u8
    do
        download_live_seg $rate_m3u8 & 
    done < rate_list.tmp
    wait

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
        usage
        exit 0
    ;;
    esac
done

if [ -n "$req_url" ]
then
    rm -f m3u8.tmp
    curl -v $req_url -o m3u8.tmp  --connect-timeout 2 2>curl.result -w "$(date -u "+%Y-%m-%d_%H:%M:%S") %{http_code} $req_url %{time_total}\n" >> download.log
    resp=$(grep "< HTTP/.*200" curl.result)
    if [ -z "$resp" ]
    then 
        echo "Can not get index. "$req_url
        #grep "< HTTP/" curl.result
        cat curl.result
        exit 0
    fi

    url_base=${req_url%/*}
    echo $url_base
    rm curl.result 
else
    echo "Please input media URL"
    usage
    exit 0
fi

grep EXT-X-VERSION m3u8.tmp
cat m3u8.tmp |grep -E "#EXT-X-MEDIA.*URI" | awk -F 'URI="' '{print $2}' |awk -F '"' '{print $1}' |sort|uniq  > rate_list.tmp
cat m3u8.tmp |grep -v "#EXT" |sort|uniq >> rate_list.tmp
dos2unix rate_list.tmp > /dev/null 2>&1
echo "RATE LIST:"
cat rate_list.tmp |cut -d "?" -f 1
echo 

curl -s $url_base"/"`tail -1 rate_list.tmp` -o m3u8.tmp

target_duration=$(grep  "#EXT-X-TARGETDURATION" m3u8.tmp |cut -d ":" -f 2 |dos2unix)
echo "DURATION: "$target_duration

if grep -q -E "EXT-X-PLAYLIST-TYPE:VOD|EXT-X-ENDLIST" m3u8.tmp ;then
    echo "PLAYLIST-TYPE: VOD"
    download_vod 
else
    echo "PLAYLIST-TYPE: EVENT"
    download_live 
fi



rm m3u8.tmp rate_list.tmp seg_list.tmp > /dev/null 2>&1
rm *m3u8.list  *.m3u8 > /dev/null 2>&1 

