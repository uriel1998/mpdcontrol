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
ADDMODE_SET_BY_ARG="0"
EMIT_MODE=""
INPUT_JSON=""
INPUT_SET="0"
INPUT_SOURCE=""
INPUT_PAYLOAD=""
PREVIEW_RECORD=""
LIMIT=""
SHUFFLE="0"
host_arg=""
LOUD="0"
FZF_LINES=()
RECORD_SEP=$'\x1f'

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

function append_record() {
	FZF_LINES+=("$1${RECORD_SEP}$2${RECORD_SEP}$3${RECORD_SEP}$4")
}

function append_dup_records() {
	local icon="$1"
	local source="$2"
	local line=""
	while IFS= read -r line; do
		if [ -n "$line" ]; then
			append_record "$icon" "$source" "$line" "$line"
		fi
	done
}

function emit_fzf_display_lines() {
	local record=""
	local icon=""
	local source=""
	local title=""
	local payload=""
	while IFS= read -r record; do
		if [ -z "$record" ]; then
			continue
		fi
		IFS="$RECORD_SEP" read -r icon source title payload <<< "$record"
		printf '%s - %s\t%s\n' "$icon" "$title" "$record"
	done
}

function emit_raw_lines() {
	printf '%s\n' "${FZF_LINES[@]}"
}

function emit_json_lines() {
	local record=""
	local icon=""
	local source=""
	local title=""
	local payload=""
	for record in "${FZF_LINES[@]}"; do
		if [ -z "$record" ]; then
			continue
		fi
		IFS="$RECORD_SEP" read -r icon source title payload <<< "$record"
		${jq_bin} -cn \
			--arg icon "$icon" \
			--arg source "$source" \
			--arg title "$title" \
			--arg payload "$payload" \
			'{icon:$icon,source:$source,title:$title,payload:$payload}'
	done
}

function parse_input_json() {
	local input_source=""
	local input_payload=""

	if IFS=$'\t' read -r input_source input_payload < <(${jq_bin} -er '[.source, .payload] | @tsv' <<< "$INPUT_JSON" 2>/dev/null); then
		:
	else
		input_source="$INPUT_SOURCE"
		input_payload="$INPUT_PAYLOAD"
	fi

	if [ -z "$input_source" ]; then
		error "Missing source in --input"
		exit 1
	fi

	if [ -z "$input_payload" ]; then
		error "Missing payload in --input"
		exit 1
	fi

	append_record "" "$input_source" "$input_payload" "$input_payload"
}

function process_selection_result() {
	local fzf_result="$1"
	local result_line=""
	local source=""
	local payload=""
	local chosen_station_config=""
	local play_after_add="0"
	local -a station_configs=()

	if [ -z "$fzf_result" ];then
		return 0
	fi

	info "Selection made; processing results"
	clearmode

	# first pass: process everything except station selections
	while IFS= read -r result_line; do
		if [ -z "$result_line" ]; then
			continue
		fi

		IFS="$RECORD_SEP" read -r _icon source _title payload <<< "$result_line"

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
				add_matching_paths genre "$payload"
				if [[ "${ADDMODE}" == "1" ]];then
					mpc_action shuffle
				fi
				play_after_add="1"
				;;
			album)
				info "Handling source ${source}"
				add_matching_paths album "$payload"
				mpc_action random off
				play_after_add="1"
				;;
			artist)
				info "Handling source ${source}"
				add_matching_paths albumartist "$payload"
				if [[ "${ADDMODE}" == "1" ]];then
					mpc_action shuffle
				fi
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
}

