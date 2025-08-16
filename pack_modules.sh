#!/bin/bash
#
# Magisk/KSU Systemless Module Packager
# Coded by JingMatrix @2025
#
# This script packages compiled kernel modules and a helper script
# into a clean, systemless "Kernel Helper" module.
#

set -e

# --- Module Configuration ---
MODULE_ID="sm7325-kernel-helper"
MODULE_NAME="Kernel Helper Pack for SM7325"
MODULE_VERSION="2.1-$(date +%Y%m%d)"
MODULE_AUTHOR="JingMatrix"
MODULE_DESC="Systemlessly installs kernel modules and spoofs boot properties to pass integrity checks."

# --- Path Configuration ---
# Assumes this script is in the main project dir and builds are in `builds`
BUILDS_DIR="$(pwd)/builds"
MODULE_WORK_DIR="$(pwd)/module_temp_work"
# The script will look for this file in the current directory
MODPROBE_SOURCE_SCRIPT="vendor_modprobe.sh"

# --- Script Logic (DO NOT EDIT BELOW THIS LINE) ---

echo "=============================================="
echo "Systemless Module Packager"
echo "=============================================="

# 1. Find the latest built variant to source modules and vbmeta from.
if [ ! -d "$BUILDS_DIR" ] || [ -z "$(ls -A "$BUILDS_DIR")" ]; then
    echo "ERROR: Output directory '$BUILDS_DIR' is empty or does not exist."
    echo "Please run the main kernel build script first."
    exit 1
