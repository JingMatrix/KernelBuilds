# Custom Kernel Build System

This repository contains a comprehensive build system for a custom kernel, specifically tailored for the Samsung Galaxy A52s (sm7325). It is designed to automate the entire process from compilation to packaging, producing ready-to-flash binaries and a companion helper module for a clean, systemless installation.

### Credits

*   **Original Script:** BlackMesa123 @2023
*   **Adaptation & Modification:** RisenID @2024
*   **Architectural Improvements & vbmeta Spoofing:** JingMatrix @2025

## Key Features

*   **Automated Environment:** Checks for dependencies and sets up the Clang toolchain automatically.
*   **Multi-Variant Support:** Dynamically builds for different device regions (e.g., `a52sxqxx`, `a52sxqks`) based on the contents of the `firmware` directory.
*   **Advanced `vbmeta` Generation:** Rebuilds `vbmeta.img` to be internally consistent with the new kernel hashes, ensuring bootloader compatibility on unlocked devices.
*   **Systemless Helper Module:** The `pack_modules.sh` script packages kernel modules (`.ko` files) and runtime scripts into a flashable Magisk/KernelSU module for a safe, systemless installation.

## Prerequisites

Before building, you must install several essential tools on your system (preferably a Debian-based Linux distribution).

```bash
sudo apt update
sudo apt install git wget tar make ccache python3 build-essential openssl
```

## Directory Structure

The project relies on a specific directory layout.

```
kernel-build/            (This repository, the project root)
├── build.sh             (Builds the kernel images)
├── pack_modules.sh      (Builds the helper module)
├── toolchains/          (Directory for local build tools)
│   ├── AIK_ARM/
│   └── avb/
├── sm7325/              (Your kernel source code goes here)
├── firmware/            (Stock firmware images go here)
└── builds/              (Output directory for compiled images)
```

## The `firmware` Directory

The `firmware` directory is the foundation of the build process. The script dynamically detects which device variants to build based on the subdirectories present here.

**You must create and populate this directory yourself.** You can extract the required images from official Samsung firmware packages. For a variant to be built, its subdirectory must contain `boot.img`, `vendor_boot.img`, `dtbo.img`, and `vbmeta.img`.

### Example Structure
To build for the European (`a52sxqxx`) and Korean (`a52sxqks`) variants:
```
firmware/
├── a52sxqxx/
│   ├── boot.img, dtbo.img, vbmeta.img, vendor_boot.img
└── a52sxqks/
    ├── boot.img, dtbo.img, vbmeta.img, vendor_boot.img
```

## The Build Process: A Two-Step Guide

### Step 1: Prepare the Environment
1.  **Clone this repository (`kernel-build`) and navigate into it.**
2.  **Initialize Toolchains:** If using Git submodules, run `git submodule update --init --recursive`.
3.  **Place Kernel Source:** Place your kernel source code inside the `kernel-build` directory and name it `sm7325`.
4.  **Select Kernel Branch:** The build script checks the current branch of your kernel source.
    *   For Samsung's stock **OneUI** ROM: `git checkout oneui-ksu`
    *   For **AOSP-based custom ROMs**: `git checkout aosp-ksu`
5.  **Populate Firmware:** Create and fill the `firmware` directory as explained above.

### Step 2: Run the Build Scripts

First, build the main kernel images. Then, package the helper module.

1.  **Build Kernel Images:**
    ```bash
    ./build.sh
    ```
    This compiles the kernel and creates the modified `boot.img`, `dtbo.img`, `vendor_boot.img`, and the special `vbmeta.img` inside the `builds/` directory.

2.  **Build the Helper Module:**
    ```bash
    ./pack_modules.sh
    ```
    This script packages the compiled kernel modules (`.ko` files) and runtime scripts into a flashable ZIP file. **This ZIP file will be created in the main `kernel-build` directory.**

## Flashing & Installation

