#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Flash OpenWrt to MSM8916 UZ801 devices entirely via EDL.
#
# This version is designed for devices where:
# - eMMC may be empty / unusable
# - critical radio partitions come from a local backup
# - rootfs_data handling must be explicitly selected by the user
#
# rootfs_data modes:
#   1) Keep current rootfs_data
#   2) Backup + Restore rootfs_data
#   3) Erase/Recreate rootfs_data
#   4) Backup rootfs_data only
#   5) Abort
#
# IMPORTANT:
# "Erase/Recreate" does NOT use "edl e rootfs_data".
# Instead, it invalidates the existing filesystem by zeroing the first
# 4096 bytes of the partition. OpenWrt preinit then detects the missing
# ext4 magic and recreates the filesystem using 79-format-rootfs-data.

set -euo pipefail

# -------------------------------------------------------
# Hardware / GPT constants
# -------------------------------------------------------

TOT_SECTORS=7569408

# Must match generate_squashfs_gpt.sh
ROOTFS_DATA_START=610338
ROOTFS_DATA_SECTORS=6959037
ROOTFS_DATA_BYTES=$((ROOTFS_DATA_SECTORS * 512))

# 8 sectors = 4096 bytes.
# This covers the beginning of the ext4 filesystem including the
# primary superblock location (1024 bytes from the partition start).
ROOTFS_DATA_INVALIDATE_SECTORS=8

# -------------------------------------------------------
# Temporary directories
# -------------------------------------------------------

firmware_tmp=""
gpt_tmp=""

cleanup() {
    rm -rf "${firmware_tmp:-}" "${gpt_tmp:-}"
}

trap cleanup EXIT

# -------------------------------------------------------
# Utility functions
# -------------------------------------------------------

find_image() {
    local dir="$1"
    local pattern="$2"
    local file

    file=$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | head -n 1 || true)

    if [[ -z "${file:-}" ]]; then
        echo "[-] Error: Image not found with pattern: $pattern" >&2
        return 1
    fi

    echo "$file"
}

abort() {
    echo
    echo "[-] $1"
    echo
    exit 1
}

# -------------------------------------------------------
# Start
# -------------------------------------------------------

echo
echo "======================================================"
echo " OpenWrt MSM8916 UZ801 EDL Flash Script"
echo " backup-based / configurable rootfs_data handling"
echo "======================================================"
echo

# -------------------------------------------------------
# 1. Detect OpenWrt images
# -------------------------------------------------------

echo "=== Detecting OpenWrt images ==="

gpt_path=$(find_image "." "*-squashfs-gpt_both0.bin") || exit 1
boot_path=$(find_image "." "*-squashfs-boot.img") || exit 1
rootfs_path=$(find_image "." "*-squashfs-system.img") || exit 1

echo "[+] GPT:    $(basename "$gpt_path")"
echo "[+] Boot:   $(basename "$boot_path")"
echo "[+] Rootfs: $(basename "$rootfs_path")"

# -------------------------------------------------------
# 2. Detect firmware ZIP
# -------------------------------------------------------

echo
echo "=== Firmware bundle (.zip) ==="

zip_path="$(find_image "." "*-firmware.zip" || true)"

if [[ -n "${zip_path:-}" ]]; then

    echo "[+] Found firmware ZIP: $(basename "$zip_path")"

    firmware_tmp="$(mktemp -d)"

    echo "[*] Extracting .mbn files..."

    unzip -q -j -d "$firmware_tmp" "$zip_path" "*.mbn" || {
        abort "Failed to extract .mbn files from firmware ZIP"
    }

    firmware_dir="$firmware_tmp"

