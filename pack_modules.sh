#!/bin/bash
#
# Magisk/KSU Systemless Module Packager
# Coded by JingMatrix @2025
#
# This script packages compiled kernel modules and helper scripts
# into a clean, systemless "Kernel Helper" module using a highly
# modular, function-based design.
#
# SCRIPT ARCHITECTURE:
# 1. Setup Functions: Prepare the environment and calculate dynamic values.
# 2. Core Feature Functions: Self-contained functions that each package one
#    major feature (e.g., KLM Loading, Camera Fix).
# 3. Main Execution: A main() function that orchestrates the entire process.
#

set -e

# --- Configuration ---
MODULE_ID="sm7325-kernel-helper"
MODULE_NAME="Kernel Helper Pack for SM7325"
MODULE_VERSION="3.5-$(date +%Y%m%d)"
MODULE_AUTHOR="JingMatrix"
MODULE_DESC="Systemlessly installs kernel modules, applies runtime fixes, and spoofs boot properties."

# --- Path Configuration ---
BUILDS_DIR="$(pwd)/builds"
MODULE_WORK_DIR="$(pwd)/module_temp_work"
MODPROBE_SOURCE_SCRIPT="vendor_modprobe.sh"
MODULE_ZIP_NAME="${MODULE_ID}-${MODULE_VERSION}.zip"

# --- Global Variables (set by setup functions) ---
LATEST_VARIANT_PATH=""
SOURCE_MODULES_DIR=""
SOURCE_VBMETA_PATH=""
VBMETA_DIGEST=""
VBMETA_SIZE=""
CUSTOMIZE_SH_PATH=""


# =============================================================================
# === 1. SETUP AND UTILITY FUNCTIONS
# =============================================================================

