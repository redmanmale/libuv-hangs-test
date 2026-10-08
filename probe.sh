#!/bin/sh
# Repeat the CMake configure until one hangs or TRIES are exhausted.
# On a hang, dump a symbolized gdb stack and the WaitForMultipleObjects
# handles via cdb.
set -u

LIMIT=25
TRIES="${TRIES:-6}"

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
  echo "cygwin debug files:"
  find /usr/lib/debug -name 'cygwin1*' 2>/dev/null | head || true
  gdb -batch -n -p "$p" \
    -ex "set pagination off" \
    -ex "set debug-file-directory /usr/lib/debug" \
    -ex "info sharedlibrary cygwin1" \
    -ex "thread apply all bt" >"gdb-$p.txt" 2>&1 &
  gpid=$!
  w=0
  while kill -0 "$gpid" 2>/dev/null && [ "$w" -lt 30 ]; do
    sleep 1
    w=$((w + 1))
  done
  kill -9 "$gpid" 2>/dev/null || true
  wait "$gpid" 2>/dev/null || true
  cat "gdb-$p.txt" || true
}

cdb_handles() {
  root="$1"
  winpid="$(tr -d '[:space:]' < "/proc/$root/winpid" 2>/dev/null || true)"
  echo "=== cdb winpid $winpid ==="
  cdb=""
  for cand in \
    "/cygdrive/c/Program Files (x86)/Windows Kits/10/Debuggers/x64/cdb.exe" \
    "/cygdrive/c/Program Files/Windows Kits/10/Debuggers/x64/cdb.exe"
  do
    if [ -f "$cand" ]; then
      cdb="$cand"
      break
    fi
  done
  if [ -z "$cdb" ]; then
    cdb="$(find '/cygdrive/c/Program Files (x86)/Windows Kits' '/cygdrive/c/Program Files/Windows Kits' \
      -name cdb.exe 2>/dev/null | head -n 1 || true)"
  fi
  if [ -z "$cdb" ] || [ -z "$winpid" ]; then
    echo "cdb not found or winpid empty (cdb='$cdb' winpid='$winpid')"
    return 0
  fi
  echo "using $cdb"
  cat > dump-wfmo.cdb <<'EOF'
.echo ==== threads ====
~
.echo ==== stacks ====
~*k 30
.echo ==== wfmo handles ====
~*e .echo --- thread ---; r rcx; r rdx; r r8; .printf "count=%d rdx=%p\n", @rcx, @rdx; .if (@rcx >= 1 and @rcx <= 8) { .for (r $t0 = 0; @$t0 < @rcx; r $t0 = @$t0 + 1) { .printf "handle[%d]=%p\n", @$t0, poi(@rdx + @$t0 * 8); !handle poi(@rdx + @$t0 * 8) f } }
q
EOF
  "$cdb" -p "$winpid" -logo cdb-out.txt -cf dump-wfmo.cdb >cdb-run.txt 2>&1 &
  cpid=$!
  w=0
  while kill -0 "$cpid" 2>/dev/null && [ "$w" -lt 40 ]; do
    sleep 1
    w=$((w + 1))
  done
  kill -9 "$cpid" 2>/dev/null || true
  wait "$cpid" 2>/dev/null || true
  echo "--- cdb stdout ---"
  cat cdb-run.txt 2>/dev/null || true
  echo "--- cdb logo ---"
  cat cdb-out.txt 2>/dev/null || true
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
  cdb_handles "$root"
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
  tail -n 40 cmake.out || true
}

i=1
while [ "$i" -le "$TRIES" ]; do
  rm -rf _build cmake.out
  echo "=== attempt $i ==="
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
      echo "HANG attempt $i after ${waited}s pid=$pid"
      dump_hang "$pid"
      kill -9 "$pid" 2>/dev/null || true
      exit 0
    fi
  done
  wait "$pid"
  rc=$?
  echo "FINISHED attempt $i rc=$rc in ${waited}s"
  tail -n 8 cmake.out || true
  i=$((i + 1))
done

echo "SUMMARY no hang in $TRIES attempts"
exit 0
