#!/bin/bash
# shellcheck shell=bash

# Main project directory, resolved relative to script location
PROJECT_MAIN_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.."

# Source utility scripts
source "${PROJECT_MAIN_DIR}/utils/tui.sh"
source "${PROJECT_MAIN_DIR}/utils/filepicker.sh"

# Lists block devices and formats output for user selection
_get_block_devices() {
	local tmpInfo=$(mktemp /tmp/recovery-utility.XXXXX)
	lsblk -o NAME,FSTYPE,LABEL,SIZE,MOUNTPOINT >$tmpInfo

	local i=0
	local SPACES='                                                                 '
	local DoHeading=true
	AllPartsArr=()

	while read -r Line; do
		if [ "$DoHeading" == "true" ]; then
			DoHeading=false
			MenuText="$Line"
			FSTYPE_col="${Line%%FSTYPE*}"
			FSTYPE_col="${#FSTYPE_col}"
			MOUNTPOINT_col="${Line%%MOUNTPOINT*}"
			MOUNTPOINT_col="${#MOUNTPOINT_col}"
			continue
		fi

		Line="$Line$SPACES"
		Line=${Line:0:74}

		#AllPartsArr+=($i "$Line")
		AllPartsArr+=("$Line" "")

		((i++))
	done <$tmpInfo

	# Clean up temp file unless in debug mode
	[ "${DEBUG,,}" != "true" ] && rm -f "$temp_file"
}

# Mounts a block device and returns its mount point
_parse_mount_block_device() {
	local input=$1
	local mount_point temp_mount="/tmp/recovery-utility-mp" result

	# Check if device is already mounted
	if [[ "${input:MOUNTPOINT_col:4}" != "    " ]]; then
		mount_point="${input:MOUNTPOINT_col:999}"
		mount_point="${mount_point%% *}"
	else
		# Extract device and filesystem type
		local device="${input%% *}"
		device=/dev/"${device:2:999}"

		local fs_type="${input:FSTYPE_col:999}"
		fs_type="${fs_type%% *}"

		mkdir -p "$temp_mount"
		result=$(mount -t "$fs_type" "$device" "$temp_mount" 2>&1)
		if [ $? -eq 0 ]; then
			mount_point="$temp_mount"
		else
			echo "$result"
			return 1
		fi
	fi

	echo "$mount_point"
	return 0
}

# Allows user to select an image file from a local storage device
_tui_get_local_image() {
	local selection mount_point file_path result return_code=1

	while true; do
		local mountpoint="/tmp/recovery-utility-mp"
		if mountpoint -q $mountpoint; then
			umount "$mountpoint"
		fi

		# get an array of partition of every device
		_get_block_devices

		selection=$(__tui_menu "Select a storage device to browse for image files:" \
			"${AllPartsArr[@]}")

		[ $? -ne 0 ] && break

		# Parse the selection and mount block device on mountpoint
		mount_point=$(_parse_mount_block_device "$selection")
		if [ $? -ne 0 ]; then
			__tui_msgbox "Error: Failed to mount device:\n${mount_point}"
			continue
		fi

		while true; do
			file_path=$(__tui_file_picker "${mount_point}")
			return_code=$?

			if [ $return_code -eq 0 ]; then
				image_path="$file_path"
				if __tui_yesno "You selected:\n\n    $image_path\n\nProceed with this image?"; then
					break
				fi
			else
				break
			fi
		done

		[ $return_code -ne 0 ] && continue

		echo "$image_path"
		return 0
	done
	return 1
}

# Allows user to select a target drive for flashing
_tui_select_flash_to_drive() {
	local temp_file
	temp_file=$(mktemp /tmp/recovery-utility.XXXXX)
	lsblk -d -o NAME,MODEL --noheadings >"$temp_file"

	local BlockArr=()
	while read -r line; do
		BlockArr+=("/dev/${line}" "")
	done <"$temp_file"

	rm -f "$temp_file"

	while true; do
		local selection=$(__tui_menu "Select target drive for flashing:" \
			"${BlockArr[@]}")

		case "${selection}" in
		/dev*)
			local block_device
			block_device=$(echo "$selection" | awk '{print $1}')
			if __tui_yesno "Confirm flashing to this device:\n\n    ${block_device}\n\nWARNING: This will erase all data on the selected drive!"; then
				echo "$block_device"
				return 0
			fi
			;;
		*)
			return 1
			;;
		esac
	done
}