else

    echo "[!] No firmware ZIP found in the current directory"
    echo
    echo "=== Qualcomm Firmware Directory (fallback) ==="

    read -e -r -p \
        "Drag the folder containing aboot/hyp/rpm/sbl1/tz .mbn files: " \
        firmware_dir

    firmware_dir="${firmware_dir//\"/}"
    firmware_dir="${firmware_dir//\'/}"
    firmware_dir="${firmware_dir%"${firmware_dir##*[![:space:]]}"}"
fi

if [[ -z "${firmware_dir:-}" || ! -d "$firmware_dir" ]]; then
    abort "Invalid firmware directory: ${firmware_dir:-<empty>}"
fi

echo "[+] Using firmware directory: $firmware_dir"

# -------------------------------------------------------
# 3. Verify firmware files
# -------------------------------------------------------

echo
echo "=== Verifying firmware partitions ==="

missing_mbn=false

for part in aboot hyp rpm sbl1 tz; do
    if [[ ! -f "$firmware_dir/${part}.mbn" ]]; then
        echo "[-] ${part}.mbn not found"
        missing_mbn=true
    else
        echo "[+] ${part}.mbn"
    fi
done

if [[ "$missing_mbn" == true ]]; then
    abort "Missing required .mbn files"
fi

# -------------------------------------------------------
# 4. Locate local radio backup
# -------------------------------------------------------

echo
echo "=== Local radio backup ==="

RADIO_DIR=""

CANDIDATES=(
    "./stock-firmware-extract/radio"
    "../stock-firmware-extract/radio"
    "../../stock-firmware-extract/radio"
    "../../../stock-firmware-extract/radio"
    "../../../../stock-firmware-extract/radio"
)

for cand in "${CANDIDATES[@]}"; do
    if [[ -d "$cand" ]]; then
        RADIO_DIR="$cand"
        break
    fi
done

if [[ -z "$RADIO_DIR" ]]; then
    abort "stock-firmware-extract/radio directory not found"
fi

echo "[+] Using radio backup from: $RADIO_DIR"

for n in fsc fsg modemst1 modemst2; do
    if [[ ! -f "$RADIO_DIR/$n.bin" ]]; then
        abort "Missing required radio file: $RADIO_DIR/$n.bin"
    fi

    echo "[+] Found $n.bin"
done

# -------------------------------------------------------
# 5. rootfs_data handling selection
# -------------------------------------------------------

echo
echo "======================================================"
echo " rootfs_data handling"
echo "======================================================"
echo
echo "Partition:"
echo "  rootfs_data"
echo "  start sector : $ROOTFS_DATA_START"
echo "  sectors      : $ROOTFS_DATA_SECTORS"
echo "  size         : $ROOTFS_DATA_BYTES bytes"
echo

echo "1) Keep current rootfs_data"
echo "   - Do not modify rootfs_data."
echo "   - Existing OpenWrt settings and overlay are preserved."
echo

echo "2) Backup + Restore rootfs_data"
echo "   - Read current rootfs_data to a backup image."
echo "   - Flash the new firmware."
echo "   - Restore the backup image to rootfs_data."
echo

echo "3) Erase + Recreate rootfs_data"
echo "   - Existing rootfs_data contents will be lost."
echo "   - The partition will NOT use 'edl e rootfs_data'."
echo "   - The filesystem will be invalidated."
echo "   - OpenWrt preinit will recreate a new ext4 filesystem."
echo

echo "4) Backup rootfs_data only"
echo "   - Create a complete rootfs_data backup."
echo "   - Do not flash anything."
echo

echo "5) Abort"
echo

ROOTFS_DATA_MODE=""

while true; do
    read -r -p "Select [1-5] (default: 1): " rootfs_choice

    # Empty input = Keep
    rootfs_choice="${rootfs_choice:-1}"

    case "$rootfs_choice" in
        1)
            ROOTFS_DATA_MODE="keep"
            break
            ;;

        2)
            ROOTFS_DATA_MODE="restore"
            break
            ;;

        3)
            ROOTFS_DATA_MODE="recreate"
            break
            ;;

        4)
            ROOTFS_DATA_MODE="backup-only"
            break
            ;;

        5)
            echo
            echo "[!] Flash cancelled."
            exit 0
            ;;

        *)
            echo "[-] Invalid selection. Enter 1, 2, 3, 4 or 5."
            ;;
    esac
done

echo
echo "[+] Selected rootfs_data mode: $ROOTFS_DATA_MODE"

# -------------------------------------------------------
# 6. Backup rootfs_data if requested
# -------------------------------------------------------

ROOTFS_DATA_BACKUP=""

