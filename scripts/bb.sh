#!/bin/bash
# Thin wrapper: source the OE build env (quietly) and run a bitbake* command.
# Usage: scripts/bb.sh <bitbake args...>   |   scripts/bb.sh --layers   (show-layers)
set -e
cd "$(dirname "$0")/.."
source sources/oe-core/oe-init-build-env build >/dev/null 2>&1
if [ "$1" = "--layers" ]; then shift; exec bitbake-layers show-layers "$@"; fi
exec bitbake "$@"
