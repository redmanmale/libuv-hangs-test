#!/bin/sh
# Configure once. If cmake is still running after 25s, dump every process
# and gdb stacks, then kill it. A finished configure prints the ABI log.
set -u

LIMIT=25

dump_one() {
  p="$1"
  echo "-- cygwin pid $p --"
  echo -n "exename: "; cat "/proc/$p/exename" 2>/dev/null || echo "?"
  echo -n "winpid: "; cat "/proc/$p/winpid" 2>/dev/null || echo "?"
  echo -n "ppid: "; cat "/proc/$p/ppid" 2>/dev/null || echo "?"
  echo -n "cmdline: "; tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true
  echo
  echo "fds:"
  ls -l "/proc/$p/fd" 2>/dev/null || true
}

gdb_pid() {
  p="$1"
  echo "=== gdb $p ==="
  gdb -batch -n -p "$p" \
    -ex "set pagination off" \
    -ex "thread apply all bt" >"gdb-$p.txt" 2>&1 &
  gpid=$!
  w=0
  while kill -0 "$gpid" 2>/dev/null && [ "$w" -lt 20 ]; do
    sleep 1
    w=$((w + 1))
  done
  kill -9 "$gpid" 2>/dev/null || true
  wait "$gpid" 2>/dev/null || true
  cat "gdb-$p.txt" || true
}

dump_hang() {
  root="$1"
  echo "=== ps -ef ==="
  ps -ef || true
  echo "=== ps -W ==="
  ps -W || true
  echo "=== /proc from $root ==="
  dump_one "$root"
  gdb_pid "$root"
  for ent in /proc/[0-9]*; do
    pid="${ent#/proc/}"
    ppid="$(cat "$ent/ppid" 2>/dev/null || true)"
    if [ "$ppid" = "$root" ]; then
      echo "child $pid"
      dump_one "$pid"
      gdb_pid "$pid"
    fi
  done
  echo "=== partial cmake output ==="
  tail -n 80 cmake.out || true
  echo "=== files written so far ==="
  find _build -type f -print 2>/dev/null || true
}

rm -rf _build
stdbuf -oL -eL cmake --debug-trycompile \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
  -DCMAKE_SYSTEM_NAME=Windows \
  -B_build -H. >cmake.out 2>&1 &
pid=$!
waited=0
while kill -0 "$pid" 2>/dev/null; do
  sleep 1
  waited=$((waited + 1))
  if [ "$waited" -ge "$LIMIT" ]; then
    echo "HANG after ${waited}s pid=$pid"
    dump_hang "$pid"
    kill -9 "$pid" 2>/dev/null || true
    exit 0
  fi
done
wait "$pid"
rc=$?
echo "FINISHED rc=$rc in ${waited}s"
cat cmake.out
log="_build/CMakeFiles/CMakeConfigureLog.yaml"
if [ -f "$log" ]; then
  echo "=== $log ==="
  cat "$log"
fi
