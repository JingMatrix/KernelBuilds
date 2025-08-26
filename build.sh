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
# To be defined after SETUP_TOOLCHAIN
MAKE_PARAMS=""

# Define full paths to binaries
AVBTOOL=$TOOLCHAINS_BASE_DIR/avb/avbtool.py
MAGISKBOOT=$TOOLCHAINS_BASE_DIR/AIK_ARM/bin/magiskboot_x86

# --- Build Environment ---
SRC_DIR=$MAIN_DIR/sm7325
OUT_DIR=$MAIN_DIR/builds
FIRMWARE_BASE_DIR=$MAIN_DIR/firmware
SIGNING_KEY_PRIVATE=$OUT_DIR/signing_key.pem
SIGNING_KEY_PUBLIC=$OUT_DIR/signing_key.avbpubkey
JOBS=$(nproc)

# --- Core Functions ---

CHECK_DEPENDENCIES()
{
	echo "----------------------------------------------"
	echo "Checking for required dependencies..."

	# Check for system-wide tools
	local system_tools=("git" "wget" "tar" "make" "ccache" "python3" "stat" "openssl" "bear")
	for tool in "${system_tools[@]}"; do
		if ! command -v "$tool" &> /dev/null; then
			echo "ERROR: System tool '$tool' is not installed."
			echo "Please install it using your system's package manager (e.g., 'sudo apt install $tool')."
			exit 1
		fi
	done
	echo "All required system tools are installed."

	# Check for toolchain-specific binaries
	local toolchain_tools=("$AVBTOOL" "$MAGISKBOOT")
	for tool_path in "${toolchain_tools[@]}"; do
		if [ ! -f "$tool_path" ]; then
			echo "ERROR: Required tool '$tool_path' not found."
			echo "Please make sure the 'toolchains' directory is populated."
			echo "If you are using Git submodules, run: git submodule update --init --recursive"
			exit 1
		fi
	done
	# Ensure binaries are executable
	chmod +x "$MAGISKBOOT"
	echo "All required toolchain binaries are present."
}

SETUP_TOOLCHAIN()
{
	echo "----------------------------------------------"
	echo "INFO: Attempting to locate local NDK toolchain..."

	# 1. Attempt to find a local NDK Clang toolchain
	if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/ndk" ]; then
		# Find the latest NDK version directory
		LATEST_NDK_VERSION_DIR=$(ls "$ANDROID_HOME/ndk" | sort -V | tail -n 1)
		if [ -n "$LATEST_NDK_VERSION_DIR" ]; then
			POTENTIAL_CLANG_DIR="$ANDROID_HOME/ndk/$LATEST_NDK_VERSION_DIR/toolchains/llvm/prebuilt/linux-x86_64"

			# The crucial check: does the clang binary actually exist?
			if [ -f "$POTENTIAL_CLANG_DIR/bin/clang" ]; then
				echo "INFO: Found valid Clang in local NDK: $POTENTIAL_CLANG_DIR"
				CLANG_DIR=$POTENTIAL_CLANG_DIR
				# If we succeed, we are done and can exit the function.
				return 0
			fi
		fi
	fi

	# 2. If local NDK fails, fall back to asking the user for download permission
	echo "WARNING: Could not find a usable Clang toolchain in your local Android NDK."
	echo "         Reason: \$ANDROID_HOME may not be set, NDK not installed, or toolchain is incomplete."

	# Check if the download destination already exists
	if [ -d "$CLANG_DIR" ] && [ -f "$CLANG_DIR/bin/clang" ]; then
		echo "INFO: Using previously downloaded toolchain at '$CLANG_DIR'."
		return 0
	fi

	# Prompt the user for permission
	read -p "Do you want to download the recommended remote toolchain? [y/N] " -r REPLY
	echo # Add a newline for cleaner output

	if [[ "$REPLY" =~ ^[Yy]$ ]]; then
		echo "INFO: User approved download. Preparing to download Clang..."
		mkdir -p "$(dirname "$CLANG_DIR")"
		wget -q --show-progress -O clang.tar.gz "$CLANG_URL"

		# Create the final destination directory
		mkdir -p "$CLANG_DIR"

		# Extract contents, stripping the top-level directory for a cleaner path
		tar -xf clang.tar.gz -C "$CLANG_DIR" --strip-components=1

		# Clean up the downloaded tarball
		rm clang.tar.gz
		echo "INFO: Clang toolchain downloaded and extracted successfully to '$CLANG_DIR'."
	else
		echo "ERROR: Toolchain setup aborted by user."
		exit 1
	fi
}

