#!/usr/bin/env bash
# Build MCUboot for an Espressif chip with the ESP-IDF version that the
# checked-out commit's ci/espressif_install.sh asks for. Each version is
# installed under $HOME on first use, so onboarding can walk back across
# ESP-IDF upgrades.
#
# Usage (from the repository root): esp-build.sh <chip>

set -eo pipefail

chip=$1

idf_version=$(grep -oE -- '--branch[= ]+[^ ]+' ci/espressif_install.sh | head -1 | sed -E 's/--branch[= ]+//')
if [ -z "$idf_version" ]; then
    echo "error: no ESP-IDF version found in ci/espressif_install.sh" >&2
    exit 1
fi
echo "Using ESP-IDF $idf_version"

mcuboot_idf_path=$HOME/esp-idf-$idf_version
if [ ! -f "$mcuboot_idf_path/.membrowse-installed" ]; then
    rm -rf "$mcuboot_idf_path"
    git clone --depth=1 --branch "$idf_version" https://github.com/espressif/esp-idf.git "$mcuboot_idf_path"
    "$mcuboot_idf_path/install.sh" "$chip"
    touch "$mcuboot_idf_path/.membrowse-installed"
fi

# export.sh can clobber variables of the shell sourcing it (v6.0 resets
# idf_path), hence the prefixed name above.
. "$mcuboot_idf_path/export.sh"

build_dir=.build-$chip
cmake -DCMAKE_TOOLCHAIN_FILE="$PWD/boot/espressif/tools/toolchain-$chip.cmake" \
      -DMCUBOOT_TARGET="$chip" \
      -DMCUBOOT_CONFIG_FILE="$PWD/boot/espressif/port/$chip/bootloader.conf" \
      -DESP_HAL_PATH="$mcuboot_idf_path" \
      -B "$build_dir" "$PWD/boot/espressif"
cmake --build "$build_dir"
