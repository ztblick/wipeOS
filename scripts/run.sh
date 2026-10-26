#!/usr/bin/env bash
# Launch WipeOS in QEMU and report whether the boot succeeded (KR1.4).
# Builds the image unless --no-build, boots it, and exits with the
# result the stub prints in the boot log (D30):
#   0  WIPEOS RESULT=SUCCESS, then a clean shutdown
#   1  WIPEOS RESULT=FAIL, then a clean shutdown
#   2  anything else: build failure, no RESULT line, crash, kernel
#      panic, timeout, or no clean shutdown after the RESULT line
#   3  bad arguments
set -euo pipefail

# Paths come from the script's own location, so it runs from any
# directory and on any machine.
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BR=$REPO/buildroot
KERNEL=$BR/output/images/bzImage

usage() {
	cat <<'EOF'
Usage: scripts/run.sh [--mode dev|prod] [--mem N] [--pages auto|4k|1g]
                      [--accel auto|kvm|tcg] [--no-build] [--timeout SECONDS]
                      [--log PATH] [--test-fail]

  --mode       prod (default) powers off after the report; dev opens a shell
  --mem        guest RAM in GiB (default 1)
  --pages      auto (default): 4 KB pages up to 2 GiB, 1 GB pages from 3 GiB;
               4k: ordinary pages at any size; 1g: needs --mem 3 or more
  --accel      auto (default): KVM if this is an x86_64 host and /dev/kvm is
               usable, otherwise TCG (software emulation); kvm: KVM or exit 2;
               tcg: always software emulation
  --no-build   boot the existing image without rebuilding
  --timeout    seconds before the run is stopped (default 300 in prod, none in dev)
  --log        boot log path (default logs/run-<date>-<time>.log)
  --test-fail  make the stub report a failing check (negative test)
EOF
}

bad_usage() {
	echo "run.sh: $1" >&2
	usage >&2
	exit 3
}

need_value() {
	[ $# -ge 2 ] || bad_usage "$1 needs a value"
}

mode=prod mem=1 pages=auto accel=auto build=1 timeout_s= log= test_fail=0

while [ $# -gt 0 ]; do
	case $1 in
	--mode) need_value "$@"; mode=$2; shift 2 ;;
	--mem) need_value "$@"; mem=$2; shift 2 ;;
	--pages) need_value "$@"; pages=$2; shift 2 ;;
	--accel) need_value "$@"; accel=$2; shift 2 ;;
	--timeout) need_value "$@"; timeout_s=$2; shift 2 ;;
	--log) need_value "$@"; log=$2; shift 2 ;;
	--no-build) build=0; shift ;;
	--test-fail) test_fail=1; shift ;;
	-h | --help) usage; exit 0 ;;
	*) bad_usage "unknown argument: $1" ;;
	esac
done

case $mode in
dev | prod) ;;
*) bad_usage "--mode must be dev or prod" ;;
esac
[[ $mem =~ ^[1-9][0-9]*$ ]] || bad_usage "--mem must be a whole number of GiB, 1 or more"
case $pages in
auto | 4k | 1g) ;;
*) bad_usage "--pages must be auto, 4k or 1g" ;;
esac
case $accel in
auto | kvm | tcg) ;;
*) bad_usage "--accel must be auto, kvm or tcg" ;;
esac
if [ -n "$timeout_s" ] && ! [[ $timeout_s =~ ^[1-9][0-9]*$ ]]; then
	bad_usage "--timeout must be a whole number of seconds, 1 or more"
fi
if [ -z "$timeout_s" ] && [ "$mode" = prod ]; then
	timeout_s=300
fi

# The accelerator (D39), chosen before the build so that --accel kvm on a
# host without KVM fails at once. KVM runs an x86_64 guest on the host's
# own CPU, so it needs an x86_64 host and a /dev/kvm this user can open;
# TCG translates every guest instruction in software and works anywhere.
kvm_usable() {
	[ "$(uname -m)" = x86_64 ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]
}
case $accel in
auto)
	if kvm_usable; then accel=kvm; else accel=tcg; fi
	;;
kvm)
	if ! kvm_usable; then
		echo "run.sh: --accel kvm needs an x86_64 host and read-write" \
		     "access to /dev/kvm (host is $(uname -m))" >&2
		exit 2
	fi
	;;
esac

# Huge pages (D22). A 1 GB page needs a free, 1 GB-aligned gigabyte.
# The first gigabyte is always broken up (BIOS areas, the legacy hole,
# the kernel) and the top of guest RAM has a reserved region, so N-2
# pages is the safe count.
if [ "$pages" = auto ]; then
	if [ "$mem" -ge 3 ]; then pages=1g; else pages=4k; fi
