# Custom Kernel Build System

This repository contains a build script for a custom kernel, specifically tailored for the Samsung Galaxy A52s (sm7325). This system is designed to automate the entire process from compilation to packaging, making kernel development and testing streamlined and repeatable.

The script automates dependency checks, toolchain setup, kernel compilation, and the patching of stock firmware images to produce ready-to-flash binaries.

### Credits

*   **Original Script:** BlackMesa123 @2023
*   **Adaptation & Modification:** RisenID @2024
*   **Architectural Improvements:** JingMatrix @2025

## Prerequisites

Before running the build script, you must have several essential tools installed on your system (preferably a Debian-based Linux distribution like Ubuntu).

You can install them by running:
```bash
sudo apt update
sudo apt install git wget tar make ccache python3 build-essential
```

## Directory Structure

The project relies on a specific directory layout. Please ensure your project is structured as follows:

```
.
├── kernel-build/        (This repository)
│   ├── build.sh         (The main build script)
│   ├── toolchains/      (Directory for local build tools)
│   │   ├── AIK_ARM/
│   │   ├── avb/
│   │   └── vbmeta-action-patcher/
│   └── README.md
├── sm7325/              (Your kernel source code goes here)
├── firmware/            (Stock firmware images go here, see below)
└── builds/              (Output directory for compiled files)
```

*   **`kernel-build/`**: The root of this build system. The `build.sh` script should be run from here.
*   **`toolchains/`**: Contains necessary binaries like Magiskboot, AVBtool, etc. If these are managed as Git submodules, initialize them with `git submodule update --init --recursive`.
*   **`sm7325/`**: The directory where your kernel source code must be located.
*   **`firmware/`**: **Crucial.** This directory holds the stock firmware images that the script will use as a base. It must be created and populated by you.
*   **`builds/`**: This directory is created automatically by the script and will contain all the final, flashable image files.

## Understanding the `firmware` Directory

The `firmware` directory is the foundation of the build process. Instead of hardcoding device variants, the script now dynamically detects which variants to build based on the subdirectories present here.

**You must create this directory and populate it yourself.** The script will **not** download these files for you. You can extract these from official Samsung firmware packages for your device.

### How it Works

1.  The build script scans the `firmware/` directory for subdirectories.
2.  Each subdirectory name corresponds to a specific device variant (e.g., `a52sxqxx`, `a52sxqks`).
3.  The script will attempt to build the kernel **only for the variants found as subdirectories**.
4.  For a variant to be built, its corresponding subdirectory must contain the following four stock image files:
    *   `boot.img`
    *   `vendor_boot.img`
    *   `dtbo.img`
    *   `vbmeta.img`

If any of these files are missing for a specific variant, the script will print a warning and skip building for that variant.

### Example Structure

To build for the European (`a52sxqxx`) and Korean (`a52sxqks`) variants, your `firmware` directory should look like this:

```
firmware/
├── a52sxqxx/
│   ├── boot.img
│   ├── dtbo.img
│   ├── vbmeta.img
│   └── vendor_boot.img
└── a52sxqks/
    ├── boot.img
    ├── dtbo.img
    ├── vbmeta.img
    └── vendor_boot.img
```

## How to Use

1.  **Clone this repository:**
    ```bash
    git clone <repository_url> kernel-build
    cd kernel-build
    ```

2.  **Initialize Toolchains:** If the `toolchains` directory uses Git submodules, initialize them:
    ```bash
    git submodule update --init --recursive
    ```

3.  **Prepare Kernel Source (`sm7325`)**:
    *   First, ensure your kernel source code is located in a directory named `sm7325` at the same level as the `kernel-build` directory.
    *   **Important: Select the Correct Kernel Source Branch.** The kernel source has different branches for different types of Android ROMs. The build script will check the branch and fail if it's not a valid one.
        *   For Samsung's stock **OneUI** ROM, use the `oneui-ksu` branch.
        *   For **AOSP-based custom ROMs**, use the `aosp-ksu` branch.

        Navigate to the kernel source directory and check out the correct branch **before** building:
        ```bash
        # Navigate to the kernel source
        cd ../sm7325

        # Example for building for OneUI:
        git checkout oneui-ksu

        # Example for building for AOSP ROMs:
        # git checkout aosp-ksu

        # Go back to the build script directory
        cd ../kernel-build
        ```

4.  **Populate Firmware:** Create the `firmware` directory and populate it with variant subdirectories and their corresponding stock images as explained above.

5.  **Run the Build Script:** Execute the main script.
    ```bash
    ./build.sh
    ```
    *   For a full clean build, use the `--clean` or `-c` flag:
        ```bash
        ./build.sh --clean
        ```

6.  **Find Your Files:** After a successful run, the script will create the `builds` directory. Inside, you will find a separate folder for each variant you built.

## Flashing Instructions

**Disclaimer:** Flashing custom binaries to your device carries inherent risks, including the potential to brick your device. Proceed with caution and at your own risk.

### 1. Install Heimdall

Heimdall is an open-source, cross-platform utility for flashing firmware onto Samsung devices. It is recommended to build the latest version from source to ensure device compatibility.

*   **Source Code:** [https://git.sr.ht/~grimler/Heimdall](https://git.sr.ht/~grimler/Heimdall)
*   Follow the build instructions in the `README.md` of the Heimdall repository. This typically involves installing dependencies like `build-essential`, `cmake`, `libusb-1.0-0-dev`, and `zlib1g-dev`.

### 2. Reboot to Download Mode

For Heimdall to recognize your device, it must be in Download Mode.

*   Ensure your phone is connected to your computer and USB Debugging is enabled and authorized.
*   Open a terminal and run the following command:
    ```bash
    adb reboot download
    ```
*   Your device will reboot and display a screen with a warning about custom OS installation. Follow the on-screen instructions to enter Download Mode.

### 3. Flash the Images

Navigate to the output directory containing the compiled files for the variant you wish to flash.

*   For example, if you built for the `a52sxqxx` variant:
    ```bash
    cd ../builds/a52sxqxx/
    ```

*   Once in the correct directory, run the following `heimdall` command to flash all the required partitions at once. The patched `vbmeta.img` will disable verification, allowing the custom kernel to boot.
    ```bash
    sudo heimdall flash --VBMETA vbmeta.img --BOOT boot.img --DTBO dtbo.img --VENDOR_BOOT vendor_boot.img
    ```

After the flash is complete, your device should reboot automatically with the new custom kernel.
