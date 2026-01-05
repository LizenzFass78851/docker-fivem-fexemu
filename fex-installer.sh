#!/bin/bash
set -euo pipefail

# --------------------------------------------------------------------------------

check_kernel_version() {
    KERNEL_VERSION=$(uname -r | cut -d- -f1)

    kernel_ge_5_15() {
        local major minor
        IFS='.' read -r major minor _ <<< "$KERNEL_VERSION"

        if (( major > 5 )); then
            return 0
        elif (( major == 5 && minor >= 15 )); then
            return 0
        else
            return 1
        fi
    }

    if ! kernel_ge_5_15; then
        echo "Kernel is too old. FEX needs 5.15 minimum." >&2
        echo "Detected kernel version: $KERNEL_VERSION" >&2
        exit 1
    fi
}

get_cpu_features_version() {
    local features

    # Mandatory feature sets
    local v8_1Mandatory=(atomics asimdrdm crc32)
    local v8_2Mandatory=(atomics asimdrdm crc32 dcpop)
    local v8_3Mandatory=(atomics asimdrdm crc32 dcpop fcma jscvt lrcpc paca pacg)
    local v8_4Mandatory=(atomics asimdrdm crc32 dcpop fcma jscvt lrcpc paca pacg asimddp flagm ilrcpc uscat)

    # Read CPU features
    features=$(awk -F: '/Features/ {print $2; exit}' /proc/cpuinfo)

    # Default minimum spec
    local arch_version="8.0"

    list_contains_required() {
        local haystack="$1"
        shift
        for req in "$@"; do
            if ! grep -qw "$req" <<< "$haystack"; then
                return 1
            fi
        done
        return 0
    }

    # We don't care beyond 8.4
    if list_contains_required "$features" "${v8_4Mandatory[@]}"; then
        arch_version="8.4"
    elif list_contains_required "$features" "${v8_3Mandatory[@]}"; then
        arch_version="8.3"
    elif list_contains_required "$features" "${v8_2Mandatory[@]}"; then
        arch_version="8.2"
    elif list_contains_required "$features" "${v8_1Mandatory[@]}"; then
        arch_version="8.1"
    fi

    echo "$arch_version"
}

# --------------------------------------------------------------------------------

if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "This script is intended to be run on an aarch64 (ARM64) system." >&2
    exit 1
fi

if ! grep -q "Ubuntu" /etc/lsb-release; then
    echo "This script is intended to be run on an Ubuntu-based system." >&2
    exit 1
fi

check_kernel_version

if ! grep -q -R "fex-emu" /etc/apt/sources.list* /etc/apt/sources.list.d/; then
    echo "FEX-EMU PPA not found. Please ensure you have added the FEX-EMU PPA." >&2
    echo "Use: sudo apt-get install software-properties-common" >&2
    echo "     sudo add-apt-repository ppa:fex-emu/fex" >&2
    exit 1
fi

# --------------------------------------------------------------------------------

CPUFEAT=$(get_cpu_features_version | awk -F. '{print $2; exit}')
echo "Detected CPU feature level: $CPUFEAT"

echo "Updating package lists..."
apt-get update

case "$CPUFEAT" in
    0|1) FEX_EMU_ARCH_REV="fex-emu-armv8.0" ;;
    2|3) FEX_EMU_ARCH_REV="fex-emu-armv8.2" ;;
    4)   FEX_EMU_ARCH_REV="fex-emu-armv8.4" ;;
    *)
        echo "Unsupported CPU revision: $CPUREV" >&2
        exit 1
        ;;
esac

# --------------------------------------------------------------------------------

echo "Using FEX package for architecture revision: $FEX_EMU_ARCH_REV"

echo "Installing FEX packages..."
NO_INSTALL_RECOMMENDS=${NO_INSTALL_RECOMMENDS:-0}
apt-get install -y $( if [ "$NO_INSTALL_RECOMMENDS" = "1" ]; then echo "--no-install-recommends"; fi ) "$FEX_EMU_ARCH_REV"

echo "Cleaning up..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "FEX installation completed successfully."
exit 0
