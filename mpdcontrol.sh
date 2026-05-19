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
INCLUDE_SOURCES=""
LISTEN_TO_DI_PLS=""
# ADDMODE can be 
# 0 - add
# 1 - clear
# 2 - crop (with bumper)
ADDMODE="2"     
host_arg=""
LOUD="0"
FZF_LINES=()

###############################################################functions
function loud() {
	# loud outputs on stderr
    if [ $LOUD -eq 1 ];then
        echo "$@" 1>&2
    fi
}

function info() {
	loud "[info] $@"
}

function warn() {
	loud "[warn] $@"
}

function error() {
	loud "[error] $@"
}

function append_fzf_lines() {
	while IFS= read -r line; do
		if [ -n "$line" ]; then
			FZF_LINES+=("$line")
		fi
	done
}

function set_host_arg() {
    # in case the password is already set in environment
    if [ -n "$MPD_PASS" ] && [[ "$MPD_HOST" != *"@"* ]]; then
        host_arg="$MPD_PASS@$MPD_HOST"
    else
        host_arg="$MPD_HOST"
    fi
}

function read_variables() {
    if [ -f "$ConfigFile" ];then
        config=$(cat "$ConfigFile")
    else
        warn "Configuration file not found; using defaults."
    fi
    
    # If there's no config file or a line is malformed or missing, sub in the default value
    MPDBASE="$(echo "$config" | ${grep_bin} -e "^musicdir=" | cut -d = -f 2- ||
        cat "$XDG_CONFIG_HOME/mpd/mpd.conf" | ${grep_bin} "^music" | cut -d'"' -f2 ||
        echo "$HOME/Music")"
    if [ -z "$MPD_HOST" ]; then
        MPD_HOST="$(echo "$config" | ${grep_bin} -e "^mpdserver=" | cut -d = -f 2-)"
    fi
    if [ -z "$MPD_HOST" ]; then
        MPD_HOST="localhost"
    fi
    if [ -z "$MPD_PASS" ]; then
        MPD_PASS=$(echo "$config" | ${grep_bin} -e "^mpdpass=" | cut -d = -f 2-)
    fi
    if [ -z "$MPD_PORT" ]; then
        MPD_PORT=$(echo "$config" | ${grep_bin} -e "^mpdport=" | cut -d = -f 2-)
    fi
    if [ -z "$MPD_PORT" ]; then
        MPD_PORT="6600"
    fi
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
	# --artist -> include artist
	# --album -> include albums
	# --all -> include all, appends string for all to INCLUDE SOURCES
	
	# --playlist-dir -> specify DI_PLS_DIR
	while [ $# -gt 0 ]; do
		case "$1" in
			--playlists)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}playlists "
				;;
			--stations)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}stations "
				;;
			--listentodi)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}listentodi "
				;;
			--radiotray)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}radiotray "
				;;
			--genre)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}genre "
				;;
			--artist)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}artist "
				;;
			--album)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}album "
				;;
			--all)
				INCLUDE_SOURCES="${INCLUDE_SOURCES}playlists stations listentodi radiotray genre artist album "
				;;
			--playlist-dir)
				shift
				if [ -z "$1" ]; then
					error "Missing argument for --playlist-dir"
					exit 1
				fi
				DI_PLS_DIR="$1"
				;;
			*)
				error "Unknown argument: $1"
				exit 1
				;;
		esac
		shift
	done
}

