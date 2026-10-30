#!/usr/bin/env bash
# On-demand hardware test of meta-riscv master on the VisionFive 2 bench.
# Per leg: build vf2-selftest-image, netboot it over ens4, collect the boot-time
# self-test & compare it with that leg's previous run; then boot the SD card again.
# Usage: hw-ci-run.sh [vendor|mainline|next|all]...     (default: all)
#   vendor    meta-riscv's machine kernel, linux-starfive-dev
#   mainline  meta-riscv's linux-mainline (stable), the reference for next
#   next      linux-mainline built from the newest linux-next tag
# Env: PORT (serial, /dev/ttyUSB0), HOST_IP (192.168.50.1), RUNS (results root)
# Needs: dnsmasq from `sudo scripts/ens4-dhcp.sh`, the board cabled to ens4.
set -euo pipefail
top="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-/dev/ttyUSB0}"
HOST_IP="${HOST_IP:-192.168.50.1}"
RUNS="${RUNS:-$top/private-notes/ci-runner/runs}"
SRC="$top/sources/ci"
TFTP="$top/tftp/visionfive2"
NEXT_URL="https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git"
UPLOAD_PORT=8766

legs="${*:-all}"
[ "$legs" = all ] && legs="vendor mainline next"
for l in $legs; do
    case "$l" in vendor|mainline|next) ;; *) sed -n 5,10p "$0" >&2; exit 2 ;; esac
done

say() { printf '\n[hw-ci] %s\n' "$*"; }
die() { printf '[hw-ci] %s\n' "$*" >&2; exit 1; }

# The bench is shared with ad hoc work: a held lock or a staged boot.scr means
# someone is using it, so stop instead of rebooting the board under them.
exec 9>"$top/.bench.lock"
flock -n 9 || die "bench busy: another run holds $top/.bench.lock"
[ -e "$TFTP/boot.scr" ] && die "a netboot is staged ($TFTP/boot.scr); remove it with scripts/stage-ens4-netboot.sh --off if the bench is free"
pgrep -x dnsmasq >/dev/null || die "dnsmasq is not running: sudo scripts/ens4-dhcp.sh"
[ -e "$PORT" ] || die "no serial console at $PORT"

# CI builds from its own detached worktrees, so ad hoc checkouts stay untouched.
say "updating sources to upstream master"
mkdir -p "$SRC"
for r in bitbake oe-core meta-riscv; do
    git -C "$top/sources/$r" fetch -q origin master
    rev="$(git -C "$top/sources/$r" rev-parse FETCH_HEAD)"
    if [ -d "$SRC/$r" ]; then
        git -C "$SRC/$r" checkout -q --detach "$rev"
    else
        git -C "$top/sources/$r" worktree add -q --detach "$SRC/$r" "$rev"
    fi
done

setup_build() {   # LEG BUILDDIR
    local leg="$1" b="$2"
    mkdir -p "$b/conf" "$b/no-hooks"
    if [ ! -f "$b/conf/local.conf" ]; then
        sed -e 's/^BB_NUMBER_THREADS ?= .*/BB_NUMBER_THREADS ?= "24"/' \
            -e 's/^PARALLEL_MAKE ?= .*/PARALLEL_MAKE ?= "-j 36"/' \
            "$top/meta-vf2-selftest/conf/templates/default/local.conf.sample" > "$b/conf/local.conf"
        printf '\nIMAGE_FSTYPES:append = " cpio.gz"\nINITRAMFS_MAXSIZE = "1048576"\n' >> "$b/conf/local.conf"
    fi
    cat > "$b/conf/bblayers.conf" <<EOF
LCONF_VERSION = "7"
BBPATH = "\${TOPDIR}"
BBFILES ?= ""
BBLAYERS ?= "$SRC/oe-core/meta $SRC/meta-riscv $top/meta-vf2-selftest"
EOF
    # The PowerVR DDK's unpack runs `git lfs install`, which fails beside a
    # global core.hooksPath; give BitBake a gitconfig without one.
    printf '[include]\n\tpath = %s/.gitconfig\n[core]\n\thooksPath = %s/no-hooks\n' "$HOME" "$b" > "$b/gitconfig"
    if [ "$leg" = next ]; then
        local tag rev
        tag="$(git ls-remote --tags --refs "$NEXT_URL" 'next-*' | sed 's#.*refs/tags/##' | sort | tail -n 1)"
        rev="$(git ls-remote "$NEXT_URL" "refs/tags/$tag^{}" | cut -f1)"
        [ -n "$tag" ] && [ -n "$rev" ] || die "could not resolve the newest linux-next tag"
        printf 'VF2_KERNEL = "next"\nVF2_NEXT_TAG = "%s"\nVF2_NEXT_REV = "%s"\n' "$tag" "$rev" > "$b/conf/auto.conf"
    else
        printf 'VF2_KERNEL = "%s"\n' "$leg" > "$b/conf/auto.conf"
    fi
}

