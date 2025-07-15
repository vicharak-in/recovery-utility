#!/bin/bash
# shellcheck shell=bash

__tui_file_picker() {
	local DEFAULT_FILE_PATH="$1"
	local selection FILE

	while true; do
		FILE=""
		selection=$(__tui_fselect $DEFAULT_FILE_PATH)
		ret=$?
		if [ $ret -eq 0 ]; then
			FILE=$selection
			break
		elif [ $ret -eq 2 ]; then
			__tui_msgbox "\
Use this file selection dialog to choose a file or directory.

  ▸ Use arrow keys or Tab to navigate.
  ▸ Press SPACE to select a file or directory into the input box.
  ▸ Double-press SPACE on a directory to open it.
  ▸ Once you see your desired image path in input box, press ENTER.

You can also:

  ▸ Type the full path manually in the input box.
  ▸ Navigate and pick your desired file or folder.

Press ENTER to confirm your selection."
		else
			return 1
		fi
	done

	if [ ! -n "$FILE" ]; then
		__tui_msgbox "[Error] No file selected. Aborted."
		return 1
	fi

	echo $FILE
	return 0
}
