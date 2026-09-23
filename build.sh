#!/bin/bash
# Copyright (c) 2026 ravindu644 <droidcasts@protonmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Linux 4.9 arm64 kernel build script for SM-T295

set -euo pipefail

# cd to the repo root
KERNEL_ROOT="$(dirname "$(readlink -f "$0")")"
cd "${KERNEL_ROOT}"

# init submodules
git submodule update --init --recursive || true

# generate localversion
BUILD_VERSION=$(git log -1 --pretty=%h 2>/dev/null)
if [ -z "$BUILD_VERSION" ]; then
    export BUILD_VERSION="dev"
fi
cat << EOF > "${KERNEL_ROOT}/arch/arm64/configs/version.config"
CONFIG_LOCALVERSION_AUTO=n
CONFIG_LOCALVERSION="-ravindu644-${BUILD_VERSION}"
EOF

# create build folders
mkdir -p out dist

# export toolchain path and core variables
export PATH="${HOME}/toolchains/llvm-arm-toolchain-ship/10.0.9/bin:${PATH}"
export KBUILD_BUILD_USER="@ravindu644"
BUILD_CROSS_COMPILE="${HOME}/toolchains/aarch64-linux-android-4.9/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"

# build options for the kernel
BUILD_OPTIONS=(
    -C "${KERNEL_ROOT}"
    O="${KERNEL_ROOT}/out"
    -j"$(nproc)"
    ARCH=arm64
    DTC_EXT="${KERNEL_ROOT}/tools/dtc"
    CONFIG_BUILD_ARM64_DT_OVERLAY=y
    CROSS_COMPILE="${BUILD_CROSS_COMPILE}"
    CC=clang
    CLANG_TRIPLE=aarch64-linux-gnu-
)

build_kernel(){
    # cleanup
    # make "${BUILD_OPTIONS[@]}" clean && make "${BUILD_OPTIONS[@]}" mrproper
    
    # make default configuration.
    make "${BUILD_OPTIONS[@]}" gto_eur_open_defconfig custom.config version.config droidspaces.config

    # menuconfig
    make "${BUILD_OPTIONS[@]}" menuconfig

    # Build the kernel
    make "${BUILD_OPTIONS[@]}" || exit 1

    # Copy the built kernel to the build directory
    cp "${KERNEL_ROOT}/out/arch/arm64/boot/Image" "${KERNEL_ROOT}/dist/Image"
}

build_boot(){
    # unpack stock boot.img, swap in our kernel, repack
    local work="${KERNEL_ROOT}/dist/boot_work"
    rm -rf "${work}" && mkdir -p "${work}" && cd "${work}"
    magiskboot unpack "${KERNEL_ROOT}/prebuilts/boot.img"
    cp "${KERNEL_ROOT}/dist/Image" kernel
    magiskboot repack "${KERNEL_ROOT}/prebuilts/boot.img" "${KERNEL_ROOT}/dist/boot.img"
    cd "${KERNEL_ROOT}" && rm -rf "${work}"

    # newer Wingtech bootloaders reject boot images without Samsung's SignerVer02
    # block: insert it after SEANDROIDENFORCE and grow the AVB footer's image size
    python3 - "${KERNEL_ROOT}/dist/boot.img" <<'EOF'
import sys
p = sys.argv[1]; d = bytearray(open(p, 'rb').read())
assert d[-64:-60] == b'AVBf' and b'SignerVer02' not in d
n = int.from_bytes(d[-52:-44], 'big')
if d[n:n+16] == b'SEANDROIDENFORCE': n += 16
assert d[n:n+512] == bytes(512)
d[n:n+11] = b'SignerVer02'
d[-52:-44] = (n + 512).to_bytes(8, 'big')
open(p, 'wb').write(d)
EOF
}

build_tar(){
    cd "${KERNEL_ROOT}/dist"
    tar -cvf "Droidspaces-Samsung-SM-T295-${BUILD_VERSION}.tar" boot.img && \
        echo -e "\n[INFO]: TAR BUILT SUCCESSFULLY..!\n"
    cd "${KERNEL_ROOT}"
}

build_kernel
build_boot
build_tar
