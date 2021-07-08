#!/bin/bash

index_m3u8=""

function usage()
{
    echo "Usage: $0 <-u media_url> [options...]"
    echo "Options:"
    echo " -u media_url     m3u8 index URL."
    echo " -i interval    request segments interval, default value: segment duration"
    echo " -w             download and save segments."
    exit 0;
}


function download_media()
{
    curl -s $url_base"/"$1 -o m3u8.tmp
    cat m3u8.tmp |grep -E "#EXT-X-MAP.*URI" | awk -F 'URI="' '{print $2}' |awk -F '"' '{print $1}' |sort|uniq  > seg_list.tmp
    cat m3u8.tmp |grep -v "#EXT" |sort|uniq >> seg_list.tmp
    dos2unix seg_list.tmp > /dev/null 2>&1
    cat seg_list.tmp |while read line
    do
        echo $line
        curl -s $url_base"/"$line -o ${line%\?*}
    done

}

function download_vod()
{
    echo "Start to download..."
    cat rate_list.tmp |while read line
    do
        download_media $line
    done

}

function download_live()
{
    echo
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
    index_m3u8="index.m3u8.tmp"
    rm -f $index_m3u8
    curl -v $req_url -o $index_m3u8 -L --connect-timeout 2 2>curl.result
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

grep EXT-X-VERSION $index_m3u8
cat $index_m3u8 |grep -E "#EXT-X-MEDIA.*URI" | awk -F 'URI="' '{print $2}' |awk -F '"' '{print $1}' |sort|uniq  > rate_list.tmp
cat $index_m3u8 |grep -v "#EXT" |sort|uniq >> rate_list.tmp
dos2unix rate_list.tmp > /dev/null 2>&1
echo "RATE LIST:"
cat rate_list.tmp |cut -d "?" -f 1
echo 

playlist_type=$(curl -s $url_base"/"`tail -1 rate_list.tmp`|grep EXT-X-PLAYLIST-TYPE |cut -d ':' -f 2|dos2unix)
echo "PLAYLIST-TYPE: "$playlist_type

if [ "$playlist_type" == "VOD" ];then
    download_vod 
elif [ "$playlist_type" == "EVENT" ];then
    download_live 
else
    echo "Unknown PLAYLIST-TYPE: "$playlist_type
fi




