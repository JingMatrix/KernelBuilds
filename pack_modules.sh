#!/bin/bash
#
# A script to pack kernel modules for sm7325
# Copyright (C) 2025 JingMatrix
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

# --- Configuration ---
MODULE_ID="sm7325-klm"
MODULE_NAME="SM7325 Kernel Helper"
MODULE_AUTHOR="JingMatrix"
MODULE_VERSION="1.5"
MODULE_VERSION_CODE=6
DATE=$(date +%Y%m%d)
ZIP_NAME="${MODULE_ID}-${MODULE_VERSION}-${DATE}.zip"
MAIN_DIR=$(pwd)
BUILDS_DIR=$MAIN_DIR/builds
MODULE_BUILD_DIR=$MAIN_DIR/module_tmp

# --- Functions ---

cleanup() {
    echo "Cleaning up temporary directory..."
    rm -rf "$MODULE_BUILD_DIR"
}

generate_module_prop() {
    echo "Generating module.prop..."
    cat > "$MODULE_BUILD_DIR/module.prop" <<- EOM
id=${MODULE_ID}
name=${MODULE_NAME}
version=${MODULE_VERSION}
versionCode=${MODULE_VERSION_CODE}
author=${MODULE_AUTHOR}
description=Systemless installer for custom kernel modules on sm7325 devices. Includes device-specific runtime fixes.
EOM
}

generate_updater_script() {
    echo "Generating META-INF/com/google/android/updater-script..."
    mkdir -p "$MODULE_BUILD_DIR/META-INF/com/google/android"
    cat > "$MODULE_BUILD_DIR/META-INF/com/google/android/updater-script" <<- EOM
# Stub updater-script
# The real logic is in customize.sh
EOM
}

