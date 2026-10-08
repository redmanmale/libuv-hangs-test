#!/bin/sh
# Repeat the CMake ABI check on stock libuv 1.53. If one hangs, dump the
# process tree and gdb stacks before killing it. If none hang, posix_spawn
# MinGW gcc directly the way libuv does.
set -u

LIMIT="${LIMIT:-20}"
CMAKE_TRIES="${CMAKE_TRIES:-4}"
hangs=0
oks=0

dump_one() {
  p="$1"
  echo "-- pid $p --"
  echo -n "exename: "
  cat "/proc/$p/exename" 2>/dev/null || echo "?"
  echo -n "winpid: "
  cat "/proc/$p/winpid" 2>/dev/null || echo "?"
  echo -n "ppid: "
  cat "/proc/$p/ppid" 2>/dev/null || echo "?"
  echo -n "cmdline: "
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true
  echo
}

dump_tree() {
  root="$1"
  echo "=== tree from $root ==="
  dump_one "$root"
  for p in /proc/[0-9]*; do
    pid="${p#/proc/}"
    ppid="$(cat "$p/ppid" 2>/dev/null || true)"
    if [ "$ppid" = "$root" ]; then
      echo "child of $root:"
      dump_one "$pid"
      if command -v gdb >/dev/null 2>&1; then
        echo "=== gdb child $pid ==="
        gdb -batch -n -p "$pid" \
          -ex "set pagination off" \
          -ex "thread apply all bt" || true
      fi
    fi
  done
  if command -v gdb >/dev/null 2>&1; then
    echo "=== gdb $root ==="
    gdb -batch -n -p "$root" \
      -ex "set pagination off" \
      -ex "thread apply all bt" || true
  fi
  echo "=== ps -W (gcc/cmake) ==="
  ps -W | grep -E -i 'gcc|g\+\+|cc1|cmake|collect2|windres|probe-spawn' || true
}

run_bounded() {
  label="$1"
  shift
  echo "=== $label ==="
  "$@" >"$label.out" 2>&1 &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$LIMIT" ]; then
      echo "HANG $label after ${waited}s pid=$pid"
      echo "--- partial output ---"
      tail -n 40 "$label.out" || true
      dump_tree "$pid"
      kill -9 "$pid" 2>/dev/null || true
      return 1
    fi
  done
  wait "$pid"
  rc=$?
  echo "OK $label rc=$rc in ${waited}s"
  tail -n 20 "$label.out" || true
  return 0
}

echo "=== packages ==="
uname -a || true
cygcheck -c libuv1 cmake cygwin mingw64-x86_64-gcc-core gcc-core gdb || true

i=1
while [ "$i" -le "$CMAKE_TRIES" ]; do
  rm -rf "_build-$i"
  if run_bounded "cmake-$i" stdbuf -oL -eL cmake --debug-trycompile \
      -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
      -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
      -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
      -DCMAKE_SYSTEM_NAME=Windows \
      -B"_build-$i" -H.; then
    oks=$((oks + 1))
    grep -E 'ABI info|compiler identification|works|failed' "cmake-$i.out" || true
  else
    hangs=$((hangs + 1))
    echo "SUMMARY cmake hangs=$hangs oks=$oks (stopped on first hang)"
    exit 0
  fi
  i=$((i + 1))
done

echo "SUMMARY cmake hangs=$hangs oks=$oks"
echo "cmake did not hang; probing posix_spawn directly"

gcc -o probe-spawn probe-spawn.c
gcc_bin="$(command -v x86_64-w64-mingw32-gcc)"

LIMIT=15
run_bounded "true-plain" ./probe-spawn /usr/bin/true 20 0 0 || exit 0
run_bounded "true-chdir-pipe" ./probe-spawn /usr/bin/true 20 1 1 || exit 0
LIMIT=25
run_bounded "mingw-plain" ./probe-spawn "$gcc_bin" 10 0 0 --version || exit 0
run_bounded "mingw-chdir-pipe" ./probe-spawn "$gcc_bin" 10 1 1 --version || exit 0
run_bounded "mingw-chdir-pipe-stdbuf" stdbuf -oL -eL ./probe-spawn "$gcc_bin" 10 1 1 --version || exit 0

echo "SUMMARY no hang in cmake or direct posix_spawn"
exit 0
