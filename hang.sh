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
  cat > dump.gdb << 'EOF'
set pagination off
set debug-file-directory /usr/lib/debug
thread 1
frame function pselect
info args
python
import gdb
inf = gdb.selected_inferior()
chosen = None
for t in inf.threads():
    t.switch()
    nm = gdb.newest_frame().name() or ""
    print("thr %s %s" % (t.num, nm))
    if "DbgBreak" in nm or "Breakin" in nm:
        chosen = t.num
if chosen is None:
    print("no breakin thread")
else:
    gdb.execute("thread %d" % chosen)
    gdb.execute("set $box = (int *)($rsp - 256)")
    gdb.execute("set {int}$box = -1")
    gdb.execute('printf "wait %d\\n", (int)waitpid(-1, $box, 1)')
    gdb.execute("x/wx $box")
    gdb.execute('printf "errno %d\\n", *__errno()')
end
EOF
  gdb -batch -n -p "$p" -x dump.gdb >gdb.txt 2>&1 &
  gpid=$!
  w=0
  while kill -0 "$gpid" 2>/dev/null && [ "$w" -lt 20 ]; do
    sleep 1
    w=$((w + 1))
  done
  kill -9 "$gpid" 2>/dev/null || true
  wait "$gpid" 2>/dev/null || true
  cat gdb.txt || true
  echo "=== SIGCHLD poke ==="
  kill -CHLD "$p" 2>/dev/null || kill -20 "$p" 2>/dev/null || true
  sleep 3
  if kill -0 "$p" 2>/dev/null; then
    echo "STILL HUNG after SIGCHLD"
  else
    echo "WOKE after SIGCHLD"
  fi
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