PREPARE_SIGNING_KEY()
{
	echo "----------------------------------------------"
	echo "Checking for signing key..."
	mkdir -p "$OUT_DIR"
	if [ ! -f "$SIGNING_KEY_PRIVATE" ]; then
		echo "Signing key not found. Generating a new one..."
		openssl genpkey -algorithm RSA -out "$SIGNING_KEY_PRIVATE" -pkeyopt rsa_keygen_bits:4096
		openssl pkey -in "$SIGNING_KEY_PRIVATE" -pubout -out "$SIGNING_KEY_PUBLIC"
		echo "New signing key pair generated in $OUT_DIR"
	else
		echo "Existing signing key found."
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
	bear -- make $MAKE_PARAMS CC="ccache clang" "vendor/$DEFCONFIG" custom.config
	bear -- make $MAKE_PARAMS CC="ccache clang"
}

BUILD_MODULES()
{
	echo "----------------------------------------------"
	echo "Building kernel modules for $VARIANT..."
	bear -- make $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

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

# Function to manually rebuild vbmeta to spoof the hashes
SPOOF_VBMETA_MANUAL()
{
	echo "----------------------------------------------"
	echo "Rebuilding vbmeta.img for $VARIANT using avbtool..."

	# Step 1: Get metadata from the original vbmeta.img
	local stock_vbmeta="$FIRMWARE_DIR/vbmeta.img"
	local info
	info=$(python3 "$AVBTOOL" info_image --image "$stock_vbmeta")

	local algorithm
	algorithm=$(echo "$info" | grep "Algorithm:" | head -n 1 | awk '{print $2}')
	local rollback_index
	rollback_index=$(echo "$info" | grep "Rollback Index:" | head -n 1 | awk '{print $3}')

	if [ -z "$algorithm" ] || [ -z "$rollback_index" ]; then
		echo "ERROR: Could not parse metadata from stock vbmeta.img for $VARIANT."
		exit 1
	fi
	echo "Stock vbmeta metadata: Algorithm=$algorithm, Rollback Index=$rollback_index"

	# Get partition sizes from stock firmware images
	echo "Getting partition sizes from stock firmware images..."
	local boot_partition_size
	boot_partition_size=$(stat -c %s "$FIRMWARE_DIR/boot.img")
	local dtbo_partition_size
	dtbo_partition_size=$(stat -c %s "$FIRMWARE_DIR/dtbo.img")
	local vendor_boot_partition_size
	vendor_boot_partition_size=$(stat -c %s "$FIRMWARE_DIR/vendor_boot.img")

	if [ -z "$boot_partition_size" ] || [ -z "$dtbo_partition_size" ] || [ -z "$vendor_boot_partition_size" ]; then
		echo "ERROR: Could not determine partition size for one or more images in $FIRMWARE_DIR."
		exit 1
	fi
	echo "Partition sizes: boot=${boot_partition_size}, dtbo=${dtbo_partition_size}, vendor_boot=${vendor_boot_partition_size}"

	# Step 2: Add signed hash footers to our custom images with correct partition sizes.
	echo "Adding signed hash footers to images..."
	python3 "$AVBTOOL" add_hash_footer --image "$VARIANT_OUT_DIR/boot.img" --partition_name boot --partition_size "$boot_partition_size" --key "$SIGNING_KEY_PRIVATE" --algorithm "$algorithm"
	python3 "$AVBTOOL" add_hash_footer --image "$VARIANT_OUT_DIR/dtbo.img" --partition_name dtbo --partition_size "$dtbo_partition_size" --key "$SIGNING_KEY_PRIVATE" --algorithm "$algorithm"
	python3 "$AVBTOOL" add_hash_footer --image "$VARIANT_OUT_DIR/vendor_boot.img" --partition_name vendor_boot --partition_size "$vendor_boot_partition_size" --key "$SIGNING_KEY_PRIVATE" --algorithm "$algorithm"

	# Step 3: Rebuild vbmeta by including descriptors from the footered images.
	if python3 "$AVBTOOL" make_vbmeta_image \
		--output "$VARIANT_OUT_DIR/vbmeta.img" \
		--key "$SIGNING_KEY_PRIVATE" \
		--algorithm "$algorithm" \
		--rollback_index "$rollback_index" \
		--flags 2 \
		--include_descriptors_from_image "$VARIANT_OUT_DIR/boot.img" \
		--include_descriptors_from_image "$VARIANT_OUT_DIR/dtbo.img" \
		--include_descriptors_from_image "$VARIANT_OUT_DIR/vendor_boot.img"
then
	echo "Successfully rebuilt vbmeta.img. Final size: $(stat -c %s "$VARIANT_OUT_DIR/vbmeta.img") bytes."
	cp "$SIGNING_KEY_PUBLIC" "$VARIANT_OUT_DIR/"
	# --- NEW: Print the metadata of the generated vbmeta.img for verification ---
	echo "----------------- Generated vbmeta.img Metadata -----------------"
	python3 "$AVBTOOL" info_image --image "$VARIANT_OUT_DIR/vbmeta.img"
	echo "-----------------------------------------------------------------"
else
	echo "ERROR: Failed to rebuild vbmeta.img manually for $VARIANT."
	exit 1
	fi
}


# --- Main Execution ---
clear

# 1. Determine Build Mode
BUILD_MODE="full"
if [[ $1 == "vbmeta" ]]; then
	BUILD_MODE="vbmeta_only"
	echo "Build mode: vbmeta only. Skipping kernel compilation."
elif [[ $1 == "-c" || $1 == "--clean" ]]; then
	CLEAN_SOURCE
fi


# 2. Setup and Preparation
CHECK_DEPENDENCIES
PREPARE_SIGNING_KEY
if [ "$BUILD_MODE" == "full" ]; then
	SETUP_TOOLCHAIN
	DETECT_BRANCH
fi

MAKE_PARAMS="-j$JOBS -C $SRC_DIR O=$SRC_DIR/out \
	ARCH=arm64 CLANG_TRIPLE=aarch64-linux-gnu- LLVM=1 LLVM_IAS=1 \
	CROSS_COMPILE=$CLANG_DIR/bin/llvm-"

export PATH="$CLANG_DIR/bin:$PATH"

# 3. Dynamic Build Loop based on firmware directories
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

		# 4. Check for required firmware files
		REQUIRED_FILES=("boot.img" "vbmeta.img" "dtbo.img" "vendor_boot.img")
		missing_file=false
		for file in "${REQUIRED_FILES[@]}"; do
			if [ ! -f "$FIRMWARE_DIR/$file" ]; then
				echo "WARNING: Missing firmware file '$file' for $VARIANT. Skipping."
				missing_file=true
				break
			fi
		done
		if [ "$missing_file" = true ]; then
			continue
		fi
		echo "All required firmware images found for $VARIANT."
		mkdir -p "$VARIANT_OUT_DIR"


		# 5. Set variant-specific configurations
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

		# 6. Build and Pack OR Check for existing files
		if [ "$BUILD_MODE" == "full" ]; then
			BUILD_KERNEL
			BUILD_MODULES
			PACK_BOOT_IMG
			PACK_DTBO_IMG
			PACK_VENDOR_BOOT_IMG
		else # vbmeta_only mode
			PACKED_IMAGES=("$VARIANT_OUT_DIR/boot.img" "$VARIANT_OUT_DIR/dtbo.img" "$VARIANT_OUT_DIR/vendor_boot.img")
			missing_packed_file=false
			for file in "${PACKED_IMAGES[@]}"; do
				if [ ! -f "$file" ]; then
					echo "WARNING: Pre-built image '$file' not found for $VARIANT. Run a full build first. Skipping."
					missing_packed_file=true
					break
				fi
			done
			if [ "$missing_packed_file" = true ]; then
				continue
			fi
			echo "Found all pre-built images for $VARIANT."
		fi

		# 7. Generate vbmeta.img (runs in both modes)
		SPOOF_VBMETA_MANUAL
	fi
done

echo "----------------------------------------------"
echo "Build process finished."
echo "Generated files are located in: $OUT_DIR"
echo "----------------------------------------------"
