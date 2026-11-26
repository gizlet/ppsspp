#!/bin/sh
# Runs inside the runtime: PPSSPP's libraries all resolve, and the headless
# build passes upstream's CPU tests (pspautotests, part of PPSSPP's source)
# with the JIT and the IR interpreter, comparing each with its .expected output.
# It runs under QEMU as a Cortex-A35, the R36S's CPU, so the JIT only emits
# instructions that CPU has.
set -eu

tests=$1
cpu="/tmp/qemu-aarch64 -cpu cortex-a35"
export HOME=/tmp/smoke-home XDG_CONFIG_HOME=/tmp/smoke-home/.config
mkdir -p "$HOME"

for binary in /usr/lib/ppsspp/PPSSPPSDL /tmp/PPSSPPHeadless; do
    if ldd "$binary" | grep -q 'not found'; then
        ldd "$binary"
        echo "$binary has missing libraries" >&2
        exit 1
    fi
done
[ -f /usr/lib/ppsspp/assets/ppge_atlas.zim ] || { echo 'PPSSPP assets are missing' >&2; exit 1; }
[ -z "$(find /usr/lib/ppsspp/assets/flash0 -name '*.pgf')" ] || { echo 'flash0 fonts must not ship' >&2; exit 1; }

set -- cpu/cpu_alu/cpu_alu cpu/fpu/fpu cpu/lsu/lsu
for mode in -j --ir; do
    for test in "$@"; do
        $cpu /tmp/PPSSPPHeadless "$mode" --root "$tests/" --compare --timeout=120 --graphics=null \
            "$tests/$test.prx" > /tmp/smoke.log 2>&1 || { cat /tmp/smoke.log; echo "$test failed ($mode)" >&2; exit 1; }
        grep -q 'passed' /tmp/smoke.log || { cat /tmp/smoke.log; echo "$test did not pass ($mode)" >&2; exit 1; }
        echo "smoke: $test passed ($mode)"
    done
done
