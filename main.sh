#!/bin/bash
# shellcheck shell=bash

# Must run as root
if [[ $(id -u) -ne 0 ]]; then
	echo "Usage: sudo $0"
	exit 1
fi

PROJECT_MAIN_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

#shellcheck "${PROJECT_MAIN_DIR}/utils/dialog.sh"
source "${PROJECT_MAIN_DIR}/utils/tui.sh"

#shellcheck "${PROJECT_MAIN_DIR}/pages/flashos.sh"
source "${PROJECT_MAIN_DIR}/pages/flashos.sh"

# Display main recovery menu

start_menu() {
	local selection
	selection=$(
		__tui_menu "Recovery Menu:" \
			"Flash OS" "   Flash a new OS image to board" \
			"Configure Network" "   Configure network connection" \
			"Console" "   Enter recovery command line console"
	)

	case $selection in
	"Flash OS")
		tui_flashos
		start_menu
		;;
	*) ;;

	esac
}

start_menu
