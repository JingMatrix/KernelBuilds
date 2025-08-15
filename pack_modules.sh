#!/bin/bash
#
# Final Magisk/KSU Systemless Module Packager
# Coded by JingMatrix @2025
#
# This script packages the compiled kernel modules and the
# vendor_modprobe.sh helper into a clean, systemless module.
#

set -e

# --- Module Configuration ---
MODULE_ID="sm7325-kernel-module-pack"
MODULE_NAME="Kernel Module Pack for SM7325"
MODULE_VERSION="1.0-$(date +%Y%m%d)"
MODULE_AUTHOR="JingMatrix"
MODULE_DESC="Systemless installation of kernel modules and the vendor_modprobe.sh helper."

# --- Path Configuration ---
# Assumes this script is in `kernel-build` and builds are in `builds`
BUILDS_DIR="$(pwd)/builds"
MODULE_WORK_DIR="$(pwd)/module_temp_final"
# The script will look for this file in the current directory (`kernel-build`)
MODPROBE_SOURCE_SCRIPT="vendor_modprobe.sh"

# --- Script Logic (DO NOT EDIT BELOW THIS LINE) ---

echo "=============================================="
echo "Final Systemless Module Packager"
echo "=============================================="

# 1. Find the latest built variant to source modules from.
if [ ! -d "$BUILDS_DIR" ] || [ -z "$(ls -A "$BUILDS_DIR")" ]; then
    echo "ERROR: Output directory '$BUILDS_DIR' is empty or does not exist."
    echo "Please run the main kernel build script first."
    exit 1
fi
LATEST_VARIANT_PATH=$(ls -td -- "$BUILDS_DIR"/*/ | head -n 1)
SOURCE_MODULES_DIR="${LATEST_VARIANT_PATH}modules/vendor/lib/modules"

if [ ! -d "$SOURCE_MODULES_DIR" ]; then
    echo "ERROR: Could not find the final 'modules' directory in: $LATEST_VARIANT_PATH"
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
mkdir -p "$MODULE_SYSTEM_DIR/vendor/lib/modules"
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

# Create customize.sh with the final permission-setting logic.
echo "Creating final customize.sh..."
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
ui_print "*      Installing Systemless Kernel Module Pack         *"
ui_print "*********************************************************"
ui_print "- Setting permissions..."

# Set permissions for the directory containing all the kernel modules
set_perm_recursive $MODPATH/system/vendor/lib/modules 0 2000 0755 0644 u:object_r:vendor_file:s0
ui_print "  - Kernel module permissions set."

# Check for the vendor_modprobe.sh helper and set its permissions
MODPROBE_HELPER=$MODPATH/system/vendor/bin/vendor_modprobe.sh
if [ -f "$MODPROBE_HELPER" ]; then
  # This sets owner 0 (root), group 2000 (shell), permissions 755 (rwxr-xr-x),
  # and the correct SELinux context for an executable in /vendor/bin.
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

# 4. Copy the kernel modules and helper script into the module structure.
echo "Copying kernel modules..."
cp -r "$SOURCE_MODULES_DIR"/* "$MODULE_SYSTEM_DIR/vendor/lib/modules/"

if [ -f "$MODPROBE_SOURCE_SCRIPT" ]; then
    echo "Copying vendor_modprobe.sh..."
    mkdir -p "$MODULE_SYSTEM_DIR/vendor/bin"
    cp "$MODPROBE_SOURCE_SCRIPT" "$MODULE_SYSTEM_DIR/vendor/bin/"
else
    echo "WARNING: vendor_modprobe.sh not found in current directory, skipping."
fi

# 5. Package everything into a ZIP file.
echo "Creating final flashable ZIP: $FINAL_ZIP_NAME..."
cd "$MODULE_WORK_DIR"
zip -r9 "../$FINAL_ZIP_NAME" ./*
cd ..

# 6. Final cleanup.
rm -rf "$MODULE_WORK_DIR"

echo "=============================================="
echo "Successfully created final systemless module:"
echo "$FINAL_ZIP_NAME"
echo "=============================================="