clearmode (){  
	if [ "$ADDMODE" == "1" ];then
		${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" clear -q
	fi
	if [ "$ADDMODE" == "2" ];then
		${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" crop -q
		# if there is anything in genre "Bumper" then choose one randomly and add it.
		SongStem=$(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" find genre "Bumper" | shuf -n1)
		if [ "$SongStem" != "" ];then
			SongFile="$MPDBASE/$SongStem"
			${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" add "${SongStem}"
		fi            
	fi
}
    
 
main (){
		
	local fzf_result=""
	local result_line=""
	local source=""
	local payload=""
	local station_config=""
	local play_after_add="0"
	#all of these need to be stored in a single data format
	#icon,source,title,full specification (url, text file to select on, whatever)
	
	if [[ "${INCLUDE_SOURCES}" == *"playlists"* ]];then
		# get playlists  
		append_fzf_lines < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" lsplaylists | sed 's/.*/&,&/' | sed 's/^/📋,playlist,/g')
	fi
	if [[ "${INCLUDE_SOURCES}" == *"stations"* ]];then
		# get stations  
		append_fzf_lines < <(${mpdq_bin} -e | sed -n '/\/default[^/]*\.cfg$/d; h; s#.*/##; s/\.cfg$//; s#^#🎛️,station,#; G; s/\n/,/; p')
	fi
	if [[ "${INCLUDE_SOURCES}" == *"listentodi"* ]];then
		# get listen to di or other playlist (prefix an emoji)  
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
							# THIS WILL GO TO OUR LIST ARRAY/VARIABLE			
							FZF_LINES+=("📡,radio,$title,$url")
						fi
						done < "$pls_file"
				done
			fi
	fi
	if [[ "${INCLUDE_SOURCES}" == *"radiotray"* ]];then	
		# get webradio presets from radiotray (functionally equivalent to listen to di here)
		if [ -f "${XDG_CONFIG_HOME}/radiotray-ng/bookmarks.json" ];then
			append_fzf_lines < <(${jq_bin} -r '
				.[]
				| .stations[]
				| "📻,radio,\(.name),\(.url)"
			' "${XDG_CONFIG_HOME}/radiotray-ng/bookmarks.json")
				# TODO MAKE THE VARIABLE WITH STATION EMJOI				
				fi
	fi	
	if [[ "${INCLUDE_SOURCES}" == *"genre"* ]];then
		# get genre 🎼
		append_fzf_lines < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list genre | sed 's/.*/&,&/' | sed 's/^/🎼,genre,/g')
	fi
	if [[ "${INCLUDE_SOURCES}" == *"artist"* ]];then
		# get album_artist  🎸
		append_fzf_lines < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list artist | sed 's/.*/&,&/' | sed 's/^/🎸,artist,/g')
	fi
	if [[ "${INCLUDE_SOURCES}" == *"album"* ]];then
		# get album 💿  (present as album by AlbumArtist)
		append_fzf_lines < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list album | sed 's/.*/&,&/' | sed 's/^/💿,album,/g')
	fi


	# present in big ass scrollable list
	# throw into fzf
	if [ ${#FZF_LINES[@]} -gt 0 ]; then
		fzf_result=$(printf '%s\n' "${FZF_LINES[@]}" |
			awk -F, '{print $1 " - " $3 "\t" $0}' |
			${fzf_bin} --exact --delimiter=$'\t' --with-nth=1 --multi |
			cut -f2-)
	fi

	if [ ${#fzf_result[@]} -gt 0 ];then
		# if the result from fzf is not null
		clearmode
		#then loop over the result, splitting out how to pass them along

		while IFS= read -r result_line; do
			if [ -z "$result_line" ]; then
				continue
			fi

			source=$(printf '%s\n' "$result_line" | cut -d',' -f2)
			payload=$(printf '%s\n' "$result_line" | cut -d',' -f4-)

			case "$source" in
				radio)
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" add "$payload"
					play_after_add="1"
					;;
				playlist)
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" load "$payload"
					play_after_add="1"
					;;
				genre)
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" findadd genre "$payload"
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" shuffle -q
					play_after_add="1"
					;;
				album)
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" findadd album "$payload"
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" random off
					play_after_add="1"
					;;
				artist)
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" findadd albumartist "$payload"
					${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" shuffle -q
					play_after_add="1"
					;;
				station)
					station_config="$payload"
					;;
				*)
					warn "Unhandled source type: $source"
					;;
			esac
		done <<< "$fzf_result"

		if [ -n "$station_config" ]; then
			${mpdq_bin} --config "$station_config"
		elif [ "$play_after_add" == "1" ]; then
			${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" play
		fi
	fi
	

}

##############################################################entrypoint


read_arguments "$@"
read_variables
main "${@}"
