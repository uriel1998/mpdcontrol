#!/bin/bash

################################################################################
# A rewritten script of a utility to make it simple to control MPD without 
# having to be too damn specific about anything. 
#
# by Steven Saus
#
################################################################################


ADDMODE="1"    
export SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Setting them here, will create if needed later
# Chooses ./config FIRST by default
if [ -w "${SCRIPT_DIR}/config" ]; then
	ConfigDir="${SCRIPT_DIR}/config"
elif [ -n "${XDG_CONFIG_HOME}" ]; then
	ConfigDir="${XDG_CONFIG_HOME}/mpdc"
else
	ConfigDir="$HOME/.config/mpdc"
fi

# check for existence is in read_variables
if [ -f "$ConfigDir/mpdc.ini" ];then
	ConfigFile="$ConfigDir/mpdc.ini"
elif [ -f "$ConfigDir/mpdq.ini" ];then
	"$ConfigDir/mpdq.ini"
fi


function loud() {
    if [ $LOUD -eq 1 ];then
        echo "$@"
    fi
}

function set_host_arg() {
    # in case the password is already set in environment
    if [ -n "$MPD_PASS" ] && [ "$MPD_HOST" != *"@"* ]; then
        host_arg="$MPD_PASS@$MPD_HOST"
    else
        host_arg="$MPD_HOST"
    fi
}

function read_variables() {
    if [ -f "$ConfigFile" ];then
        config=$(cat "$ConfigFile")
    else
        loud "Configuration file not found; using defaults."
    fi
    # If there's no config file or a line is malformed or missing, sub in the default value

    MPD_HOST="$(echo "$config" | ${grep_bin} -e "^mpdserver=" | cut -d = -f 2- || echo localhost)"
    MPD_PASS=$(echo "$config" | ${grep_bin} -e "^mpdpass=" | cut -d = -f 2-)
    MPD_PORT=$(echo "$config" | ${grep_bin} -e "^mpdport=" | cut -d = -f 2- || echo 6600)
    set_host_arg
    # fallback of fallbacks
	if [ -z "$MPD_HOST" ];then
		MPD_HOST=localhost
	fi
    
}



# get playlists (prefix an emoji) 📋
# get stations (prefix an emoji) 🎛️
# get listen to di (prefix an emoji) 📡
# get webradio presets from radiotray (prefix an emoji) 📻
# get genre 🎼
# get album_artist  🎸
# get album 💿  (present as album by AlbumArtist)
# get track 🎶 (present as track by Artist)
mpc lsplaylists
mpdq -e (need to trim path and ext)
mpc list album group genre
mpc list artist group genre 
listen to di reads pls files

all of these need to be stored in a single data format
icon,source,title,full specification (url, text file to select on, whatever)
then use case to split out how to pass them along
	
	(streamlink, url, whatever)
	
	Just do playlists and stations and listentodi to start, then add in the rest
# present in big ass scrollable list
# throw into fzf|rofi | php ?? 
# get result, pipe back to mpc, mpdq, listen_to_di, however pipe in webradio preset
  

    
    
    if [ "$1" == "-c" ];then
        ADDMODE="0"
        shift
    fi
    
now_album(){
    
    artist=$(mpc --host "$MPD_HOST" current --format "%artist%")
    album=$(mpc --host "$MPD_HOST" current --format "%album%")


    if [[ -z "$artist" || -z "$album" ]]; then
        echo "No song is currently playing."
    else
        clearmode
        mpc --host "$MPD_HOST" search album "$album" | mpc add
        mpc --host "$MPD_HOST" play
    fi
}
    
now_artist(){
    
    album_artist=$(mpc --host "$MPD_HOST" current --format "%albumartist%")
    if [[ -z "$album_artist" ]]; then
        echo "No song is currently playing or no album artist information available."
    else
        clearmode
        mpc --host "$MPD_HOST" search albumartist "$album_artist" | mpc add
        mpc --host "$MPD_HOST" play
    fi

}    
    
    
    
    

clearmode (){  
        if [ "$ADDMODE" = "0" ];then
            mpc --host "$MPD_HOST" clear -q
			# if there is anything in genre "Bumper" then choose one randomly and add it.
			SongStem=$(mpc --host "${MPD_HOST}" find genre "Bumper" | shuf -n1 )
			if [ "$SongStem" != "" ];then
				# We will also use $SongFile as a continuing check
				SongFile="$MPDBASE/$SongStem"
				`mpc --host $MPD_HOST add "${SongStem}"`
			fi            
            # This doesn't work with the shuffle implementation and the way I add songs here.
            #SongStem=$(mpc --host "${MPD_HOST}" -port "${MPD_PORT}" find genre "Bumper" | shuf -n1 )
			#if [ "$SongStem" != "" ];then
				#`mpc --host $MPD_HOST --port $MPD_PORT add "${SongStem}"`
			#fi
        fi
}
    
    
    