fi
LATEST_VARIANT_PATH=$(ls -td -- "$BUILDS_DIR"/*/ | head -n 1)
SOURCE_MODULES_DIR="${LATEST_VARIANT_PATH}modules/vendor/lib/modules"
SOURCE_VBMETA_PATH="${LATEST_VARIANT_PATH}vbmeta.img"

if [ ! -d "$SOURCE_MODULES_DIR" ]; then
    echo "ERROR: Could not find the 'modules' directory in: $LATEST_VARIANT_PATH"
    exit 1
fi
echo "Found modules to package from: $(basename "$LATEST_VARIANT_PATH")"

# 2. Dynamically calculate the vbmeta digest and size for spoofing.
if [ ! -f "$SOURCE_VBMETA_PATH" ]; then
    echo "ERROR: Could not find vbmeta.img in '$LATEST_VARIANT_PATH' to calculate digest."
    exit 1
fi
VBMETA_DIGEST=$(sha256sum "$SOURCE_VBMETA_PATH" | awk '{print $1}')
VBMETA_SIZE=$(stat -c %s "$SOURCE_VBMETA_PATH")

if [ -z "$VBMETA_DIGEST" ] || [ -z "$VBMETA_SIZE" ]; then
    echo "ERROR: Failed to calculate digest or size of vbmeta.img."
    exit 1
fi
echo "Determined vbmeta digest for spoofing: ${VBMETA_DIGEST}"
echo "Determined vbmeta size for spoofing: ${VBMETA_SIZE}"

# 3. Clean up and create the working directory structure.
MODULE_ZIP_NAME="${MODULE_ID}-${MODULE_VERSION}.zip"
echo "Cleaning up previous build..."
rm -rf "$MODULE_WORK_DIR"
rm -f "$MODULE_ZIP_NAME"

echo "Creating module structure..."
MODULE_SYSTEM_DIR="$MODULE_WORK_DIR/system"
mkdir -p "$MODULE_SYSTEM_DIR/vendor/lib/modules"
mkdir -p "$MODULE_WORK_DIR/META-INF/com/google/android"

# 4. Create the Magisk/KSU metadata files.

# Create module.prop
echo "Creating module.prop..."
cat <<EOF > "$MODULE_WORK_DIR/module.prop"
id=$MODULE_ID
name=$MODULE_NAME
version=$MODULE_VERSION
versionCode=$(date +%Y%m%d)
author=$MODULE_AUTHOR
description=$MODULE_DESC
reboot=true
EOF

# Create service.sh with our dynamically determined values.
echo "Creating service.sh for property spoofing..."
cat <<EOF > "$MODULE_WORK_DIR/service.sh"
#!/system/bin/sh
# This script is executed in post-fs-data mode by Magisk/KernelSU.

# Wait a few seconds for the boot process to stabilize before setting properties.
sleep 15

# Forcibly create missing boot properties using dynamically determined values
# from the build script and other plausible reference values.
resetprop -n ro.boot.vbmeta.avb_version 1.0
resetprop -n ro.boot.vbmeta.device_state locked
resetprop -n ro.boot.vbmeta.digest ${VBMETA_DIGEST}
resetprop -n ro.boot.vbmeta.hash_alg sha256
resetprop -n ro.boot.vbmeta.invalidate_on_error yes
resetprop -n ro.boot.vbmeta.size ${VBMETA_SIZE}
resetprop -n ro.boot.verifiedbootstate green

# Log that the script has run successfully.
log -p i -t KernelHelper "Successfully spoofed boot properties."
EOF
chmod 755 "$MODULE_WORK_DIR/service.sh"

# Create customize.sh with permission-setting logic.
echo "Creating customize.sh..."
cat <<'EOF' > "$MODULE_WORK_DIR/customize.sh"
#!/system/bin/sh
# This script is executed by the Magisk/KernelSU installer environment.

# Abort installation if the user tries to flash this in recovery.
if [ -z "$MODPATH" ]; then
  ui_print "*********************************************************"
  ui_print "! This is a Magisk/KernelSU module, not a recovery ZIP."
  ui_print "! Please install it from the Magisk or KernelSU app."
  ui_print "*********************************************************"
  abort
fi

ui_print "*********************************************************"
ui_print "*         Installing Kernel Helper Pack for SM7325      *"
ui_print "*********************************************************"
ui_print "- Setting permissions..."

# Set permissions for the directory containing all the kernel modules
set_perm_recursive $MODPATH/system/vendor/lib/modules 0 2000 0755 0644 u:object_r:vendor_file:s0
ui_print "  - Kernel module permissions set."

# Check for the vendor_modprobe.sh helper and set its permissions
MODPROBE_HELPER=$MODPATH/system/vendor/bin/vendor_modprobe.sh
if [ -f "$MODPROBE_HELPER" ]; then
  set_perm $MODPROBE_HELPER 0 2000 0755 u:object_r:vendor_modinstall-sh_exec:s0
  ui_print "  - vendor_modprobe.sh permissions set."
fi

ui_print "- Installation complete."
EOF

# Create the standard, minimal META-INF scripts
echo "Creating standard META-INF scripts..."
cat <<EOF > "$MODULE_WORK_DIR/META-INF/com/google/android/updater-script"
# Magisk/KSU stub
EOF
cat <<EOF > "$MODULE_WORK_DIR/META-INF/com/google/android/update-binary"
#!/sbin/sh
OUTFD=\$2
ZIPFILE=\$3
. /data/adb/magisk/util_functions.sh
. \$ZIPFILE/customize.sh
exit 0
EOF
chmod 755 "$MODULE_WORK_DIR/META-INF/com/google/android/update-binary"

# 5. Copy the kernel modules and helper script into the module structure.
echo "Copying kernel modules..."
cp -r "$SOURCE_MODULES_DIR"/* "$MODULE_SYSTEM_DIR/vendor/lib/modules/"

if [ -f "$MODPROBE_SOURCE_SCRIPT" ]; then
    echo "Copying vendor_modprobe.sh..."
    mkdir -p "$MODULE_SYSTEM_DIR/vendor/bin"
    cp "$MODPROBE_SOURCE_SCRIPT" "$MODULE_SYSTEM_DIR/vendor/bin/"
else
    echo "WARNING: vendor_modprobe.sh not found in current directory, skipping."
fi

# 6. Package everything into a ZIP file.
echo "Creating flashable ZIP: $MODULE_ZIP_NAME..."
cd "$MODULE_WORK_DIR"
zip -r9 "../$MODULE_ZIP_NAME" ./*
cd ..

# 7. Final cleanup.
rm -rf "$MODULE_WORK_DIR"

echo "=============================================="
echo "Successfully created systemless module:"
echo "$MODULE_ZIP_NAME"
echo "=============================================="