generate_customize_sh() {
    echo "Generating customize.sh with verbose camera fix logic..."
    # Using <<- 'EOM' allows for indentation in the script for readability,
    # and the quotes prevent variable expansion within this script.
    cat > "$MODULE_BUILD_DIR/customize.sh" <<- 'EOM'
#!/sbin/sh
#
# This script is executed by the Magisk/KernelSU app during module installation.
# It applies a systemless camera fix for sm7325 devices that require it.
#

# Magisk/KernelSU provides these variables and functions
# $MODPATH is the path to this module's directory
# ui_print "message" prints a message to the installation log

ui_print " "
ui_print "- SM7325 Kernel Helper -"
ui_print "  Installing kernel modules and applying fixes..."
ui_print " "

# --- Camera Fix Logic ---
DEVICE_CODENAME=$(getprop ro.product.device)

# Check if the device codename starts with "a52s"
if [[ "$DEVICE_CODENAME" == "a52s"* ]]; then
    ui_print "- Device identified as Galaxy A52s ($DEVICE_CODENAME)."
    ui_print "- Checking camera libraries for required patches..."

    PATCH_APPLIED=false

    # Create the necessary directories inside the module's folder ($MODPATH)
    # This is done once to avoid repetition.
    mkdir -p "$MODPATH/system/vendor/lib/hw"
    mkdir -p "$MODPATH/system/vendor/lib64/hw"

    # --- Check and patch each library individually for clear user feedback ---

    # 64-bit main library
    if [ -f "/vendor/lib64/hw/camera.qcom.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib64/hw/camera.qcom.so; then
            ui_print "  - Patching /vendor/lib64/hw/camera.qcom.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib64/hw/camera.qcom.so" > "$MODPATH/system/vendor/lib64/hw/camera.qcom.so"
            PATCH_APPLIED=true
        else
            ui_print "  - Skipping /vendor/lib64/hw/camera.qcom.so (no patch needed)."
        fi
    fi

    # 64-bit override library
    if [ -f "/vendor/lib64/hw/com.qti.chi.override.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib64/hw/com.qti.chi.override.so; then
            ui_print "  - Patching /vendor/lib64/hw/com.qti.chi.override.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib64/hw/com.qti.chi.override.so" > "$MODPATH/system/vendor/lib64/hw/com.qti.chi.override.so"
            PATCH_APPLIED=true
        else
            ui_print "  - Skipping /vendor/lib64/hw/com.qti.chi.override.so (no patch needed)."
        fi
    fi

    # 32-bit main library
    if [ -f "/vendor/lib/hw/camera.qcom.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib/hw/camera.qcom.so; then
            ui_print "  - Patching /vendor/lib/hw/camera.qcom.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib/hw/camera.qcom.so" > "$MODPATH/system/vendor/lib/hw/camera.qcom.so"
            PATCH_APPLIED=true
        else
            ui_print "  - Skipping /vendor/lib/hw/camera.qcom.so (no patch needed)."
        fi
    fi

    # 32-bit override library
    if [ -f "/vendor/lib/hw/com.qti.chi.override.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib/hw/com.qti.chi.override.so; then
            ui_print "  - Patching /vendor/lib/hw/com.qti.chi.override.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib/hw/com.qti.chi.override.so" > "$MODPATH/system/vendor/lib/hw/com.qti.chi.override.so"
            PATCH_APPLIED=true
        else
            ui_print "  - Skipping /vendor/lib/hw/com.qti.chi.override.so (no patch needed)."
        fi
    fi

    if $PATCH_APPLIED; then
        ui_print "- Camera fix applied successfully."
    else
        ui_print "- Camera patch check complete. No patches were required."
    fi
else
    ui_print "- Device ($DEVICE_CODENAME) does not require a camera fix. Skipping."
fi

ui_print " "
ui_print "- Installation complete."
EOM
}

generate_service_sh() {
    local calculated_digest="$1"
    local calculated_size="$2"
    echo "Generating service.sh for vbmeta spoofing with digest: ${calculated_digest} and size: ${calculated_size}"
    mkdir -p "$MODULE_BUILD_DIR"
    cat > "$MODULE_BUILD_DIR/service.sh" <<- EOM
#!/system/bin/sh
#
# This script is executed during the boot process by Magisk/KernelSU.
# Its purpose is to add back the ro.boot.vbmeta.* properties that are
# missing when booting with a vbmeta that has verification disabled.
#

# Wait for the boot process to be mostly complete
until [ "\$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# The digest and size of the custom vbmeta.img, calculated at build time.
VBMETA_DIGEST="${calculated_digest}"
VBMETA_SIZE="${calculated_size}"

resetprop -p --delete ro.boot.vbmeta.avb_version
resetprop -p --delete ro.boot.vbmeta.device_state
resetprop -p --delete ro.boot.vbmeta.digest
resetprop -p --delete ro.boot.vbmeta.hash_alg
resetprop -p --delete ro.boot.vbmeta.size

resetprop -n ro.boot.vbmeta.avb_version 1.0
resetprop -n ro.boot.vbmeta.device_state locked
resetprop -n ro.boot.vbmeta.digest "\$VBMETA_DIGEST"
resetprop -n ro.boot.vbmeta.hash_alg sha256
resetprop -n ro.boot.vbmeta.size "\$VBMETA_SIZE"
EOM
}


# --- Main Script ---
echo "Starting Kernel Module Packager..."

# Trap to ensure cleanup happens on exit
trap cleanup EXIT

# Clean previous build
rm -f "$ZIP_NAME"
cleanup
mkdir -p "$MODULE_BUILD_DIR"

# Generate module metadata
generate_module_prop
generate_updater_script
generate_customize_sh
generate_service_sh

# Find the latest build directory
LATEST_BUILD_DIR=$(find "$BUILDS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

if [ -z "$LATEST_BUILD_DIR" ]; then
    echo "ERROR: Could not find any recent build directory in '$BUILDS_DIR'."
    echo "Please run a full kernel build first using ./build.sh"
    exit 1
fi

# Find the first vbmeta.img inside the latest build's variant folders
VBMETA_PATH=$(find "$LATEST_BUILD_DIR" -name "vbmeta.img" | head -n 1)

if [ -z "$VBMETA_PATH" ]; then
    echo "ERROR: Could not find a 'vbmeta.img' in the latest build directory: $LATEST_BUILD_DIR"
    echo "Please ensure the kernel build completed successfully."
    exit 1
fi
echo "Found latest vbmeta.img at: $VBMETA_PATH"

# Calculate both digest and size of the vbmeta.img file
CALCULATED_DIGEST=$(sha256sum "$VBMETA_PATH" | awk '{print $1}')
CALCULATED_SIZE=$(stat -c %s "$VBMETA_PATH")

if [ -z "$CALCULATED_DIGEST" ] || [ -z "$CALCULATED_SIZE" ]; then
    echo "ERROR: Failed to calculate digest or size for $VBMETA_PATH"
    exit 1
fi

# Pass both calculated values to the service.sh generator
generate_service_sh "$CALCULATED_DIGEST" "$CALCULATED_SIZE"

# Find the latest compiled modules
MODULES_SOURCE_DIR="${LATEST_BUILD_DIR}/modules"

if [ ! -d "$MODULES_SOURCE_DIR" ]; then
    echo "ERROR: Could not find a 'modules' directory in '$LATEST_BUILD_DIR'."
    exit 1
fi
echo "Found latest modules in: $LATEST_BUILD_DIR"
echo "Copying modules to the package..."

# Copy module files into the correct structure for a systemless module
mkdir -p "$MODULE_BUILD_DIR/system/vendor/lib"
cp -r "$MODULES_SOURCE_DIR" "$MODULE_BUILD_DIR/system/vendor/lib/"

# Create the final ZIP archive
echo "Creating ZIP file: $ZIP_NAME"
cd "$MODULE_BUILD_DIR"
zip -r9 "../$ZIP_NAME" ./*
cd "$MAIN_DIR"

echo "----------------------------------------------"
echo "Module packaging complete!"
echo "Flashable ZIP is available at: ${MAIN_DIR}/${ZIP_NAME}"
echo "----------------------------------------------"