interactive(){  

    echo -e "\E[0;32m(\E[0;37mc\E[0;32m)ustom, \E[0;32m(\E[0;37mg\E[0;32m)enre, (\E[0;37mA\E[0;32m)lbumartist, (\E[0;37ma\E[0;32m)rtist, a(\E[0;37ml\E[0;32m)bum, (\E[0;37ms\E[0;32m)ong, (\E[0;37mp\E[0;32m)laylist, or (\E[0;37mq\E[0;32m)uit? "; tput sgr0
    read -r CHOICE


    case "$CHOICE" in
        "c") 
            if [ -f "$(which fzf)" ];then 
                result=$(mpc --host "$MPD_HOST" list genre | fzf --multi)
            else
                result=$(mpc --host "$MPD_HOST" list genre | pick)
            fi
            
            selection=""
            while IFS= read -r genre; do
                bob=$(mpc --host "$MPD_HOST" -f "%title% ‡ %artist%" search genre "$genre")
                selection=$(echo "$selection $bob")
            done <<< "$result"    
            
# for year in {1990..1999}; do     mpc -f "%album% - %artist% - %genre%" find genre "Rock" date "$year"; done  | sort | uniq                
        ### TODO
        ### THIS IS IT - WE CAN ACTUALLY PUT IN A SHORTCUT MATCH FOR OTHER FIELDS HERE TOO!
        ### EG g:${genre} so if you want to limit what you're seeing, you can type g:Rock
        ### I THINK if FZF does each term separately
        # TODO - findadd BOTH artist and title, lololol
            if [ -f "$(which fzf)" ];then 
                result=$(echo "$selection" | fzf --multi)
            else
                result=$(echo "$selection" | pick )
            fi            
            clearmode
            while IFS= read -r line; do
                title=$(echo "${line}" | awk -F ' ‡' '{print $1}') 
                artist=$(echo "${line}" | awk -F '‡ ' '{print $2}') 
                echo "$title"
                echo "$artist"
                mpc --host "$MPD_HOST" findadd title "${title}" artist "${artist}"
            done <<< "$result"
            mpc --host "$MPD_HOST" play
        ;;


        "s") 
            if [ -f "$(which fzf)" ];then 
                result=$(mpc --host "$MPD_HOST" list title | fzf --multi)
            else
                result=$(mpc --host "$MPD_HOST" list title | pick)
            fi            
            clearmode
            while IFS= read -r title; do
                mpc --host "$MPD_HOST" findadd title "${title}" 
            done <<< "$result"
            mpc --host "$MPD_HOST" play
        ;;

        "A") 
            if [ -f "$(which fzf)" ];then 
                result=$(mpc --host "$MPD_HOST" list albumartist | fzf --multi)
            else
                result=$(mpc --host "$MPD_HOST" list albumartist | pick)
            fi            
            clearmode
            while IFS= read -r albumartist; do
                mpc --host "$MPD_HOST" findadd albumartist "${albumartist}" 
                mpc --host "$MPD_HOST" shuffle -q
                mpc --host "$MPD_HOST" play
            done <<< "$result"
        ;;
        "a") 
            if [ -f "$(which fzf)" ];then 
                result=$(mpc --host "$MPD_HOST" list artist | fzf --multi)
            else
                result=$(mpc --host "$MPD_HOST" list artist | pick)
            fi
            clearmode
            while IFS= read -r artist; do
                mpc --host "$MPD_HOST" findadd artist "${artist}" 
                mpc --host "$MPD_HOST" shuffle -q
                mpc --host "$MPD_HOST" play
            done <<< "$result"
        ;;
        "l") 

            if [ -f "$(which fzf)" ];then 
                result=$(mpc --host "$MPD_HOST" list album | fzf --multi)
            else
                result=$(mpc --host "$MPD_HOST" list album | pick)
            fi
            clearmode
            while IFS= read -r album; do
                mpc --host "$MPD_HOST" findadd album "$album"
                mpc --host "$MPD_HOST" random off
                mpc --host "$MPD_HOST" play
            done <<< "$result"
        ;;

        "g") 
            if [ -f "$(which fzf)" ];then 
                result=$(mpc --host "$MPD_HOST" list genre | fzf --multi)
            else
                result=$(mpc --host "$MPD_HOST" list genre | pick)
            fi
            clearmode
            while IFS= read -r genre; do
                mpc --host "$MPD_HOST" findadd genre "$genre" 
                mpc --host "$MPD_HOST" shuffle -q
                mpc --host "$MPD_HOST" play
            done <<< "$result"
        ;;
        "p")
            if [ -f "$(which fzf)" ];then 
                result=$(mpc --host "$MPD_HOST" lsplaylists | fzf --multi)
            else
                result=$(mpc --host "$MPD_HOST" lsplaylists | pick)
            fi
            clearmode            
            while IFS= read -r playlist; do
                mpc --host "$MPD_HOST" load "$playlist" 
                mpc --host "$MPD_HOST" play
            done <<< "$result"
        ;;
        "q")
        ;;
        "h") echo "Use -c to clear before adding.  Export your MPD_HOST as PASS@HOST; localhost is default";;
        *)            echo "You have chosen poorly. Run without commandline input.";;
    esac
}


case "${1}" in 
    nowal*|now_al*)
                now_album
                ;;
    nowar*|now_ar*)
                now_artist
                ;;
    -c) ADDMODE="0"
        shift
        ;;
    *) interactive "${@}"
        ;;
esac