# Finds the latest build output directory to source files from.
find_latest_build() {
    echo "Finding the latest build output..."
    if [ ! -d "$BUILDS_DIR" ] || [ -z "$(ls -A "$BUILDS_DIR")" ]; then
        echo "ERROR: Output directory '$BUILDS_DIR' is empty or does not exist." >&2
        exit 1
    fi
    LATEST_VARIANT_PATH=$(ls -td -- "$BUILDS_DIR"/*/ | head -n 1)
    SOURCE_MODULES_DIR="${LATEST_VARIANT_PATH}modules"
    SOURCE_VBMETA_PATH="${LATEST_VARIANT_PATH}vbmeta.img"

    if [ ! -d "$SOURCE_MODULES_DIR" ]; then
        echo "ERROR: Could not find the 'modules' directory in: $LATEST_VARIANT_PATH" >&2
        exit 1
    fi
    echo "Source build for packaging: $(basename "$LATEST_VARIANT_PATH")"
}

# Calculates the digest and size of the vbmeta.img for spoofing.
calculate_vbmeta_props() {
    echo "Calculating vbmeta properties for spoofing..."
    if [ ! -f "$SOURCE_VBMETA_PATH" ]; then
        echo "ERROR: Could not find vbmeta.img in '$LATEST_VARIANT_PATH'." >&2
        exit 1
    fi
    VBMETA_DIGEST=$(sha256sum "$SOURCE_VBMETA_PATH" | awk '{print $1}')
    VBMETA_SIZE=$(stat -c %s "$SOURCE_VBMETA_PATH")

    if [ -z "$VBMETA_DIGEST" ] || [ -z "$VBMETA_SIZE" ]; then
        echo "ERROR: Failed to calculate digest or size of vbmeta.img." >&2
        exit 1
    fi
    echo "Determined vbmeta digest: ${VBMETA_DIGEST}"
    echo "Determined vbmeta size: ${VBMETA_SIZE}"
}

# Cleans up old artifacts and creates the base directory structure.
create_base_module_structure() {
    echo "Creating base module structure..."
    rm -rf "$MODULE_WORK_DIR"
    rm -f "$MODULE_ZIP_NAME"
    mkdir -p "$MODULE_WORK_DIR/system"
    mkdir -p "$MODULE_WORK_DIR/META-INF/com/google/android"
    CUSTOMIZE_SH_PATH="$MODULE_WORK_DIR/customize.sh"
}

# =============================================================================
# === 2. CORE FEATURE PACKAGING FUNCTIONS
# =============================================================================

# Packages the Kernel Loadable Modules (KLM) and the modprobe helper.
build_feature_klm_loading() {
    echo "Packaging Feature: Kernel Module Loading"

    # --- Step 1: Copy module content ---
    echo "  -> Copying kernel modules..."
    mkdir -p "$MODULE_WORK_DIR/system"
    cp -a "$SOURCE_MODULES_DIR/vendor" "$MODULE_WORK_DIR/system/"

    if [ -f "$MODPROBE_SOURCE_SCRIPT" ]; then
        echo "  -> Copying vendor_modprobe.sh..."
        mkdir -p "$MODULE_WORK_DIR/system/vendor/bin"
        cp "$MODPROBE_SOURCE_SCRIPT" "$MODULE_WORK_DIR/system/vendor/bin/"
    else
        echo "  -> WARNING: vendor_modprobe.sh not found, skipping."
    fi

    # --- Step 2: Append installation logic to customize.sh ---
    cat <<'EOF' >> "$CUSTOMIZE_SH_PATH"

ui_print "- Setting Kernel Module Loading permissions..."
set_perm_recursive $MODPATH/system/vendor/lib/modules 0 2000 0755 0644 u:object_r:vendor_file:s0
MODPROBE_HELPER=$MODPATH/system/vendor/bin/vendor_modprobe.sh
if [ -f "$MODPROBE_HELPER" ]; then
  set_perm $MODPROBE_HELPER 0 2000 0755 u:object_r:vendor_modinstall-sh_exec:s0
  ui_print "  - Permissions set for kernel modules and modprobe helper."
else
  ui_print "  - Permissions set for kernel modules."
fi
EOF
}

# Packages the service.sh script to spoof VBMeta properties.
build_feature_vbmeta_spoof() {
    echo "Packaging Feature: VBMeta Property Spoofing"

    # --- Create the service.sh file with dynamic property values ---
    cat <<EOF > "$MODULE_WORK_DIR/service.sh"
#!/system/bin/sh
# Executed by Magisk/KernelSU to spoof vbmeta properties.
sleep 15
resetprop -n ro.boot.vbmeta.avb_version 1.0
resetprop -n ro.boot.vbmeta.device_state locked
resetprop -n ro.boot.vbmeta.digest ${VBMETA_DIGEST}
resetprop -n ro.boot.vbmeta.hash_alg sha256
resetprop -n ro.boot.vbmeta.invalidate_on_error yes
resetprop -n ro.boot.vbmeta.size ${VBMETA_SIZE}
resetprop -n ro.boot.verifiedbootstate green
log -p i -t KernelHelper "Successfully spoofed boot properties."
EOF
    chmod 755 "$MODULE_WORK_DIR/service.sh"
}

# Appends the A52s camera fix logic to the customize.sh script.
build_feature_camera_fix() {
    echo "Packaging Feature: A52s Camera Fix"

    # --- Append the robust, verbose camera fix logic to customize.sh ---
    cat <<'EOF' >> "$CUSTOMIZE_SH_PATH"

ui_print "- Checking for A52s camera fix..."
DEVICE_CODENAME=$(getprop ro.product.device)
if [[ "$DEVICE_CODENAME" == "a52s"* ]]; then
    ui_print "  - Device identified as Galaxy A52s ($DEVICE_CODENAME)."
    ui_print "  - Checking camera libraries for required patches..."

    PATCH_APPLIED=false

    # Create the necessary directories once to avoid repetition.
    mkdir -p "$MODPATH/system/vendor/lib/hw"
    mkdir -p "$MODPATH/system/vendor/lib64/hw"

    set_perm_recursive $MODPATH/system/vendor/lib 0 2000 0755 0644 u:object_r:vendor_file:s0
    set_perm_recursive $MODPATH/system/vendor/lib64 0 2000 0755 0644 u:object_r:vendor_file:s0
    ui_print "  - Set base permissions for vendor/lib and vendor/lib64."
    # --- Check, patch, and set permissions for each library individually ---

    # 64-bit main library
    if [ -f "/vendor/lib64/hw/camera.qcom.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib64/hw/camera.qcom.so; then
            ui_print "    - Patching /vendor/lib64/hw/camera.qcom.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib64/hw/camera.qcom.so" > "$MODPATH/system/vendor/lib64/hw/camera.qcom.so"
            set_perm "$MODPATH/system/vendor/lib64/hw/camera.qcom.so" 0 0 0644 u:object_r:vendor_file:s0
            PATCH_APPLIED=true
        else
            ui_print "    - Skipping /vendor/lib64/hw/camera.qcom.so (no patch needed)."
        fi
    fi

    # 64-bit override library
    if [ -f "/vendor/lib64/hw/com.qti.chi.override.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib64/hw/com.qti.chi.override.so; then
            ui_print "    - Patching /vendor/lib64/hw/com.qti.chi.override.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib64/hw/com.qti.chi.override.so" > "$MODPATH/system/vendor/lib64/hw/com.qti.chi.override.so"
            set_perm "$MODPATH/system/vendor/lib64/hw/com.qti.chi.override.so" 0 0 0644 u:object_r:vendor_file:s0
            PATCH_APPLIED=true
        else
            ui_print "    - Skipping /vendor/lib64/hw/com.qti.chi.override.so (no patch needed)."
        fi
    fi

    # 32-bit main library
    if [ -f "/vendor/lib/hw/camera.qcom.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib/hw/camera.qcom.so; then
            ui_print "    - Patching /vendor/lib/hw/camera.qcom.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib/hw/camera.qcom.so" > "$MODPATH/system/vendor/lib/hw/camera.qcom.so"
            set_perm "$MODPATH/system/vendor/lib/hw/camera.qcom.so" 0 0 0644 u:object_r:vendor_file:s0
            PATCH_APPLIED=true
        else
            ui_print "    - Skipping /vendor/lib/hw/camera.qcom.so (no patch needed)."
        fi
    fi

    # 32-bit override library
    if [ -f "/vendor/lib/hw/com.qti.chi.override.so" ]; then
        if grep -q 'ro.boot.flash.locked' /vendor/lib/hw/com.qti.chi.override.so; then
            ui_print "    - Patching /vendor/lib/hw/com.qti.chi.override.so..."
            sed 's/ro.boot.flash.locked/ro.camera.notify_nfc/g' "/vendor/lib/hw/com.qti.chi.override.so" > "$MODPATH/system/vendor/lib/hw/com.qti.chi.override.so"
            set_perm "$MODPATH/system/vendor/lib/hw/com.qti.chi.override.so" 0 0 0644 u:object_r:vendor_file:s0
            PATCH_APPLIED=true
        else
            ui_print "    - Skipping /vendor/lib/hw/com.qti.chi.override.so (no patch needed)."
        fi
    fi

    if $PATCH_APPLIED; then
        ui_print "  - Camera fix and permissions applied successfully."
    else
        ui_print "  - Camera patch check complete. No patches were required."
    fi
else
    ui_print "  - Device is not an A52s, skipping fix."
fi
EOF
}

# =============================================================================
# === 3. MAIN EXECUTION
# =============================================================================

main() {
    echo "=============================================="
    echo "Systemless Module Packager (Modular Design)"
    echo "=============================================="

    # --- Setup Phase ---
    find_latest_build
    calculate_vbmeta_props
    create_base_module_structure

    # --- Base Module File Generation ---
    # Create the initial module.prop and installer scripts that will be
    # appended to by the feature packaging functions.
    cat <<EOF > "$MODULE_WORK_DIR/module.prop"
id=$MODULE_ID
name=$MODULE_NAME
version=$MODULE_VERSION
versionCode=$(date +%Y%m%d)
author=$MODULE_AUTHOR
description=$MODULE_DESC
reboot=true
EOF

    cat <<'EOF' > "$CUSTOMIZE_SH_PATH"
#!/system/bin/sh
if [ -z "$MODPATH" ]; then
  ui_print "*********************************************************"
  ui_print "! This is a Magisk/KernelSU module, not a recovery ZIP."
  ui_print "! Please install it from the Magisk or KernelSU app."
  ui_print "*********************************************************"
  abort
fi
ui_print "***********************************"
ui_print "*  Installing Kernel Helper Pack  *"
ui_print "***********************************"
EOF

    cat <<EOF > "$MODULE_WORK_DIR/META-INF/com/google/android/updater-script"
# Magisk/KSU stub
EOF
    cat <<EOF > "$MODULE_WORK_DIR/META-INF/com/google/android/update-binary"
#!/sbin/sh
if [ -f /data/adb/magisk/util_functions.sh ]; then . /data/adb/magisk/util_functions.sh; else exit 1; fi
. \$ZIPFILE/customize.sh
exit 0
EOF
    chmod 755 "$MODULE_WORK_DIR/META-INF/com/google/android/update-binary"

    # --- Feature Packaging Phase ---
    # Call the core feature functions to populate the module.
    # To disable a feature, simply comment out its respective line.
    build_feature_klm_loading
    build_feature_vbmeta_spoof
    build_feature_camera_fix

    # touch $MODULE_WORK_DIR/skip_mount

    # Append a final footer to customize.sh
    echo 'ui_print "- Installation complete."' >> "$CUSTOMIZE_SH_PATH"

    # --- Finalization Phase ---
    echo "Creating flashable ZIP: $MODULE_ZIP_NAME..."
    cd "$MODULE_WORK_DIR"
    zip -r9 "../$MODULE_ZIP_NAME" ./* > /dev/null
    cd ..
    rm -rf "$MODULE_WORK_DIR"

    echo "=============================================="
    echo "Successfully created systemless module:"
    echo "$MODULE_ZIP_NAME"
    echo "=============================================="
}

# Run the main function
main
