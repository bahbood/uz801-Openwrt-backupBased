```bash
#!/bin/bash
set -e

# ============================================================
# UZ801 OpenWrt reproducible build
# Target: FY UZ801 V3 / V3.2 - MSM8916
# ============================================================

BUILD_PACKAGES_ONLY=0

if [ "$1" = "-packages" ]; then
    BUILD_PACKAGES_ONLY=1
fi

# ------------------------------------------------------------
# Fixed versions
# ------------------------------------------------------------

OPENWRT_VERSION="v25.12.5"
OPENWRT_REPO="https://git.openwrt.org/openwrt/openwrt.git"

# ------------------------------------------------------------
# Fixed dependency commits
# Kept for reproducibility / reference
# ------------------------------------------------------------

QHYPSTUB_COMMIT="fca3c513b6fb5e5b8fabae21dac1f4a5c0b51bc6"
LK2ND_COMMIT="87ccbc5a5502d4dd8183bf3a4279d90704330fb9"
QTESTSIGN_COMMIT="f3df53a5f0e37ccee076541f30f9d5b8340fc2d3"
QRTR_COMMIT="5923eea97377f4a3ed9121b358fd919e3659db7b"
RMTFS_COMMIT="586372e575f5cc1a7cbb170219ab6df98f394cae"

# ------------------------------------------------------------
# Basic checks
# ------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo "============================================================"
echo " UZ801 OpenWrt reproducible build"
echo "============================================================"
echo
echo "OpenWrt : $OPENWRT_VERSION"
echo

if [ ! -f "diffconfig_uz801" ]; then
    echo "ERROR: diffconfig_uz801 not found."
    exit 1
fi

if [ ! -d "msm89xx" ]; then
    echo "ERROR: msm89xx directory not found."
    exit 1
fi

if [ ! -d "packages" ]; then
    echo "ERROR: packages directory not found."
    exit 1
fi

if [ ! -f "apply_patches.sh" ]; then
    echo "ERROR: apply_patches.sh not found."
    exit 1
fi

# ------------------------------------------------------------
# Debian dependencies
# ------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

echo "[1/9] Installing build dependencies..."

sudo -E apt-get update -qq

sudo -E apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    flex \
    bison \
    g++ \
    gawk \
    gcc-multilib \
    g++-multilib \
    gettext \
    git \
    libncurses5-dev \
    libssl-dev \
    python3-setuptools \
    rsync \
    swig \
    unzip \
    zlib1g-dev \
    file \
    wget \
    python3-cryptography \
    mkbootimg \
    qemu-utils \
    help2man \
    xsltproc \
    bc \
    binutils \
    bzip2 \
    make \
    patch \
    time \
    device-tree-compiler \
    e2fsprogs \
    fdisk \
    util-linux \
    nano \
    perl \
    perl-modules \
    python3-dev \
    xz-utils \
    zstd \
    zip \
    libelf-dev \
    libfdt-dev \
    gcc-arm-none-eabi \
    binutils-arm-none-eabi

# ------------------------------------------------------------
# OpenWrt source
# ------------------------------------------------------------

echo
echo "[2/9] Preparing OpenWrt $OPENWRT_VERSION..."

if [ ! -d "openwrt" ]; then

    echo "Cloning OpenWrt..."

    git clone \
        --branch "$OPENWRT_VERSION" \
        --depth 1 \
        "$OPENWRT_REPO" \
        openwrt

else

    echo "OpenWrt directory already exists."

    cd openwrt

    CURRENT_VERSION="$(git describe --tags --exact-match 2>/dev/null || true)"

    if [ "$CURRENT_VERSION" != "$OPENWRT_VERSION" ]; then

        echo
        echo "ERROR:"
        echo "Existing OpenWrt source is: ${CURRENT_VERSION:-unknown}"
        echo "Expected: $OPENWRT_VERSION"
        echo
        echo "Remove the existing openwrt directory or checkout the required version manually."

        exit 1
    fi

    cd "$SCRIPT_DIR"
fi

OPENWRT_COMMIT="$(git -C openwrt rev-parse HEAD)"

echo
echo "OpenWrt commit: $OPENWRT_COMMIT"

# ------------------------------------------------------------
# Apply UZ801 patches
# ------------------------------------------------------------

echo
echo "[3/9] Applying UZ801 mac80211 patches..."

chmod +x ./apply_patches.sh

./apply_patches.sh openwrt

# ------------------------------------------------------------
# Copy target files and custom packages
# ------------------------------------------------------------

echo
echo "[4/9] Installing UZ801 target files and packages..."

# Target
mkdir -p openwrt/target/linux/msm89xx

cp -a msm89xx/. \
    openwrt/target/linux/msm89xx/

# Custom packages
rm -rf openwrt/package/custom

mkdir -p openwrt/package/custom

cp -a packages/. \
    openwrt/package/custom/

# ------------------------------------------------------------
# Verify important UZ801 files
# ------------------------------------------------------------

echo
echo "[5/9] Verifying UZ801 source tree..."

REQUIRED_FILES=(
    "openwrt/target/linux/msm89xx/Makefile"
    "openwrt/target/linux/msm89xx/image/Makefile"
    "openwrt/target/linux/msm89xx/modules.mk"
)

for FILE in "${REQUIRED_FILES[@]}"; do

    if [ ! -f "$FILE" ]; then
        echo "ERROR: Missing $FILE"
        exit 1
    fi

done

echo "Required target files OK."

# ------------------------------------------------------------
# Feeds
# ------------------------------------------------------------

cd openwrt

echo
echo "[6/9] Updating OpenWrt feeds..."

./scripts/feeds update -a

./scripts/feeds install -a

cd "$SCRIPT_DIR"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

echo
echo "[7/9] Applying UZ801 configuration..."

cd openwrt

cp ../diffconfig_uz801 .config

make defconfig

echo
echo "Final target:"

grep '^CONFIG_TARGET_' .config \
    | grep -E 'msm89xx|msm8916|yiming' \
    || true

echo
echo "Important packages:"

grep '^CONFIG_PACKAGE_' .config \
    | grep -E \
    'qmi|qrtr|rmtfs|wcn|modem|zhihe|sms|firewall|dnsmasq|usb-gadget' \
    || true

cd "$SCRIPT_DIR"

# ------------------------------------------------------------
# Download sources
# ------------------------------------------------------------

echo
echo "[8/9] Downloading sources..."

cd openwrt

CORES="$(nproc 2>/dev/null || echo 2)"

echo "Build jobs: $CORES"

make download -j"$CORES"

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

echo
echo "[9/9] Starting OpenWrt build..."
echo

if [ "$BUILD_PACKAGES_ONLY" -eq 1 ]; then

    echo "============================================================"
    echo " PACKAGE-ONLY BUILD"
    echo "============================================================"

    make tools/install -j"$CORES"

    make toolchain/install -j"$CORES"

    make target/linux/compile -j"$CORES" \
        || make target/linux/compile -j1 V=s

    echo
    echo "Building UZ801 custom packages..."

    for pkg_dir in ../packages/*; do

        if [ -d "$pkg_dir" ] && [ -f "$pkg_dir/Makefile" ]; then

            pkg_name="$(basename "$pkg_dir")"

            echo
            echo "------------------------------------------------------------"
            echo "Building package: $pkg_name"
            echo "------------------------------------------------------------"

            make "package/custom/$pkg_name/compile" \
                -j"$CORES" \
                || make "package/custom/$pkg_name/compile" \
                -j1 V=s

        fi

    done

    echo
    echo "============================================================"
    echo " Package build completed"
    echo "============================================================"
    echo

    echo "Packages:"

    find bin/packages -type f \
        \( \
        -name '*qmi*' -o \
        -name '*rmtfs*' -o \
        -name '*zhihe*' -o \
        -name '*sms*' -o \
        -name '*usb-gadget*' \
        \) \
        -print 2>/dev/null || true

else

    make -j"$CORES" \
        || make -j1 V=s

    echo
    echo "============================================================"
    echo " Firmware build completed"
    echo "============================================================"

    TARGET_DIR="bin/targets/msm89xx/msm8916"

    echo
    echo "Output directory: $TARGET_DIR"
    echo

    if [ -d "$TARGET_DIR" ]; then

        echo "Generated files:"

        ls -lh "$TARGET_DIR"

    else

        echo "WARNING: target output directory not found: $TARGET_DIR"

    fi

fi

cd "$SCRIPT_DIR"

echo
echo "============================================================"
echo " BUILD FINISHED"
echo "============================================================"
echo
echo "OpenWrt : $OPENWRT_VERSION"
echo "Commit  : $OPENWRT_COMMIT"
echo
echo "AmneziaWG/AWG: DISABLED / REMOVED"
echo
```
