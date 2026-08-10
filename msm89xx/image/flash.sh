#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Flash OpenWrt to MSM8916 UZ801 devices entirely via EDL.
# This version is designed for the case where eMMC is empty / unusable
# and critical radio partitions are supplied from a local backup.
#
# Prerequisites: edl tool[](https://github.com/bkerler/edl)
# Usage: run from the build output directory (bin/targets/msm89xx/msm8916/)
#
# Expected local backup structure (relative to project root):
#   stock-firmware-extract/radio/
#       fsc.bin
#       fsg.bin
#       modemst1.bin
#       modemst2.bin

set -euo pipefail

# Must match TOT_SECTORS in generate_squashfs_gpt.sh
TOT_SECTORS=7569408

# Temporary directories - cleaned up on exit
firmware_tmp=""
gpt_tmp=""
trap 'rm -rf "$firmware_tmp" "$gpt_tmp"' EXIT

find_image() {
    local dir="$1" pattern="$2" file
    file=$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | head -n 1 || true)
    if [[ -z "${file:-}" ]]; then
        echo "[-] Error: Image not found with pattern: $pattern" >&2
        return 1
    fi
    echo "$file"
}

echo "=== OpenWrt MSM8916 EDL Flash Script (backup-based) ==="
echo

# -------------------------------------------------------
# 1. Detect OpenWrt images
# -------------------------------------------------------
echo "[*] Detecting OpenWrt images..."
gpt_path=$(find_image "." "*-squashfs-gpt_both0.bin") || exit 1
boot_path=$(find_image "." "*-squashfs-boot.img")     || exit 1
rootfs_path=$(find_image "." "*-squashfs-system.img") || exit 1

echo "[+] GPT:    $(basename "$gpt_path")"
echo "[+] Boot:   $(basename "$boot_path")"
echo "[+] Rootfs: $(basename "$rootfs_path")"

# -------------------------------------------------------
# 2. Detect firmware ZIP (aboot/hyp/rpm/sbl1/tz)
# -------------------------------------------------------
echo
echo "=== Firmware bundle (.zip) ==="
zip_path="$(find_image "." "*-firmware.zip" || true)"

if [[ -n "${zip_path:-}" ]]; then
    echo "[*] Found firmware ZIP: $(basename "$zip_path")"
    firmware_tmp="$(mktemp -d)"
    echo "[*] Extracting .mbn files..."
    unzip -q -j -d "$firmware_tmp" "$zip_path" "*.mbn" || {
        echo "[-] Error: Failed to extract .mbn files from ZIP"
        exit 1
    }
    firmware_dir="$firmware_tmp"