function add_matching_paths() {
	local tag_name="$1"
	local tag_value="$2"
	local match_path=""

	if [ "$SHUFFLE" -eq 0 ] && [ -z "$LIMIT" ]; then
		mpc_action findadd "$tag_name" "$tag_value"
		return 0
	fi

	while IFS= read -r match_path; do
		if [ -n "$match_path" ]; then
			mpc_action add "$match_path"
		fi
	done < <(
		${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" find "$tag_name" "$tag_value" |
		if [ "$SHUFFLE" -eq 1 ]; then
			shuf
		else
			cat
		fi |
		if [ -n "$LIMIT" ]; then
			head -n "$LIMIT"
		else
			cat
		fi
	)
}

function show_preview_record() {
	local record="$1"
	local icon=""
	local source=""
	local title=""
	local payload=""

	if [ -z "$record" ]; then
		return 0
	fi

	IFS="$RECORD_SEP" read -r icon source title payload <<< "$record"

	case "$source" in
		album)
			${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" --format '%track% %title%' find album "$payload"
			;;
		artist)
			${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list album albumartist "$payload"
			;;
		genre)
			${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list album genre "$payload"
			;;
		playlist)
			${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" playlist "$payload"
			;;
		station)
			if [ -f "$payload" ]; then
				cat "$payload"
			else
				printf '%s\n' "$payload"
			fi
			;;
		radio)
			printf '%s\n' "$payload"
			;;
	esac
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
  --station, --stations    Include mpdq station configs
  --listentodi             Include .pls radio entries from DI_PLS_DIR
  --radiotray              Include radiotray-ng bookmarks
  --genre                  Include MPD genres
  --artist                 Include MPD album artists
  --album                  Include MPD albums
  --all                    Include all supported sources

Mode Options:
  --append                 Append selections without clearing or cropping
  --clear                  Clear playlist before adding selections
  --crop                   Crop playlist before adding selections, with bumper logic
  --limit NUMBER           For genre and artist, add only NUMBER matching entries
  --shuffle                For genre, artist, and album, shuffle tracks before adding
  --loud                   Enable informational logging and non-quiet mpc actions

Config Options:
  --playlist-dir PATH      Override DI_PLS_DIR for --listentodi