if [[ "$ROOTFS_DATA_MODE" == "restore" ||
      "$ROOTFS_DATA_MODE" == "backup-only" ]]; then

    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    ROOTFS_DATA_BACKUP="./rootfs_data-backup-${TIMESTAMP}.img"

    echo
    echo "=== rootfs_data backup ==="
    echo
    echo "[*] Backup file:"
    echo "    $ROOTFS_DATA_BACKUP"
    echo
    echo "[*] Expected size:"
    echo "    $ROOTFS_DATA_BYTES bytes"
    echo

    read -r -p \
        "Create this backup before continuing? (y/N): " backup_confirm

    if [[ ! "$backup_confirm" =~ ^[Yy]$ ]]; then
        echo "[!] Cancelled."
        exit 0
    fi

    echo
    echo "[*] Reading rootfs_data from device..."

    edl r rootfs_data "$ROOTFS_DATA_BACKUP" || {
        rm -f "$ROOTFS_DATA_BACKUP"
        abort "Failed to read rootfs_data"
    }

    if [[ ! -f "$ROOTFS_DATA_BACKUP" ]]; then
        abort "Backup file was not created"
    fi

    actual_size=$(stat -c '%s' "$ROOTFS_DATA_BACKUP")

    echo "[*] Backup size:"
    echo "    $actual_size bytes"

    if [[ "$actual_size" -ne "$ROOTFS_DATA_BYTES" ]]; then
        rm -f "$ROOTFS_DATA_BACKUP"

        abort \
            "rootfs_data backup size mismatch. Expected $ROOTFS_DATA_BYTES bytes, got $actual_size bytes."
    fi

    echo "[+] rootfs_data backup verified successfully."

    if [[ "$ROOTFS_DATA_MODE" == "backup-only" ]]; then
        echo
        echo "=============================================="
        echo "[+] Backup completed successfully."
        echo "=============================================="
        echo
        echo "Backup:"
        echo "  $ROOTFS_DATA_BACKUP"
        echo
        exit 0
    fi
fi

# -------------------------------------------------------
# 7. Final confirmation
# -------------------------------------------------------

echo
echo "======================================================"
echo " FLASH SUMMARY"
echo "======================================================"
echo
echo "GPT:"
echo "  $(basename "$gpt_path")"
echo
echo "Boot:"
echo "  $(basename "$boot_path")"
echo
echo "Rootfs:"
echo "  $(basename "$rootfs_path")"
echo
echo "rootfs_data mode:"
echo "  $ROOTFS_DATA_MODE"
echo

if [[ "$ROOTFS_DATA_MODE" == "restore" ]]; then
    echo "rootfs_data backup:"
    echo "  $ROOTFS_DATA_BACKUP"
    echo
fi

if [[ "$ROOTFS_DATA_MODE" == "recreate" ]]; then
    echo "WARNING:"
    echo "  Existing rootfs_data contents WILL BE LOST."
    echo "  OpenWrt will recreate the filesystem on first boot."
    echo
fi

read -r -p "Continue with flashing? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "[!] Flash cancelled."
    exit 0
fi

# -------------------------------------------------------
# 8. Flash new GPT
# -------------------------------------------------------

echo
echo "=== Flashing GPT (EDL) ==="

gpt_tmp="$(mktemp -d)"

# gpt_both0.bin layout:
#   primary header + entries
#   backup entries
#   backup header

dd \
    if="$gpt_path" \
    bs=512 \
    count=34 \
    of="${gpt_tmp}/primary.bin" \
    2>/dev/null

dd \
    if="$gpt_path" \
    bs=512 \
    skip=34 \
    count=32 \
    of="${gpt_tmp}/backup_entries.bin" \
    2>/dev/null

dd \
    if="$gpt_path" \
    bs=512 \
    skip=66 \
    count=1 \
    of="${gpt_tmp}/backup_header.bin" \
    2>/dev/null

echo "[*] Writing primary GPT..."
edl ws 0 "${gpt_tmp}/primary.bin" || {
    abort "Error flashing primary GPT"
}

echo "[*] Writing backup GPT entries..."
edl ws $((TOT_SECTORS - 33)) \
    "${gpt_tmp}/backup_entries.bin" || {
    abort "Error flashing GPT backup entries"
}