fi
hugepages=0
cpu_args=()
page_args=
if [ "$pages" = 1g ]; then
	[ "$mem" -ge 3 ] || bad_usage "--pages 1g needs --mem 3 or more"
	hugepages=$((mem - 2))
	# QEMU's default CPU model doesn't advertise 1 GB page support.
	cpu_args=(-cpu max)
	page_args=" default_hugepagesz=1G hugepagesz=1G hugepages=$hugepages"
fi

if [ -z "$log" ]; then
	log=$REPO/logs/run-$(date +%Y%m%d-%H%M%S).log
fi
mkdir -p "$(dirname "$log")"
build_log=${log%.log}-build.log

if ! command -v qemu-system-x86_64 >/dev/null; then
	echo "run.sh: qemu-system-x86_64 not found; install the distribution's QEMU (D23)" >&2
	exit 2
fi

seconds_since() {
	awk -v a="$1" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }'
}

build_s=
if [ "$build" = 1 ]; then
	echo "building (log: $build_log)"
	build_start=$(date +%s.%N)
	if ! { make -C "$BR" wipeos-stub-rebuild && make -C "$BR"; } >"$build_log" 2>&1; then
		echo "run.sh: build failed; last lines of $build_log:" >&2
		tail -n 20 "$build_log" >&2
		exit 2
	fi
	build_s=$(seconds_since "$build_start")
fi
if [ ! -f "$KERNEL" ]; then
	echo "run.sh: no image at $KERNEL; run without --no-build" >&2
	exit 2
fi

append="console=ttyS0 panic=-1 wipeos.mode=$mode"
if [ "$test_fail" = 1 ]; then
	append+=" wipeos.test_fail=1"
fi
append+=$page_args
qemu=(qemu-system-x86_64 -accel "$accel" -m "${mem}G" -vga none -nographic
	-no-reboot "${cpu_args[@]}" -kernel "$KERNEL" -append "$append")

# Header lines in the same key=value style as the stub's report.
{
	echo "RUN qemu_version=\"$(qemu-system-x86_64 --version | head -n 1)\""
	echo "RUN git=$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)" \
		"mode=$mode accel=$accel mem_gib=$mem pages=$pages hugepages_requested=$hugepages" \
		"timeout_s=${timeout_s:-none}"
	echo "RUN command=\"${qemu[*]}\""
} >"$log"

boot_start=$(date +%s.%N)
set +e
if [ "$mode" = prod ]; then
	echo "booting (log: $log)"
	# stdin from /dev/null keeps QEMU off the terminal.
	timeout "$timeout_s" "${qemu[@]}" </dev/null >>"$log" 2>&1
	rc=$?
else
	# QEMU keeps the terminal as its input (type into the shell, Ctrl-A
	# X to quit QEMU); tee copies everything it prints into the log.
	# --foreground lets an optional timeout leave the terminal alone.
	tmo=()
	if [ -n "$timeout_s" ]; then
		tmo=(timeout --foreground "$timeout_s")
	fi
	"${tmo[@]}" "${qemu[@]}" 2>&1 | tee -a "$log"
	rc=${PIPESTATUS[0]}
fi
set -e
boot_s=$(seconds_since "$boot_start")

# The stub prints exactly one RESULT line. In dev mode anything typed
# into the shell also lands in the log, so the first one counts. Serial
# output can contain control bytes, hence grep -a.
result=$(grep -a -m 1 '^WIPEOS RESULT=' "$log" | tr -d '\r' || true)
status=${result#WIPEOS RESULT=}
reserved=$(grep -a -m 1 '^WIPEOS hugetlb.pages_total=' "$log" | tr -d '\r' | cut -d= -f2 || true)

# A clean end: QEMU stopped on its own, not by timeout, after the kernel
# powered the VM off.
clean=0
if [ "$rc" -ne 124 ] && grep -aq 'reboot: Power down' "$log"; then
	clean=1
fi

if [ -z "$result" ]; then
	why="no RESULT line"
	if [ "$rc" -eq 124 ]; then
		why="timeout after $timeout_s s"
	elif grep -aq 'Kernel panic' "$log"; then
		why="kernel panic"
	fi
	summary="NONE ($why)"
	code=2
elif [ "$clean" -ne 1 ]; then
	if [ "$rc" -eq 124 ]; then
		summary="$status, then timeout after $timeout_s s"
	else
		summary="$status, but the VM didn't power off cleanly"
	fi
	code=2
elif [ "$status" = SUCCESS ]; then
	summary=SUCCESS
	code=0
elif [[ $status == FAIL* ]]; then
	summary=$status
	code=1
else
	summary="unrecognized: $result"
	code=2
fi

echo "result:     $summary"
echo "huge pages: $hugepages requested, ${reserved:-unknown} reserved"
if [ "$hugepages" -gt 0 ] && ! [ "${reserved:-0}" -ge "$hugepages" ] 2>/dev/null; then
	echo "warning:    fewer huge pages reserved than requested"
fi
echo "log:        $log"
echo "elapsed:    boot $boot_s s${build_s:+, build $build_s s}"
exit "$code"