bitbake_in() {   # BUILDDIR ARGS...
    local b="$1"; shift
    (
        export GIT_CONFIG_GLOBAL="$b/gitconfig" BB_ENV_PASSTHROUGH_ADDITIONS="GIT_CONFIG_GLOBAL"
        export BITBAKEDIR="$SRC/bitbake"
        set +u
        # shellcheck disable=SC1091
        source "$SRC/oe-core/oe-init-build-env" "$b" >/dev/null
        set -u
        bitbake "$@"
    )
}

# The board posts its results as hex text: busybox wget --post-file stops at the
# first NUL byte & the image has no base64, but busybox has xxd.
fetch_results() {   # OUTDIR
    local out="$1" i
    for i in 1 2 3; do
        rm -f "$out/results.hex"
        python3 - "$out/results.hex" "$HOST_IP" "$UPLOAD_PORT" <<'EOF_PY' &
import http.server, socket, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        open(sys.argv[1], "wb").write(self.rfile.read(n))
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer((sys.argv[2], int(sys.argv[3])), H)
s.timeout = 60
s.handle_request()
EOF_PY
        local srv=$!
        until ss -ltn | grep -q ":$UPLOAD_PORT "; do :; done
        python3 "$top/scripts/vf2-shell.py" --port "$PORT" --tmo 60 --cmd \
            "tar czf - -C /var/log/vf2-selftest/latest/ . | xxd -p > /tmp/r.hex && wget -q -O /dev/null --post-file=/tmp/r.hex http://$HOST_IP:$UPLOAD_PORT/" \
            >> "$out/console.log" 2>&1 || true
        wait "$srv" || true
        if [ -s "$out/results.hex" ] && xxd -r -p "$out/results.hex" | tar xzf - -C "$out" 2>/dev/null; then
            rm -f "$out/results.hex"; return 0
        fi
        say "results upload failed (attempt $i)"
    done
    return 1
}

summary=""
for leg in $legs; do
    b="$top/build-ci-$leg"
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    out="$RUNS/$stamp-$leg"
    mkdir -p "$out"
    setup_build "$leg" "$b"
    {
        echo "leg: $leg"
        echo "date: $stamp"
        for r in bitbake oe-core meta-riscv; do echo "$r: $(git -C "$SRC/$r" log -1 --format='%h %s')"; done
        echo "meta-vf2-selftest: $(git -C "$top/meta-vf2-selftest" log -1 --format='%h %s')$(git -C "$top/meta-vf2-selftest" diff --quiet HEAD || echo ' (+uncommitted)')"
        cat "$b/conf/auto.conf"
    } > "$out/manifest.txt"

    say "$leg: building vf2-selftest-image (log: $out/build.log)"
    if ! bitbake_in "$b" vf2-selftest-image > "$out/build.log" 2>&1; then
        summary="$summary\n$leg: BUILD FAILED, see $out/build.log"
        grep -E '^ERROR' "$out/build.log" | head -n 5 >&2 || true
        continue
    fi

    deploy="$b/tmp/deploy/images/visionfive2"
    say "$leg: netbooting"
    "$top/scripts/stage-ens4-netboot.sh" "$deploy/Image" \
        "$deploy/jh7110-starfive-visionfive-2-v1.3b.dtb" \
        "$deploy/vf2-selftest-image-visionfive2.rootfs.cpio.gz" > /dev/null
    booted=0
    python3 "$top/scripts/vf2-console-wait.py" --port "$PORT" --tmo 900 \
        --until '=== VF2-SELFTEST END rc=[0-9]+' --log "$out/console.log" > /dev/null && booted=1
    "$top/scripts/stage-ens4-netboot.sh" --off > /dev/null

    if [ "$booted" = 1 ] && fetch_results "$out"; then
        prev="$(readlink -f "$RUNS/latest-$leg" 2>/dev/null || true)"
        fails="$(awk -F'\t' '$2 == "FAIL"' "$out/results.tsv" | wc -l)"
        line="$leg: $fails FAIL"
        if [ -n "$prev" ] && [ -f "$prev/results.tsv" ]; then
            sh "$top/meta-vf2-selftest/recipes-support/vf2-selftest/files/vf2-selftest" --compare \
                "previous=$prev/results.tsv" "this=$out/results.tsv" > "$out/compare.md" || true
            line="$line; compared with $(basename "$prev") in compare.md"
        fi
        ref="$(readlink -f "$RUNS/latest-mainline" 2>/dev/null || true)"
        if [ "$leg" = next ] && [ -n "$ref" ] && [ -f "$ref/results.tsv" ]; then
            sh "$top/meta-vf2-selftest/recipes-support/vf2-selftest/files/vf2-selftest" --compare \
                "mainline=$ref/results.tsv" "next=$out/results.tsv" > "$out/compare-mainline.md" || true
            line="$line; against mainline in compare-mainline.md"
        fi
        ln -sfn "$out" "$RUNS/latest-$leg"
        summary="$summary\n$line ($out)"
    else
        summary="$summary\n$leg: NO RESULTS (boot or upload failed), console in $out/console.log"
    fi
done

# Hand the bench back on its SD card.
say "rebooting the board to its SD card"
python3 "$top/scripts/vf2-console-wait.py" --port "$PORT" --tmo 120 --until 'login:' > /dev/null || true
printf '%b\n' "$summary"
