#!/bin/bash
# bb.sh for the minimal self-test builds: build-selftest/ (mainline kernel) or
# build-selftest-vendor/ (--vendor), seeded from meta-vf2-selftest's templates.
# Usage: scripts/bb-selftest.sh [--vendor] <bitbake args...>  |  ... [--vendor] --layers
set -e
cd "$(dirname "$0")/.."
kernel=mainline; dir=build-selftest
if [ "$1" = "--vendor" ]; then kernel=vendor; dir=build-selftest-vendor; shift; fi
export TEMPLATECONF="$PWD/meta-vf2-selftest/conf/templates/default"
source sources/oe-core/oe-init-build-env "$dir" >/dev/null 2>&1
# The kernel choice lives in auto.conf so local.conf stays identical across both.
echo "VF2_KERNEL = \"$kernel\"" > conf/auto.conf
if [ "$1" = "--layers" ]; then shift; exec bitbake-layers show-layers "$@"; fi
exec bitbake "$@"
