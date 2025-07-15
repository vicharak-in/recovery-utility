# shellcheck shell=bash

RECOVERY_TUI=${RECOVERY_TUI:-"dialog"}

__check_terminal() {
	local devices=("/dev/stdin" "/dev/stdout" "/dev/stderr") output disable_stderr
	for i in "${devices[@]}"; do
		disable_stderr="2>&-"
		if [[ $i == "/dev/stderr" ]]; then
			disable_stderr=
		fi

		if output="$(eval "stty size -F '$i' $disable_stderr")"; then
			echo "$output"
			return
		fi
	done
	echo "Unable to get terminal size!" >&2
}

__tui() {
	local type="$1" text="$2" height width listheight
	shift 2
	height="$(__check_terminal | cut -d ' ' -f 1)"
	width="$(__check_terminal | cut -d ' ' -f 2)"

	height=$((height - 5))
	width=$((width - 5))

	case $type in
	--menu)
		listheight=0
		;;
	--checklist | --radiolist)
		listheight=$((height - 8))
		;;
	--gauge)
		height=10
		;;
	esac

	if ((height < 8)); then
		echo "TTY height needs to be at least 8 for TUI mode to work, currently is '$height'." >&2
		return 1
	fi

	case $type in
	--inputbox)
		$RECOVERY_TUI --title "Recovery Utility" \
			--backtitle "	Vicharak" \
			--cancel-button "Exit" "$type" "${text}" "${height}" \
			"$width" "$@" 3>&1 1>&2 2>&3 3>&-
		;;
	--fselect)
		$RECOVERY_TUI --title "Recovery Utility" \
			--backtitle "  Vicharak" \
			--help-button \
			"$type" "${text}" "${height}" \
			"$width" "$@" 3>&1 1>&2 2>&3 3>&-
		;;
	--menu)
		$RECOVERY_TUI --title "Recovery Utility" \
			--backtitle "Vicharak" \
			"${type}" "${text}" "${height}" \
			"${width}" "${listheight}" "$@" 3>&1 1>&2 2>&3 3>&-
		;;
	*)
		$RECOVERY_TUI --title "Recovery Utility" \
			--backtitle "Vicharak" \
			"${type}" "${text}" "${height}" \
			"${width}" "$@" 3>&1 1>&2 2>&3 3>&-
		;;

	esac

	return $?
}

__tui_yesno() {
	__tui --yesno "$@"
	return $?
}

__tui_msgbox() {
	__tui --msgbox "$@"
	return $?
}

__tui_inputbox() {
	__tui --inputbox "$@"
	return $?
}

__tui_menu() {
	__tui --menu "$@"
	return $?
}

__tui_radiolist() {
	__tui --radiolist "$@"
	return $?
}

__tui_fselect() {
	__tui --fselect "$@"
	return $?
}

__tui_gauge() {
	__tui --gauge "$@"
}
