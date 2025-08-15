#!/bin/bash
#
# KLM to Magisk/KSU Module Packager
# Coded by JingMatrix @2025
#
# This script takes the compiled kernel modules from a kernel build
# and packages them into a flashable Magisk/KernelSU module ZIP.
# It also includes device-specific fixes in the installer.
#

set -e

# --- Module Configuration ---
MODULE_ID="sm7325-klm"
MODULE_NAME="Kernel Modules for SM7325"
MODULE_VERSION="1.1-$(date +%Y%m%d)" # Version incremented for new feature
MODULE_AUTHOR="JingMatrix"
MODULE_DESC="Installs kernel modules and applies camera fix for the Galaxy A52s."

# --- Path Configuration ---
# Assumes this script is in `kernel-build` and builds are in `builds`
BUILDS_DIR="$(pwd)/builds"
MODULE_WORK_DIR="$(pwd)/module_temp"
# Path to your custom modprobe helper script
MODPROBE_SOURCE_SCRIPT="vendor_modprobe.sh"

# --- Script Logic (DO NOT EDIT BELOW THIS LINE) ---

echo "=============================================="
echo "Magisk/KSU Module Packager"
echo "=============================================="

# 1. Find the latest built variant to source modules from.
if [ ! -d "$BUILDS_DIR" ] || [ -z "$(ls -A "$BUILDS_DIR")" ]; then
    echo "ERROR: Output directory '$BUILDS_DIR' is empty or does not exist."
    echo "Please run the main kernel build script first."
    exit 1
fi
LATEST_VARIANT_PATH=$(ls -td -- "$BUILDS_DIR"/*/ | head -n 1)
SOURCE_MODULES_DIR="${LATEST_VARIANT_PATH}modules"

if [ ! -d "$SOURCE_MODULES_DIR" ]; then
    echo "ERROR: Could not find a 'modules' directory in the latest build: $LATEST_VARIANT_PATH"
    exit 1
fi
echo "Found modules to package from: $(basename "$LATEST_VARIANT_PATH")"

# 2. Clean up and create the working directory structure.
FINAL_ZIP_NAME="${MODULE_ID}-${MODULE_VERSION}.zip"
echo "Cleaning up previous build..."
rm -rf "$MODULE_WORK_DIR"
rm -f "$FINAL_ZIP_NAME"

echo "Creating module structure..."
MODULE_SYSTEM_DIR="$MODULE_WORK_DIR/system"
mkdir -p "$MODULE_SYSTEM_DIR"
mkdir -p "$MODULE_WORK_DIR/META-INF/com/google/android"

# 3. Create the Magisk/KSU metadata files.

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

# Create customize.sh - This is the new installer logic.
echo "Creating customize.sh with camera fix..."
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

# Set permissions for modules and scripts first.
ui_print "- Setting base permissions..."
set_perm_recursive $MODPATH/system/vendor/lib/modules 0 2000 0755 0644 u:object_r:vendor_file:s0
MODPROBE_HELPER=$MODPATH/system/vendor/bin/vendor_modprobe.sh
if [ -f "$MODPROBE_HELPER" ]; then
  set_perm $MODPROBE_HELPER 0 2000 0755 u:object_r:vendor_modinstall-sh_exec:s0
fi

# --- Device Specific Fixes ---
# Credits to ddavidavidd @Telegram for the camera fix method.

DEVICE=$(getprop ro.product.device)
if [[ "$DEVICE" == "a52s" || "$DEVICE" == "a52sxq" ]]; then
  ui_print "- Device is A52s, checking for camera fix..."
  CAMERA_LIB="/vendor/lib64/hw/camera.qcom.so"
  
  if [ -f "$CAMERA_LIB" ] && grep -q "ro.boot.flash.locked" "$CAMERA_LIB"; then
    ui_print "- Applying camera library patch..."
    
    # Create the directory structure within the module
    mkdir -p "$MODPATH/system/vendor/lib64/hw"
    
    # Use sed to patch the library and place the MODIFIED version in the module directory.
    # This leaves the original file untouched on the /vendor partition.
    sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "$CAMERA_LIB" > "$MODPATH$CAMERA_LIB"
    
    # Set the correct permissions and context on the NEW file inside the module.
    set_perm "$MODPATH$CAMERA_LIB" 0 0 0644 u:object_r:vendor_file:s0
    ui_print "- Camera fix applied systemlessly."
  else
    ui_print "- Camera library does not require patching."
  fi
else
  ui_print "- Not an A52s, skipping camera fix."
fi

ui_print "- Installation complete."

EOF

# Create the standard, minimal META-INF scripts
echo "Creating standard META-INF scripts..."
cat <<EOF > "$MODULE_WORK_DIR/META-INF/com/google/android/updater-script"
# Magisk/KSU stub
# Real installation logic is in customize.sh
EOF

cat <<EOF > "$MODULE_WORK_DIR/META-INF/com/google/android/update-binary"
#!/sbin/sh
# Magisk/KSU Installer stub
OUTFD=\$2
ZIPFILE=\$3
. /data/adb/magisk/util_functions.sh
. \$ZIPFILE/customize.sh
exit 0
EOF

chmod 755 "$MODULE_WORK_DIR/META-INF/com/google/android/update-binary"

# 4. Copy the kernel modules and helper scripts into the structure.
echo "Copying kernel modules..."
cp -r "$SOURCE_MODULES_DIR"/* "$MODULE_SYSTEM_DIR/"

if [ -f "$MODPROBE_SOURCE_SCRIPT" ]; then
    echo "Copying vendor_modprobe.sh..."
    mkdir -p "$MODULE_SYSTEM_DIR/vendor/bin"
    cp "$MODPROBE_SOURCE_SCRIPT" "$MODULE_SYSTEM_DIR/vendor/bin/"
else
    echo "WARNING: vendor_modprobe.sh not found, skipping."
fi

# 5. Package everything into a ZIP file.
echo "Creating flashable ZIP: $FINAL_ZIP_NAME..."
cd "$MODULE_WORK_DIR"
zip -r9 "../$FINAL_ZIP_NAME" ./*
cd ..

# 6. Final cleanup.
rm -rf "$MODULE_WORK_DIR"

echo "=============================================="
echo "Successfully created module:"
echo "$FINAL_ZIP_NAME"
echo "You can now flash this file using the Magisk or KernelSU app."
echo "=============================================="