Help:
  -e, --emit               Emit the would-be fzf option display list to stdout and exit
  -i, --input JSON         Use one JSON source/payload input and skip source selection
  --emit-raw               Emit raw internal records to stdout and exit
  --emit-json              Emit JSON lines to stdout and exit
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
	    if [ "$ADDMODE_SET_BY_ARG" -ne 1 ];then
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
	# --station/--stations -> include stations from mpdq
	# --listentodi -> include playlists from DI_PLS_DIR
	# --radiotray -> include from radiotray
	# --genre -> include genres
	# --artist -> include album artists
	# --album -> include albums
	# --all -> include all, appends string for all to INCLUDE SOURCES
	
	# --playlist-dir -> specify DI_PLS_DIR
	while [ $# -gt 0 ]; do
					case "$1" in
						-e|--emit)
							EMIT_MODE="display"
							;;
						--preview-record)
							shift
							if [ -z "$1" ]; then
								error "Missing argument for --preview-record"
								exit 1
							fi
							PREVIEW_RECORD="$1"
							;;
						-i|--input)
							if [ "$INPUT_SET" -eq 1 ]; then
								error "Only one --input value is allowed per run"
								exit 1
							fi
							shift
							if [ -z "$1" ]; then
								error "Missing argument for --input"
								exit 1
							fi
							INPUT_JSON="$1"
							if [[ "$1" == source:* ]]; then
								INPUT_SOURCE="${1#source:}"
								shift
								if [ -z "$1" ] || [[ "$1" != payload:* ]]; then
									error "Expected payload:... after source:... for --input"
									exit 1
								fi
								INPUT_PAYLOAD="${1#payload:}"
								INPUT_JSON=""
							fi
							INPUT_SET=1
							;;
						--emit-raw)
							EMIT_MODE="raw"
							;;
					--emit-json)
						EMIT_MODE="json"
						;;
					-h|--help)
						show_help
						exit 0
					;;
				--append)
					ADDMODE=0
					ADDMODE_SET_BY_ARG=1
					;;
				--clear)
					ADDMODE=1
					ADDMODE_SET_BY_ARG=1
					;;
				--crop)
					ADDMODE=2
					ADDMODE_SET_BY_ARG=1
					;;
				--limit)
					shift
					if [ -z "$1" ]; then
						error "Missing argument for --limit"
						exit 1
					fi
					if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ]; then
						error "Invalid value for --limit: $1"
						exit 1
					fi
					LIMIT="$1"
					;;
				--shuffle)
					SHUFFLE=1
					;;
				--loud)
					LOUD=1
					;;
				--playlist|--playlists)
					INCLUDE_SOURCES="${INCLUDE_SOURCES}playlists "
					;;
			--station|--stations)
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
			info "Doing nothing to crop"
			;;
		*)
			warn "Unknown ADDMODE '$ADDMODE'; defaulting to add mode."
			;;
	esac
}
    
 
main (){
	FZF_LINES=()
	local fzf_result=""
	#all of these need to be stored in a single data format
	#icon<sep>source<sep>title<sep>full specification (url, text file to select on, whatever)

	if [ -n "$PREVIEW_RECORD" ]; then
		show_preview_record "$PREVIEW_RECORD"
		return 0
	fi

	if [ "$INPUT_SET" -eq 1 ]; then
		parse_input_json
	elif [[ "${INCLUDE_SOURCES}" == *"playlists"* ]];then
		# get playlists  
		append_dup_records "📋" "playlist" < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" lsplaylists)
	fi
	if [ "$INPUT_SET" -ne 1 ] && [[ "${INCLUDE_SOURCES}" == *"stations"* ]];then
		# get stations  
		while IFS= read -r station_path; do
			if [ -z "$station_path" ]; then
				continue
			fi
			station_name=$(basename "$station_path")
			station_name="${station_name%.cfg}"
			append_record "🎛️" "station" "$station_name" "$station_path"
		done < <(${mpdq_bin} -e | sed -n '/\/default[^/]*\.cfg$/d; p')
	fi
	if [ "$INPUT_SET" -ne 1 ] && [[ "${INCLUDE_SOURCES}" == *"listentodi"* ]];then
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
								append_record "📡" "radio" "$title" "$url"
							fi
							done < "$pls_file"
					done
				fi
	fi
	if [ "$INPUT_SET" -ne 1 ] && [[ "${INCLUDE_SOURCES}" == *"radiotray"* ]];then	
		# get webradio presets from radiotray (functionally equivalent to listen to di here)
		if [ -f "${XDG_CONFIG_HOME}/radiotray-ng/bookmarks.json" ];then
			while IFS=$'\t' read -r title url; do
				if [ -n "$title" ] || [ -n "$url" ]; then
					append_record "📻" "radio" "$title" "$url"
				fi
			done < <(${jq_bin} -r '
				.[]
				| .stations[]
				| [.name, .url]
				| @tsv
			' "${XDG_CONFIG_HOME}/radiotray-ng/bookmarks.json")
			# TODO MAKE THE VARIABLE WITH STATION EMJOI
		fi
	fi	
	if [ "$INPUT_SET" -ne 1 ] && [[ "${INCLUDE_SOURCES}" == *"genre"* ]];then
		# get genre 🎼
		append_dup_records "🎼" "genre" < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list genre)
	fi
	if [ "$INPUT_SET" -ne 1 ] && [[ "${INCLUDE_SOURCES}" == *"artist"* ]];then
		# get albumartist  🎸
		append_dup_records "🎸" "artist" < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list albumartist)
	fi
	if [ "$INPUT_SET" -ne 1 ] && [[ "${INCLUDE_SOURCES}" == *"album"* ]];then
		# get album 💿  (present as album by AlbumArtist)
		append_dup_records "💿" "album" < <(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" list album)
	fi


		# present in big ass scrollable list
		# throw into fzf
		if [ ${#FZF_LINES[@]} -gt 0 ]; then
			info "Built ${#FZF_LINES[@]} selectable entries"
			case "$EMIT_MODE" in
				display)
					printf '%s\n' "${FZF_LINES[@]}" |
						emit_fzf_display_lines |
						cut -f1
					return 0
					;;
				raw)
					emit_raw_lines
					return 0
					;;
				json)
					emit_json_lines
					return 0
					;;
			esac
			if [ "$INPUT_SET" -eq 1 ]; then
				fzf_result="${FZF_LINES[0]}"
			else
				fzf_result=$(printf '%s\n' "${FZF_LINES[@]}" |
					emit_fzf_display_lines |
					${fzf_bin} --exact --delimiter=$'\t' --with-nth=1 --multi \
						--preview "${SCRIPT_DIR}/mpdcontrol.sh --preview-record {2}" \
						--preview-window=right,60%,wrap |
					cut -f2-)
			fi
	fi

	process_selection_result "$fzf_result"
	

}

##############################################################entrypoint


read_arguments "$@"
read_variables
main "${@}"