### Step 1: Flash Kernel Images via Heimdall
1.  **Install Heimdall:** It is recommended to build the latest version from this fork: [https://git.sr.ht/~grimler/Heimdall](https://git.sr.ht/~grimler/Heimdall).
2.  **Reboot to Download Mode:** With your phone connected, run `adb reboot download`.
3.  **Flash:** Navigate to the output directory for your variant (e.g., `cd builds/a52sxqxx/`) and run the flash command:
    ```bash
    heimdall flash --VBMETA vbmeta.img --BOOT boot.img --DTBO dtbo.img --VENDOR_BOOT vendor_boot.img
    ```
    *Note: `sudo` may be required if you haven't set up udev rules for your user to access the USB device.*

### Step 2: Install the Helper Module
After your device reboots into Android, you are advised to install the helper module.

1.  **Transfer the ZIP:** Locate the module ZIP file created by `pack_modules.sh` in the main `kernel-build` directory and copy it to your phone.
2.  **Install via App:**
    *   Open the **Magisk** or **KernelSU** app.
    *   Go to the **Modules** section.
    *   Tap **Install from storage** and select the ZIP file.
3.  **Reboot:** Reboot your device when prompted.

## Technical Details: The Two-Part Integrity Spoof

This system uses a two-part approach to create a bootable kernel that can serve as a base for passing integrity checks.

### Part 1: The `vbmeta.img` Foundation
The `build.sh` script creates a `vbmeta.img` with two key characteristics:
*   **It is bootable:** It is created with **`--flags 2`**, which sets the `VERIFICATION_DISABLED` flag. This instructs the bootloader to skip the main signature check, allowing the device to boot without a "public key mismatch" error.
*   **It is internally consistent:** It contains the correct SHA hashes of our custom-built `boot.img`, `dtbo.img`, and `vendor_boot.img`.

However, using `--flags 2` creates a new problem: the bootloader sees verification is disabled and, as a result, **does not set the `ro.boot.vbmeta.*` properties** at all. This absence is itself a clear sign of tampering. This is where the helper module is essential.

### Part 2: The Helper Module's Runtime Spoof
The helper module serves two critical functions:

1.  **Systemless Module Loading:** Its primary job is to package all the necessary kernel modules (`.ko` driver files) into a safe, systemless module. This means your `/vendor` partition is never modified.
2.  **A52s Camera Fix:** The module automatically detects if it is being installed on a Galaxy A52s and applies a systemless patch to the camera libraries. This fixes the common "camera crash" issue that occurs on devices with an unlocked bootloader.
3.  **Runtime Property Injection:** The `service.sh` script within the helper module is specifically designed to fix the problem created by the bootable `vbmeta`. It runs at boot and uses `resetprop` to **add the missing `ro.boot.vbmeta.*` properties back into the system**. By providing these properties, it spoofs a clean, stock boot environment and provides the necessary foundation for passing integrity checks.

---

## Bonus: A Note on Bypassing Advanced Integrity Checks

The kernel and helper module provide the foundation for hiding modifications. However, the most sophisticated detection methods may require additional community tools.

After installing this kernel and the helper module, to bypass certain checks, the following tools may be required. It is crucial to understand that there are two distinct layers of security checks an application can perform, each requiring a different tool to address.

### 1. The Software Layer (Device Profile Checks)

This layer includes checks where an application verifies the device's software profile by reading properties from the Android framework.

*   **How the Check Works:** An application reads a collection of properties directly from standard Android classes like `android.os.Build`. To be convincing, these properties must be **coherent**—for example, the `Build.FINGERPRINT` must be consistent with the `Build.MODEL`, `Build.BRAND`, `Build.ID`, etc. An unlocked or custom ROM device will present an incoherent or non-certified profile.

*   **Tool:** **[Play Integrity Fix](https://github.com/JingMatrix/PlayIntegratyFix)**
*   **Primary Function:** Its core function is to spoof the device's software profile with a **complete and coherent set of properties** from a legitimate, certified device.
*   **Mechanism:** It employs a two-stage approach to achieve this:
    1.  **System-Wide Baseline Spoofing (via `resetprop`):** During the early boot process, the module performs a **system-wide** modification of common, low-level properties that indicate a rooted state (e.g., setting `ro.debuggable` to `0`, `ro.build.tags` to `release-keys`, and resetting vendor warranty flags). This establishes a clean "factory-like" foundation across the entire OS.
    2.  **Targeted Profile Injection (via Zygisk):** The main, high-precision attack is reserved almost exclusively for the **Google Play Services process** (`com.google.android.gms.unstable`). It injects code that loads a full device profile from a JSON file and **directly modifies the static fields of the `android.os.Build` class within the GMS process's memory.** This spoofs the detailed device fingerprint only where it is most critically inspected.

### 2. The Hardware Layer (Hardware-Backed Integrity Checks)

This is the deepest level of security, where an application directly queries the secure hardware for a cryptographic proof of the device's boot integrity. This process has two phases: **local generation** and **chain verification**.

**Phase A: The Local Generation (The Offline Check)**

*   **How the Check Works:** An application, **entirely on the device and offline**, asks the secure hardware (TEE) to generate a **Key Attestation** certificate. This certificate is a cryptographic report containing the device's **true boot state** (e.g., `deviceLocked: false`). An offline detector app can read this report and immediately see the unlocked state.

*   **Tool:** **[TrickyStoreOSS](https://github.com/beakthoven/TrickyStoreOSS)**
*   **Mechanism:** **TrickyStore is essential for bypassing this local, offline check.** It intercepts the communication with the hardware and performs **cryptographic surgery** on the certificate *before* it is returned to the app. It replaces the true, unfavorable boot state data with a forged, "perfect" one. The local detector app is thus fooled because it receives a fraudulent report.

**Phase B: The Chain Verification (The Online Check)**

*   **How the Check Works:** After receiving the certificate, a security-conscious service (like Google Play) needs to confirm it wasn't forged. It does this by checking the signature on the certificate. It follows the chain of signatures up to a root authority. **Google's servers maintain a list of trusted hardware root authorities.**

*   **Tool:** A valid **`keybox`** from a certified device.
*   **Mechanism:** When TrickyStore forges the certificate in Phase A, it must re-sign it. It uses the private key from your user-provided `keybox` to do this. When Google's servers receive the certificate, they check its signature chain. If the `keybox` chain leads back to a root authority that is on their list of trusted hardware, the check passes. If the `keybox` is from an uncertified device or is self-signed, the chain verification will fail.

**In Summary:**
*   **TrickyStore** is what bypasses the **local detection** by forging the *content* of the attestation report. It is always required for hardware-level checks.
*   A **valid `keybox`** is what bypasses the **online verification** by providing a trusted *signature* for the forged report. The offline/online distinction primarily affects whether the `keybox`'s signature chain can be authoritatively verified.
