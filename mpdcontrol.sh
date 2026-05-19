#!/bin/bash

################################################################################
# A rewritten script of a utility to make it simple to control MPD without 
# having to be too damn specific about anything. 
#
# by Steven Saus
#
################################################################################


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

# Globals
# check for helper programs
grep_bin=$(which grep)
mpc_bin=$(which mpc)
fzf_bin=$(which fzf)
mpdq_bin=$(which mpdq)
jq_bin=$(which jq)
USE_SOURCES=""
LISTEN_TO_DI_PLS=""
ADDMODE="1"    
host_arg=""
LOUD="0"

###############################################################functions

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
    MPDBASE="$(echo "$config" | ${grep_bin} -e "^musicdir=" | cut -d = -f 2- ||
        cat "$XDG_CONFIG_HOME/mpd/mpd.conf" | ${grep_bin} "^music" | cut -d'"' -f2 ||
        echo $HOME/Music)"
    MPD_HOST="$(echo "$config" | ${grep_bin} -e "^mpdserver=" | cut -d = -f 2- || echo localhost)"
    MPD_PASS=$(echo "$config" | ${grep_bin} -e "^mpdpass=" | cut -d = -f 2-)
    MPD_PORT=$(echo "$config" | ${grep_bin} -e "^mpdport=" | cut -d = -f 2- || echo 6600)
    set_host_arg
    # preferentially use argument
    if [ -z "${DI_PLS_DIR}" ];then
		DI_PLS_DIR="$(echo "$config" | ${grep_bin} -e "^DI_PLS_DIR=" | cut -d = -f 2- || echo "$DI_PLS_DIR")"
	fi
}

read_arguments (){
	#limit data arguments
	# These set a global variable or array that is checked in 
	# main by appending the string, e.g. --playlists appends 'playlists '
	# --playlists -> include playlists from mpc
	# --stations -> include stations from mpdq
	# --listentodi -> include playlists from DI_PLS_DIR
	# --radiotray -> include from radiotray
	# --genre -> include genres
	# --album -> include artist	
	# --album -> include albums
	# --all -> include all, appends string for all to INCLUDE SOURCES
	
	# --playlist-dir -> specify DI_PLS_DIR
}


main (){

if [[ "${INCLUDE_SOURCES}" == *"playlists"* ]];then
	# get playlists (prefix an emoji) 📋
	${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" lsplaylists
fi
if [[ "${INCLUDE_SOURCES}" == *"playlists"* ]];then
	# get stations (prefix an emoji) 🎛️
	${mpdq_bin} -e (need to trim path and ext)
fi
if [[ "${INCLUDE_SOURCES}" == *"listentodi"* ]];then
	# get listen to di or other playlist (prefix an emoji) 📡
	# Loop through all .pls files in the specified directory
	if [ -d "${DI_PLS_DIR}" ];then 
		for pls_file in "${DI_PLS_DIR}"/*.pls; do
			# Parse each .pls file
			while IFS= read -r line; do
				# Check if the line contains a File or Title
				if [[ $line == File* ]]; then
					url=$(echo "$line" | cut -d'=' -f2)
				elif [[ $line == Title* ]]; then
					title=$(echo "$line" | cut -d'=' -f2)
					# Append title and url to variable 
	# TODO MAKE THE VARIABLE WITH STATION EMJOI				
					echo "$title ‡ $url" >> "$temp_file"
				fi
			done < "$pls_file"
		done
fi
if [[ "${INCLUDE_SOURCES}" == *"radiotray"* ]];then	
	# get webradio presets from radiotray (prefix an emoji) 📻
	if [ -d "${XDG_CONFIG_HOME}/radiotray-ng/bookmarks.json" ];then
		${jq_bin} -r '
			.[]
			| .stations[]
			| "\(.name) ‡ \(.url)"
		' "${XDG_CONFIG_HOME}/radiotray-ng/bookmarks.json"
	# TODO MAKE THE VARIABLE WITH STATION EMJOI				
fi	
if [[ "${INCLUDE_SOURCES}" == *"genre"* ]];then
	# get genre 🎼
	${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list album group genre
fi
if [[ "${INCLUDE_SOURCES}" == *"artist"* ]];then
	# get album_artist  🎸
	${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list artist group genre 
fi
if [[ "${INCLUDE_SOURCES}" == *"album"* ]];then
	# get album 💿  (present as album by AlbumArtist)
	${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list album group genre 
fi

#all of these need to be stored in a single data format
#icon,source,title,full specification (url, text file to select on, whatever)
# present in big ass scrollable list
# throw into fzf

#then use case to split out how to pass them along
	
#	(streamlink, url, whatever)
	

}

##############################################################entrypoint


read_arguments
read_variables
main "${@}"
