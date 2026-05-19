#!/bin/bash

################################################################################
# A rewritten script of a utility to make it simple to control MPD without 
# having to be too damn specific about anything. 
#
# by Steven Saus
#
################################################################################


SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export SCRIPT_DIR

# Setting them here, will create if needed later
# Chooses ./config FIRST by default
if [ -w "${SCRIPT_DIR}" ]; then
	ConfigDir="${SCRIPT_DIR}"
elif [ -n "${XDG_CONFIG_HOME}" ]; then
	ConfigDir="${XDG_CONFIG_HOME}/mpdc"
else
	ConfigDir="$HOME/.config/mpdc"
fi

# check for existence is in read_variables
if [ -f "$ConfigDir/mpdc.ini" ];then
	ConfigFile="$ConfigDir/mpdc.ini"
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
ADDMODE=""
host_arg=""
LOUD="0"
FZF_LINES=()

###############################################################functions
function loud() {
	# loud outputs on stderr
	if [ "$LOUD" -eq 1 ];then
		printf '%s\n' "$*" 1>&2
	fi
}

function info() {
	loud "[info] $*"
}

function warn() {
	loud "[warn] $*"
}

function error() {
	loud "[error] $*"
}

function append_fzf_lines() {
	while IFS= read -r line; do
		if [ -n "$line" ]; then
			FZF_LINES+=("$line")
		fi
	done
}