echo "[*] Writing backup GPT header..."
edl ws $((TOT_SECTORS - 1)) \
    "${gpt_tmp}/backup_header.bin" || {
    abort "Error flashing GPT backup header"
}

# -------------------------------------------------------
# 9. Flash bootloader + OpenWrt images
# -------------------------------------------------------

echo
echo "=== Flashing Firmware + OpenWrt images (EDL) ==="

echo "[*] Writing aboot..."
edl w aboot "$firmware_dir/aboot.mbn" || {
    abort "Error flashing aboot"
}

echo "[*] Writing hyp..."
edl w hyp "$firmware_dir/hyp.mbn" || {
    abort "Error flashing hyp"
}

echo "[*] Writing rpm..."
edl w rpm "$firmware_dir/rpm.mbn" || {
    abort "Error flashing rpm"
}

echo "[*] Writing sbl1..."
edl w sbl1 "$firmware_dir/sbl1.mbn" || {
    abort "Error flashing sbl1"
}

echo "[*] Writing tz..."
edl w tz "$firmware_dir/tz.mbn" || {
    abort "Error flashing tz"
}

echo "[*] Writing boot..."
edl w boot "$boot_path" || {
    abort "Error flashing boot"
}

echo "[*] Writing rootfs..."
edl w rootfs "$rootfs_path" || {
    abort "Error flashing rootfs"
}

# -------------------------------------------------------
# 10. Handle rootfs_data
# -------------------------------------------------------

echo
echo "=== Handling rootfs_data ==="

case "$ROOTFS_DATA_MODE" in

    keep)
        echo
        echo "[+] Keeping current rootfs_data unchanged."
        ;;

    restore)
        echo
        echo "[*] Restoring rootfs_data backup..."
        echo "    $ROOTFS_DATA_BACKUP"

        edl w rootfs_data "$ROOTFS_DATA_BACKUP" || {
            abort "Error restoring rootfs_data"
        }

        echo "[+] rootfs_data restored successfully."
        ;;

    recreate)
        echo
        echo "[!] Invalidating rootfs_data filesystem..."
        echo "[*] No full-partition EDL erase will be used."

        rootfs_data_invalid="${gpt_tmp}/rootfs_data_invalid.bin"

        dd \
            if=/dev/zero \
            of="$rootfs_data_invalid" \
            bs=512 \
            count="$ROOTFS_DATA_INVALIDATE_SECTORS" \
            status=none

        echo "[*] Zeroing first $ROOTFS_DATA_INVALIDATE_SECTORS sectors..."

        edl ws \
            "$ROOTFS_DATA_START" \
            "$rootfs_data_invalid" || {
            abort "Error invalidating rootfs_data"
        }

        echo
        echo "[+] rootfs_data filesystem invalidated."
        echo "[+] OpenWrt preinit will recreate it on first boot."
        ;;

    *)
        abort "Internal error: unknown rootfs_data mode: $ROOTFS_DATA_MODE"
        ;;
esac

# -------------------------------------------------------
# 11. Restore critical radio partitions
# -------------------------------------------------------

echo
echo "=== Restoring radio partitions from local backup ==="

for n in fsc fsg modemst1 modemst2; do
    echo "[*] Writing $n..."

    edl w "$n" "$RADIO_DIR/$n.bin" || {
        abort "Error writing $n"
    }

    echo "[+] $n restored."
done

# -------------------------------------------------------
# 12. Final message
# -------------------------------------------------------

echo
echo "======================================================"
echo "[+] Flash completed successfully"
echo "======================================================"
echo

if [[ "$ROOTFS_DATA_MODE" == "keep" ]]; then
    echo "[+] rootfs_data was kept unchanged."
elif [[ "$ROOTFS_DATA_MODE" == "restore" ]]; then
    echo "[+] rootfs_data backup was restored."
elif [[ "$ROOTFS_DATA_MODE" == "recreate" ]]; then
    echo "[+] rootfs_data was invalidated."
    echo "[+] OpenWrt will recreate it during first boot."
fi

echo
echo "[*] Rebooting device..."

edl reset || {
    abort "Error resetting device"
}

echo
echo "Device should now boot into OpenWrt."
echo "Firmware blobs are already included in the image."
echo "Radio/NV data was restored from the local backup."
echo
