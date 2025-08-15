#!/bin/bash
#
# Ascendia Build Script - a52sxq
# Coded by BlackMesa123 @2023
# Modified and adapted by RisenID @2024
# Improved by JingMatrix @2025
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e

# --- Main Configuration ---
DATE=$(date +%Y%m%d)
ANDROID_CODENAME="U"
RELEASE_VERSION="jingmatrix"
MAIN_DIR=$(pwd)

# --- Toolchain and Tool Paths ---
TOOLCHAINS_BASE_DIR=$MAIN_DIR/toolchains
CLANG_DIR=$TOOLCHAINS_BASE_DIR/clang
CLANG_URL="https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/clang-r383902b.tar.gz"

# Define full paths to binaries
AVBTOOL=$TOOLCHAINS_BASE_DIR/avb/avbtool.py
MAGISKBOOT=$TOOLCHAINS_BASE_DIR/AIK_ARM/bin/magiskboot_x86
VBMETA_PATCHER=$TOOLCHAINS_BASE_DIR/vbmeta-action-patcher/x86_64/vbmeta-disable-verification

# --- Build Environment ---
SRC_DIR=$MAIN_DIR/sm7325
OUT_DIR=$MAIN_DIR/builds
FIRMWARE_BASE_DIR=$MAIN_DIR/firmware
JOBS=$(nproc)

MAKE_PARAMS="-j$JOBS -C $SRC_DIR O=$SRC_DIR/out \
	ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1 \
	CROSS_COMPILE=$CLANG_DIR/bin/llvm-"

export PATH="$CLANG_DIR/bin:$PATH"

# --- Core Functions ---

CHECK_DEPENDENCIES()
{
	echo "----------------------------------------------"
	echo "Checking for required dependencies..."

	# Check for system-wide tools
	local system_tools=("git" "wget" "tar" "make" "ccache" "python3")
	for tool in "${system_tools[@]}"; do
		if ! command -v "$tool" &> /dev/null; then
			echo "ERROR: System tool '$tool' is not installed."
			echo "Please install it using your system's package manager (e.g., 'sudo apt install $tool')."
			exit 1
		fi
	done
	echo "All required system tools are installed."

	# Check for toolchain-specific binaries
	local toolchain_tools=("$AVBTOOL" "$MAGISKBOOT" "$VBMETA_PATCHER")
	for tool_path in "${toolchain_tools[@]}"; do
		if [ ! -f "$tool_path" ]; then
			echo "ERROR: Required tool '$tool_path' not found."
			echo "Please make sure the 'toolchains' directory is populated."
			echo "If you are using Git submodules, run: git submodule update --init --recursive"
			exit 1
		fi
	done
	# Ensure binaries are executable
	chmod +x "$MAGISKBOOT" "$VBMETA_PATCHER"
	echo "All required toolchain binaries are present."
}

PREPARE_CLANG()
{
	echo "----------------------------------------------"
	echo "Preparing Clang toolchain..."
	if [ ! -d "$CLANG_DIR" ]; then
		echo "Clang toolchain not found. Downloading..."
		# Create the final destination directory first
		mkdir -p "$CLANG_DIR"
		# Download the tarball
		wget -q -O clang.tar.gz "$CLANG_URL"
		# Extract its contents directly into the destination directory
		tar -xf clang.tar.gz -C "$CLANG_DIR"
		# Clean up the downloaded tarball
		rm clang.tar.gz
		echo "Clang toolchain downloaded and extracted."
	else
		echo "Clang toolchain already exists."
	fi
}

DETECT_BRANCH()
{
	cd "$SRC_DIR/"
	local branch
	branch=$(git rev-parse --abbrev-ref HEAD)
	cd "$MAIN_DIR/"

	echo "----------------------------------------------"
	if [[ "$branch" == "oneui-ksu" ]]; then
		echo "OneUI Branch Detected..."
		ASC_VARIANT="OneUI"
		ASC_VAR="O"
	elif [[ "$branch" == "aosp-ksu" ]]; then
		echo "AOSP Branch Detected..."
		ASC_VARIANT="AOSP"
		ASC_VAR="A"
	else
		echo "ERROR: Current branch '$branch' is not a valid build branch."
		exit 1
	fi
}

CLEAN_SOURCE()
{
	echo "----------------------------------------------"
	echo "Cleaning up kernel source output..."
	rm -rf "$SRC_DIR/out"
}

BUILD_KERNEL()
{
	echo "----------------------------------------------"
	[ -d "$SRC_DIR/out" ] && echo "Starting $VARIANT kernel build... (DIRTY)" || echo "Starting $VARIANT kernel build..."
	export LOCALVERSION="-$ANDROID_CODENAME-$RELEASE_VERSION-$ASC_VAR-$VARIANT"
	mkdir -p "$SRC_DIR/out"
	make $MAKE_PARAMS CC="ccache clang" "vendor/$DEFCONFIG"
	make $MAKE_PARAMS CC="ccache clang"
}

BUILD_MODULES()
{
	echo "----------------------------------------------"
	echo "Building kernel modules for $VARIANT..."
	make $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

	local MODULES_OUT_DIR="$VARIANT_OUT_DIR/modules/vendor/lib/modules"
	mkdir -p "$MODULES_OUT_DIR"
	find "$SRC_DIR/out/modules" -name '*.ko' -exec cp '{}' "$MODULES_OUT_DIR" ';'
	if [ -d "$SRC_DIR/out/modules/lib/modules/5.4"* ]; then
		cp "$SRC_DIR/out/modules/lib/modules/5.4"*/modules.{alias,dep,softdep} "$MODULES_OUT_DIR"
		cp "$SRC_DIR/out/modules/lib/modules/5.4"*/modules.order "$MODULES_OUT_DIR/modules.load"
		sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' "$MODULES_OUT_DIR/modules.dep"
		sed -i 's/.*\///g' "$MODULES_OUT_DIR/modules.load"
	fi
	rm -rf "$SRC_DIR/out/modules"
}