else
    echo "[!] No firmware ZIP found in the current directory"
    echo "=== Qualcomm Firmware Directory (fallback) ==="
    read -e -r -p "Drag the folder with .mbn files (aboot, hyp, rpm, sbl1, tz): " firmware_dir
    firmware_dir="${firmware_dir//\"/}"
    firmware_dir="${firmware_dir//\'/}"
    firmware_dir="${firmware_dir%"${firmware_dir##*[![:space:]]}"}"
fi

if [[ -z "$firmware_dir" || ! -d "$firmware_dir" ]]; then
    echo "[-] Error: Invalid firmware directory: $firmware_dir"
    exit 1
fi

echo "[*] Using firmware directory: $firmware_dir"
echo

# Verify required .mbn files
echo "[*] Verifying firmware partitions..."
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
    echo "[-] ERROR: Missing required .mbn files."
    exit 1
fi

# -------------------------------------------------------
# 3. Locate local radio backup (fsc/fsg/modemst*)
# -------------------------------------------------------
echo
echo "=== Local radio backup ==="

RADIO_DIR=""

# Try several relative locations (depending on where the script is run from)
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
    echo "[-] Error: stock-firmware-extract/radio directory not found"
    echo "    Please make sure the following files exist:"
    echo "      stock-firmware-extract/radio/fsc.bin"
    echo "      stock-firmware-extract/radio/fsg.bin"
    echo "      stock-firmware-extract/radio/modemst1.bin"
    echo "      stock-firmware-extract/radio/modemst2.bin"
    exit 1
fi

echo "[*] Using radio backup from: $RADIO_DIR"

for n in fsc fsg modemst1 modemst2; do
    if [[ ! -f "$RADIO_DIR/$n.bin" ]]; then
        echo "[-] Missing required file: $RADIO_DIR/$n.bin"
        exit 1
    fi
    echo "[+] Found $n.bin"
done

# -------------------------------------------------------
# 4. Final confirmation
# -------------------------------------------------------
echo
read -r -p "Continue with flashing? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "[!] Cancelled"
    exit 0
fi

# -------------------------------------------------------
# 5. Flash new GPT
# -------------------------------------------------------
echo
echo "=== Flashing GPT (EDL) ==="
gpt_tmp="$(mktemp -d)"

# gpt_both0.bin layout: [34 sectors primary] [32 sectors backup entries] [1 sector backup header]
dd if="$gpt_path" bs=512 count=34         of="${gpt_tmp}/primary.bin"        2>/dev/null
dd if="$gpt_path" bs=512 skip=34 count=32 of="${gpt_tmp}/backup_entries.bin" 2>/dev/null
dd if="$gpt_path" bs=512 skip=66 count=1  of="${gpt_tmp}/backup_header.bin"  2>/dev/null

edl ws 0                      "${gpt_tmp}/primary.bin"        || { echo "[-] Error flashing primary GPT"; exit 1; }
edl ws $((TOT_SECTORS - 33)) "${gpt_tmp}/backup_entries.bin" || { echo "[-] Error flashing GPT backup entries"; exit 1; }
edl ws $((TOT_SECTORS - 1))  "${gpt_tmp}/backup_header.bin"  || { echo "[-] Error flashing GPT backup header"; exit 1; }

# -------------------------------------------------------
# 6. Flash bootloader + OpenWrt images
# -------------------------------------------------------
echo
echo "=== Flashing Firmware + OpenWrt images (EDL) ==="
edl w aboot  "$firmware_dir/aboot.mbn" || { echo "[-] Error flashing aboot";  exit 1; }
edl w hyp    "$firmware_dir/hyp.mbn"   || { echo "[-] Error flashing hyp";    exit 1; }
edl w rpm    "$firmware_dir/rpm.mbn"   || { echo "[-] Error flashing rpm";    exit 1; }
edl w sbl1   "$firmware_dir/sbl1.mbn"  || { echo "[-] Error flashing sbl1";   exit 1; }
edl w tz     "$firmware_dir/tz.mbn"    || { echo "[-] Error flashing tz";     exit 1; }
edl w boot   "$boot_path"              || { echo "[-] Error flashing boot";   exit 1; }
edl w rootfs "$rootfs_path"            || { echo "[-] Error flashing rootfs"; exit 1; }
edl e rootfs_data                      || { echo "[-] Error erasing rootfs_data"; exit 1; }

# -------------------------------------------------------
# 7. Restore critical radio partitions from local backup
# -------------------------------------------------------
echo
echo "=== Restoring radio partitions (from local backup) ==="
for n in fsc fsg modemst1 modemst2; do
    echo "[*] Writing $n ..."
    edl w "$n" "$RADIO_DIR/$n.bin" || { echo "[-] Error writing $n"; exit 1; }
done

# -------------------------------------------------------
# 8. Done
# -------------------------------------------------------
echo
echo "[+] Flash completed successfully"
echo "[*] Rebooting device..."
edl reset || { echo "[-] Error resetting device"; exit 1; }

echo
echo "Device should now boot into OpenWrt."
echo "Firmware blobs are already included in the image (base-files)."
echo "Radio/NV data restored from your local backup."