_tui_flash_image() {
	local image_path=$1
	local flash_device=$2
	local mountpoint="/tmp/recovery-utility-mp"

	if __tui_yesno "\
You are about to flash the following image:

    ${image_path}

onto the target device:

    ${flash_device}

⚠️ WARNING: This will erase **all data** on the selected drive.

Please ensure:
  - The device remains powered during flashing.
  - You are flashing the correct target device.

⚠️ An interrupted flash may leave the system in an inconsistent state.
(Flashing into slower devices such USB 2.0 may take longer)

In case something goes wrong, don't panic —
you can recover the device using the *upgrade_tool*.

For recovery instructions, visit:
  https://docs.vicharak.in/vicharak_sbcs/axon/axon-linux/linux-usage-guide/

Do you want to proceed?"; then
		echo "Do nothing!"
	else
		# User cancelled — optionally log or return
		return 1
	fi

	local mountdevice=$(
		lsblk -no PKNAME "$(findmnt -nvo SOURCE ${mountpoint})" | sed 's|^|/dev/|'
	)

	if [ "${mountdevice}" == "${flash_device}" ]; then
		if [ "${flash_device}" == "/dev/mmcblk0" ]; then
			echo "Do something"
		else
			__tui_msgbox "You aren't supposed to flash into the same device where you have your image. Are you? Flashing Aborted!"
			return 0
		fi
	fi

	# Extract and validate .img file from tar.gz archive
	local target_dir=/var/tmp/recovery-utility-dir/
	mkdir -p "${target_dir}"
	rm -rf "${target_dir}"/*

	( 
		(
			tar xvzf "$image_path" -C "$target_dir" &>/tmp/recovery-utility-tar.log
			echo $? >/tmp/recovery-utility-tar.ret
		) &
		tar_pid=$!

		progress=1
		while kill -0 $tar_pid 2>/dev/null; do
			progress=$(((progress % 70) + 1))
			echo "$progress"
			echo "# Extracting image..."
			sleep 2
		done

		wait $tar_pid

		if [ "$(cat /tmp/recovery-utility-tar.ret)" != "0" ]; then
			echo "0"
			echo "# Extraction failed"
			sleep 1
			exit 1
		fi

		echo "50"
		echo "# Image extracted successfully!"
		sleep 0.5
	) | __tui_gauge "Extracting Image..."

	if [ "$(cat /tmp/recovery-utility-tar.ret)" != "0" ]; then
		__tui_msgbox "[Error] Failed to extract image.\n\n$(cat /tmp/recovery-utility-tar.log)"
		return 1
	fi

	image_path=$(ls "${target_dir}"*.img 2>/dev/null)
	if [ $? -ne 0 ]; then
		__tui_msgbox "Error: No valid .img file found in the archive!"
		return 1
	fi

	# TODO: Copy it first to ram? our root? {maybe a trigger from user to switch into intramfs and flash emmc directly form userspace}o
	# TODO: Add feature for emmc to flash new image into it from live system
	# TODO: Special case to handle, when user wants to flash into drive where images resides

	if [ "pikaa" == "$(hostname)" ]; then
		__tui_msgbox "Are you trying to flash your own PC? heartbreak? you ok?"
		image_path=/dev/zero
		flash_device=/tmp/zero.img
	fi

	(
		(
			if [ "pikaa" == "$(hostname)" ]; then
				dd if="$image_path" of="$flash_device" count=100  bs=4M status=none conv=fsync &>/tmp/recovery-utility-dd.log
			else
				dd if="$image_path" of="$flash_device"  bs=4M status=none conv=fsync &>/tmp/recovery-utility-dd.log
			fi
			echo $? >/tmp/recovery-utility-dd.ret
			sync
		) &

		dd_pid=$!
		progress=51
		while kill -0 $dd_pid 2>/dev/null; do
			progress=$(((progress % 98) + 1))
			[ $progress -lt 51 ] && progress=51
			echo "$progress"
			echo "# Flashing image... Please wait."
			sleep 2
		done

		wait $dd_pid

		if [ "$(cat /tmp/recovery-utility-dd.ret)" != "0" ]; then
			echo "99"
			echo "# Flashing failed."
			sleep 1
			exit 1
		fi

		echo "100"
		echo "# Done flashing image!"
		sleep 1
	) | __tui_gauge "Flashing Image..."

	if [ "$(cat /tmp/recovery-utility-dd.ret)" != "0" ]; then
		__tui_msgbox "[Error] Failed to flash image.\n\n$(cat /tmp/recovery-utility-dd.log)"
		return 1
	else
		__tui_msgbox "Successfully flashed image! Existing..."
	fi

	return 0
}

# Main function to handle OS image flashing process
tui_flashos() {
	local selection flash_device image_path

	while true; do
		selection=$(__tui_menu "Select image source:" \
			"Local Storage Device" "Browse a connected storage device" \
			"Download from Server" "Download an image from a remote server")

		case "$selection" in
		"Local"*)
			while true; do
				local ret
				flash_device=$(_tui_select_flash_to_drive)
				ret=$?
				if [ $ret -eq 1 ]; then
					break
				elif [ $ret -ne 0 ]; then
					__tui_msgbox "Error: No target drive selected!"
					break
				fi

				while true; do
					image_path=$(_tui_get_local_image)
					local ret=$?
					if [ $ret -eq 1 ]; then
						break
					elif [ $ret -ne 0 ]; then
						__tui_msgbox "Error: Failed to select a valid image!"
						break
					fi

					local res=$(_tui_flash_image $image_path $flash_device)
					if [ $? -ne 0 ]; then
						continue
					else
						return 0
					fi
				done
			done
			;;

		"Download"*)
			flash_device=$(_tui_select_flash_to_drive)
			if [ $? -ne 0 ]; then
				__tui_msgbox "Error: No target drive selected!"
				return 1
			fi

			image_path=$(_tui_get_download_image)
			if [ $? -ne 0 ]; then
				__tui_msgbox "Error: Failed to download image!"
				return 1
			fi
			;;

		*)
			break
			;;

		esac
	done
}

# Run main function in debug mode
if [[ "${DEBUG,,}" = "true" ]]; then
	tui_flashos
fi