PACK_BOOT_IMG()
{
	echo "----------------------------------------------"
	echo "Packing boot.img for $VARIANT..."
	local TMP_DIR="$OUT_DIR/tmp"
	rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
	cd "$TMP_DIR"

	cp "$FIRMWARE_DIR/boot.img" .
	python3 "$AVBTOOL" erase_footer --image boot.img
	"$MAGISKBOOT" unpack boot.img

	# Replace stock kernel image and repack
	cp "$SRC_DIR/out/arch/arm64/boot/Image" kernel
	"$MAGISKBOOT" repack boot.img boot_new.img
	mv boot_new.img "$VARIANT_OUT_DIR/boot.img"

	cd "$MAIN_DIR"
	rm -rf "$TMP_DIR"
}

PACK_DTBO_IMG()
{
	echo "----------------------------------------------"
	echo "Packing dtbo.img for $VARIANT..."
	cp "$SRC_DIR/out/arch/arm64/boot/dtbo.img" "$VARIANT_OUT_DIR/dtbo.img"
}

PACK_VENDOR_BOOT_IMG()
{
	echo "----------------------------------------------"
	echo "Packing vendor_boot.img for $VARIANT..."
	local TMP_DIR="$OUT_DIR/tmp"
	rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
	cd "$TMP_DIR"

	cp "$FIRMWARE_DIR/vendor_boot.img" .
	python3 "$AVBTOOL" erase_footer --image vendor_boot.img
	"$MAGISKBOOT" unpack -h vendor_boot.img

	# Replace KernelRPValue and stock DTB
	sed "1 c\name=$RP_REV" header > header_new
	mv header_new header
	cp "$SRC_DIR/out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" dtb

	# Repack and move
	"$MAGISKBOOT" repack vendor_boot.img vendor_boot_new.img
	mv vendor_boot_new.img "$VARIANT_OUT_DIR/vendor_boot.img"

	cd "$MAIN_DIR"
	rm -rf "$TMP_DIR"
}

PATCH_VBMETA()
{
	echo "----------------------------------------------"
	echo "Patching vbmeta.img for $VARIANT..."
	cp "$FIRMWARE_DIR/vbmeta.img" "$VARIANT_OUT_DIR/vbmeta.img"
	"$VBMETA_PATCHER" "$VARIANT_OUT_DIR/vbmeta.img"
	echo "vbmeta verification disabled for $VARIANT."
}


# --- Main Execution ---
clear

# 1. Setup and Preparation
CHECK_DEPENDENCIES
PREPARE_CLANG
DETECT_BRANCH
if [[ $1 == "-c" || $1 == "--clean" ]]; then
	CLEAN_SOURCE
fi

# 2. Dynamic Build Loop based on firmware directories
if [ ! -d "$FIRMWARE_BASE_DIR" ] || [ -z "$(ls -A "$FIRMWARE_BASE_DIR")" ]; then
    echo "ERROR: 'firmware' directory does not exist or is empty."
    echo "Please create subdirectories for each variant (e.g., firmware/a52sxqxx) with required images."
    exit 1
fi

for variant_path in "$FIRMWARE_BASE_DIR"/*; do
	if [ -d "$variant_path" ]; then
		VARIANT=$(basename "$variant_path")
		FIRMWARE_DIR=$variant_path
		VARIANT_OUT_DIR="$OUT_DIR/$VARIANT"

		echo ""
		echo "=============================================="
		echo "Processing Variant: $VARIANT"
		echo "=============================================="

		# 3. Check for required firmware files
		REQUIRED_FILES=("boot.img" "vbmeta.img" "dtbo.img" "vendor_boot.img")
		missing_file=false
		for file in "${REQUIRED_FILES[@]}"; do
			if [ ! -f "$FIRMWARE_DIR/$file" ]; then
				echo "WARNING: Missing '$file' in '$FIRMWARE_DIR'. Skipping build for $VARIANT."
				missing_file=true
				break
			fi
		done
		if [ "$missing_file" = true ]; then
			continue
		fi
		echo "All required firmware images found for $VARIANT."
		mkdir -p "$VARIANT_OUT_DIR"


		# 4. Set variant-specific configurations
		case "$VARIANT" in
			a52sxqxx)
				DEFCONFIG=a52sxq_eur_open_defconfig
				RP_REV=SRPUE26A001
				;;
			a52sxqks)
				DEFCONFIG=a52sxq_kor_single_defconfig
				RP_REV=SRPUF22A001
				;;
			a52sxqzt)
				DEFCONFIG=a52sxq_chn_tw_defconfig
				RP_REV=SRPUE26A001
				;;
			*)
				echo "WARNING: No specific configuration found for '$VARIANT'. Skipping."
				continue
				;;
		esac

		# 5. Build and Pack
		BUILD_KERNEL
		BUILD_MODULES
		PACK_BOOT_IMG
		PACK_DTBO_IMG
		PACK_VENDOR_BOOT_IMG
		PATCH_VBMETA
	fi
done

echo "----------------------------------------------"
echo "Build process finished."
echo "Generated files are located in: $OUT_DIR"
echo "----------------------------------------------"
