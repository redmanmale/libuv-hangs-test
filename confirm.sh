#!/bin/sh
# Same hang rule as hang.sh: still alive after LIMIT seconds and no /proc child.
# Tee each cmake configure and record whether the compiler checks passed.
set -u

LIMIT="${LIMIT:-20}"
TRIES="${TRIES:-40}"

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

compiler_lines() {
  echo "=== compiler lines ==="
  grep -E "Check for working C compiler|Check for working CXX compiler|Configuring done|Generating done|CMake Error" cmake.out || true
}

dump_hang() {
  p="$1"
  echo "HANG pid=$p"
  echo "=== ps -ef ==="
  ps -ef || true
  echo "=== fds ==="
  ls -l "/proc/$p/fd" || true
  # tee reads cmake.fifo until cmake closes it. Kill first or this wait
  # never returns and the job sits until it is cancelled.
  kill -9 "$p" 2>/dev/null || true
  wait "$p" 2>/dev/null || true
  wait "$teepid" 2>/dev/null || true
  echo "=== cmake tail ==="
  tail -n 40 cmake.out || true
  compiler_lines
}

finished=0
c_ok=0
cxx_ok=0
config_ok=0

i=1
while [ "$i" -le "$TRIES" ]; do
  rm -rf _build cmake.out cmake.fifo
  echo "=== attempt $i ==="
  mkfifo cmake.fifo
  tee cmake.out < cmake.fifo &
  teepid=$!
  cmake --debug-trycompile \
    -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
    -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
    -DCMAKE_SYSTEM_NAME=Windows \
    -B_build -H. >cmake.fifo 2>&1 &
  pid=$!
  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge "$LIMIT" ] && ! has_child "$pid"; then
      dump_hang "$pid"
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      wait "$teepid" 2>/dev/null || true
      echo "SUMMARY hung=1 attempt=$i finished=$finished c_works=$c_ok cxx_works=$cxx_ok configure_done=$config_ok"
      echo "CONFIGURE: hung on attempt $i before completion"
      exit 1
    fi
    if [ "$waited" -ge 90 ]; then
      echo "SLOW attempt $i still alive after ${waited}s"
      dump_hang "$pid"
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      wait "$teepid" 2>/dev/null || true
      echo "SUMMARY hung=1 attempt=$i finished=$finished c_works=$c_ok cxx_works=$cxx_ok configure_done=$config_ok"
      echo "CONFIGURE: still alive after ${waited}s on attempt $i"
      exit 1
    fi
  done
  wait "$pid"
  rc=$?
  wait "$teepid" || true
  echo "FINISHED attempt $i in ${waited}s exit=$rc"
  finished=$((finished + 1))
  if grep -E -q "Check for working C compiler:.* - works" cmake.out; then
    c_ok=$((c_ok + 1))
    echo "C compiler: works (attempt $i)"
  else
    echo "C compiler: NOT works (attempt $i)"
  fi
  if grep -E -q "Check for working CXX compiler:.* - works" cmake.out; then
    cxx_ok=$((cxx_ok + 1))
    echo "CXX compiler: works (attempt $i)"
  else
    echo "CXX compiler: NOT works (attempt $i)"
  fi
  if grep -q "Configuring done" cmake.out; then
    config_ok=$((config_ok + 1))
    echo "CONFIGURE finished attempt $i"
  else
    echo "CONFIGURE did not finish attempt $i"
  fi
  compiler_lines
  i=$((i + 1))
done

echo "SUMMARY hung=0 finished=$finished c_works=$c_ok cxx_works=$cxx_ok configure_done=$config_ok tries=$TRIES"
if [ "$c_ok" -eq "$TRIES" ] && [ "$cxx_ok" -eq "$TRIES" ] && [ "$config_ok" -eq "$TRIES" ]; then
  echo "CONFIGURE: all $TRIES attempts finished with a working C and CXX compiler"
  exit 0
fi
echo "CONFIGURE: not every attempt finished with a working C and CXX compiler"
exit 1