function mpc_action() {
	if [ "$LOUD" -eq 1 ]; then
		${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" "$@"
	else
		${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" -q "$@"
	fi
}

function show_help() {
	cat <<'EOF'
Usage: mpdcontrol.sh [options]

Build an fzf chooser from MPD, mpdq, and radio sources, then act on the
selected result(s).

Source Options:
  --playlist, --playlists  Include MPD playlists
  --stations               Include mpdq station configs
  --listentodi             Include .pls radio entries from DI_PLS_DIR
  --radiotray              Include radiotray-ng bookmarks
  --genre                  Include MPD genres
  --artist                 Include MPD artists
  --album                  Include MPD albums
  --all                    Include all supported sources

Mode Options:
  --clear                  Clear playlist before adding selections
  --crop                   Crop playlist before adding selections, with bumper logic
  --loud                   Enable informational logging and non-quiet mpc actions

Config Options:
  --playlist-dir PATH      Override DI_PLS_DIR for --listentodi

Help:
  -h, --help               Show this help text and exit

Config Resolution:
  1. Environment variables already set in the shell
  2. ./mpdc.ini
  3. XDG config location
  4. Built-in defaults

Relevant config keys:
  mpdserver
  mpdport
  mpdpass
  musicdir
  DI_PLS_DIR
  ADDMODE

Multi-select behavior:
  Non-station selections are processed first
  Station selections are deferred until last
  If multiple stations are selected, one station is chosen at random
EOF
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
	config=""
    if [ -f "$ConfigFile" ];then
        config=$(cat "$ConfigFile")
    else
        warn "Configuration file not found; using defaults."
    fi
    
    # If there's no config file or a line is malformed or missing, sub in the default value
    MPDBASE="$(echo "$config" | ${grep_bin} -e "^musicdir=" | cut -d = -f 2- ||
        ${grep_bin} "^music" "$XDG_CONFIG_HOME/mpd/mpd.conf" | cut -d'"' -f2 ||
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
	    info "Using MPD host ${MPD_HOST}:${MPD_PORT}"
	    if [ -n "$MPD_PASS" ]; then
			info "MPD password is set"
	    fi
	    # preferentially use argument
    if [ -z "${DI_PLS_DIR}" ];then
		DI_PLS_DIR="$(echo "$config" | ${grep_bin} -e "^DI_PLS_DIR=" | cut -d = -f 2-)"
	fi
	    if [ -z "${ADDMODE}" ];then
			ADDMODE="$(echo "$config" | ${grep_bin} -e "^ADDMODE=" | cut -d = -f 2-)"
		fi
	    if [ -z "${ADDMODE}" ];then
			ADDMODE="0"
		fi
	    ADDMODE="$(printf '%s' "$ADDMODE" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
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
				-h|--help)
					show_help
					exit 0
					;;
				--clear)
					ADDMODE=1
					;;
			--crop)
				ADDMODE=2
				;;
			--loud)
				LOUD=1
				;;
				--playlist|--playlists)
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
	info "ADDMODE is ${ADDMODE}"
	case "$ADDMODE" in
		1)
			info "Clearing current playlist"
			mpc_action clear
			;;
		2)
			info "Cropping current playlist and adding bumper if available"
			# if it is a url, it won't move off of it.
			current_file=$(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" --format %file% current)
			if [[ "$current_file" == http://* || "$current_file" == https://* ]]; then
				info "Current track is a stream URL; clearing instead of cropping"
				mpc_action clear
			else
				mpc_action crop
			fi
			# if there is anything in genre "Bumper" then choose one randomly and add it.
			SongStem=$(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" find genre "Bumper" | shuf -n1)
			if [ "$SongStem" != "" ];then
				SongFile="$MPDBASE/$SongStem"
				mpc_action add "${SongStem}"
			fi
			;;
		0)
			:
			;;
		*)
			warn "Unknown ADDMODE '$ADDMODE'; defaulting to add mode."
			;;
	esac
}
    
 
main (){
	FZF_LINES=()
	local fzf_result=""
	local result_line=""
	local source=""
	local payload=""
	local chosen_station_config=""
	local play_after_add="0"
	local -a station_configs=()
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
				if [ ! -e "$pls_file" ]; then
					continue
				fi
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
		info "Built ${#FZF_LINES[@]} selectable entries"
		fzf_result=$(printf '%s\n' "${FZF_LINES[@]}" |
			awk -F, '{print $1 " - " $3 "\t" $0}' |
			${fzf_bin} --exact --delimiter=$'\t' --with-nth=1 --multi |
			cut -f2-)
	fi

	if [ -n "$fzf_result" ];then
		info "Selection made; processing results"
		clearmode

		# first pass: process everything except station selections
		while IFS= read -r result_line; do
			if [ -z "$result_line" ]; then
				continue
			fi

			source=$(printf '%s\n' "$result_line" | cut -d',' -f2)
			payload=$(printf '%s\n' "$result_line" | cut -d',' -f4-)

			case "$source" in
				station)
					station_configs+=("$payload")
					;;
				radio)
					info "Handling source ${source}"
					mpc_action add "$payload"
					play_after_add="1"
					;;
				playlist)
					info "Handling source ${source}"
					mpc_action load "$payload"
					play_after_add="1"
					;;
				genre)
					info "Handling source ${source}"
					mpc_action findadd genre "$payload"
					mpc_action shuffle
					play_after_add="1"
					;;
				album)
					info "Handling source ${source}"
					mpc_action findadd album "$payload"
					mpc_action random off
					play_after_add="1"
					;;
				artist)
					info "Handling source ${source}"
					mpc_action findadd albumartist "$payload"
					mpc_action shuffle
					play_after_add="1"
					;;
				*)
					warn "Unhandled source type: $source"
					;;
			esac
		done <<< "$fzf_result"

		if [ "$play_after_add" == "1" ]; then
			mpc_action play
		fi

		# second pass: if one or more station selections were made, choose one and run it last
		if [ ${#station_configs[@]} -gt 1 ]; then
			info "Multiple station selections made; choosing one at random"
			chosen_station_config=$(printf '%s\n' "${station_configs[@]}" | shuf -n1)
		elif [ ${#station_configs[@]} -eq 1 ]; then
			chosen_station_config="${station_configs[0]}"
		fi

		if [ -n "$chosen_station_config" ]; then
			info "Handling source station"
			${mpdq_bin} --config "$chosen_station_config"
		fi
	fi
	

}

##############################################################entrypoint


read_arguments "$@"
read_variables
main "${@}"
