#!/usr/bin/env bash
# Build MCUboot's Zephyr port against a Zephyr release that matches the
# checked-out commit. MCUboot's own CI builds against Zephyr main, so a commit
# doesn't name a Zephyr version, but its .github/workflows/zephyr_build.yaml
# does name the Zephyr SDK version. The newest Zephyr release whose SDK has
# the same major.minor version is used. Each release and its SDK are
# installed under $HOME on first use, so onboarding can walk back across
# Zephyr upgrades.
#
# The MCUboot checkout is passed in as an extra Zephyr module, so the build
# uses this commit's code rather than the copy pinned in Zephyr's west.yml.
#
# Usage (from the repository root):
#   zephyr-build.sh <board> <build-dir> [cmake args...]

set -eo pipefail

board=$1
build_dir=$PWD/$2
shift 2
mcuboot=$PWD

# The modules the nRF52840 DK build needs (mcuboot itself is passed in).
projects='-.*,+cmsis,+cmsis_6,+hal_nordic,+libmetal,+mbedtls,+zcbor,+tf-psa-crypto'

sdk=$(sed -nE 's/^ *sdk-version: *([0-9.]+).*/\1/p' .github/workflows/zephyr_build.yaml | head -1)
if [ -z "$sdk" ]; then
    echo "error: no Zephyr SDK version found in .github/workflows/zephyr_build.yaml" >&2
    exit 1
fi

cache=$HOME/membrowse-zephyr
mkdir -p "$cache"

ref_file=$cache/sdk-${sdk%.*}.ref
if [ ! -s "$ref_file" ]; then
    for tag in $(git ls-remote --tags --refs https://github.com/zephyrproject-rtos/zephyr |
                 sed -n 's#.*refs/tags/\(v[0-9]*\.[0-9]*\.[0-9]*\)$#\1#p' | sort -Vr); do
        # The Zephyr CI container has no curl.
        tag_sdk=$(python3 -c 'import sys, urllib.request; print(urllib.request.urlopen(sys.argv[1]).read().decode().strip())' \
                  "https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/$tag/SDK_VERSION" 2>/dev/null || true)
        if [ "${tag_sdk%.*}" = "${sdk%.*}" ]; then
            echo "$tag" > "$ref_file"
            break
        fi
    done
fi
if [ ! -s "$ref_file" ]; then
    echo "error: no Zephyr release uses SDK ${sdk%.*}.x" >&2
    exit 1
fi
zephyr_ref=$(cat "$ref_file")

ws=$cache/$zephyr_ref
if [ ! -f "$ws/.membrowse-installed" ]; then
    rm -rf "$ws"
    git clone --depth 1 --branch "$zephyr_ref" https://github.com/zephyrproject-rtos/zephyr "$ws/zephyr"
    python3 -m venv "$ws/.venv"
    . "$ws/.venv/bin/activate"
    # MCUboot's requirements cover imgtool, which the build runs to embed the key.
    pip install west -r "$ws/zephyr/scripts/requirements-base.txt" -r "$mcuboot/scripts/requirements.txt"
    (
        cd "$ws"
        west init -l zephyr
        west config manifest.project-filter -- "$projects"
        west update --narrow -o=--depth=1
        west sdk install -b "$cache" -H -t arm-zephyr-eabi \
            ${GITHUB_TOKEN:+--personal-access-token "$GITHUB_TOKEN"}
    )
    touch "$ws/.membrowse-installed"
fi

. "$ws/.venv/bin/activate"
export ZEPHYR_BASE=$ws/zephyr
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export ZEPHYR_SDK_INSTALL_DIR=$cache/zephyr-sdk-$(cat "$ZEPHYR_BASE/SDK_VERSION")
echo "Using Zephyr $zephyr_ref with SDK $(cat "$ZEPHYR_BASE/SDK_VERSION")"

cd "$ws"
west build -p always -b "$board" -d "$build_dir" "$mcuboot/boot/zephyr" -- \
    -DEXTRA_ZEPHYR_MODULES="$mcuboot" "$@"
