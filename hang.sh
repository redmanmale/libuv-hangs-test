#!/bin/sh
# Repeat the CMake configure until one is stuck with no live child.
# Then ask that process whether it still has a zombie.
set -u

LIMIT="${LIMIT:-20}"
TRIES="${TRIES:-40}"

dump_hang() {
  p="$1"
  echo "HANG pid=$p"
  echo "=== ps -ef ==="
  ps -ef || true
  echo "=== fds ==="
  ls -l "/proc/$p/fd" || true
  echo "=== waitpid and stack ==="
  gdb -batch -n -p "$p" \
    -ex 'set pagination off' \
    -ex 'set debug-file-directory /usr/lib/debug' \
    -ex 'set $st = -999' \
    -ex 'printf "wait1 %d st %d errno %d\n", (int)waitpid(-1, &$st, 1), $st, errno' \
    -ex 'set $st = -999' \
    -ex 'printf "wait2 %d st %d errno %d\n", (int)waitpid(-1, &$st, 1), $st, errno' \
    -ex 'set $st = -999' \
    -ex 'printf "wait3 %d st %d errno %d\n", (int)waitpid(-1, &$st, 1), $st, errno' \
    -ex 'thread 1' \
    -ex 'bt 8' || true
  echo "=== cmake tail ==="
  tail -n 20 cmake.out || true
}

has_child() {
  root="$1"
  for ent in /proc/[0-9]*; do
    ppid="$(cat "$ent/ppid" 2>/dev/null || true)"
    if [ "$ppid" = "$root" ]; then
      return 0
    fi
  done
  return 1
}

i=1
while [ "$i" -le "$TRIES" ]; do
  rm -rf _build cmake.out
  echo "=== attempt $i ==="
  cmake --debug-trycompile \
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
    if [ "$waited" -ge "$LIMIT" ] && ! has_child "$pid"; then
      dump_hang "$pid"
      kill -9 "$pid" 2>/dev/null || true
      exit 0
    fi
    if [ "$waited" -ge 90 ]; then
      echo "SLOW attempt $i still alive after ${waited}s"
      dump_hang "$pid"
      kill -9 "$pid" 2>/dev/null || true
      exit 0
    fi
  done
  wait "$pid" || true
  echo "FINISHED attempt $i in ${waited}s"
  i=$((i + 1))
done

echo "SUMMARY no hang in $TRIES attempts"
exit 0
