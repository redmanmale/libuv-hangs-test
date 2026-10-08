#!/bin/sh
# One CMake configure on libuv 1.53. Print the ABI try_compile command and
# the configure log so we can see what runs after compiler identification.
set -u

echo "=== packages ==="
cygcheck -c libuv1 cmake cygwin mingw64-x86_64-gcc-core || true

rm -rf _build
stdbuf -oL -eL cmake --debug-trycompile \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
  -DCMAKE_SYSTEM_NAME=Windows \
  -B_build -H.
echo "cmake_rc=$?"

echo "=== interesting files ==="
find _build -type f \
  \( -name 'CMakeConfigureLog.yaml' -o -name 'CMakeError.log' \
     -o -name 'CMakeOutput.log' -o -name 'build.make' \
     -o -name 'link.txt' -o -name 'flags.make' \
     -o -name 'CMakeLists.txt' \) \
  -print || true

log="_build/CMakeFiles/CMakeConfigureLog.yaml"
if [ -f "$log" ]; then
  echo "=== $log ==="
  cat "$log"
fi

echo "=== scratch CMakeLists and build rules ==="
find _build -path '*CMakeScratch*' -type f -print | while read -r f; do
  case "$f" in
    *.o|*.obj|*.exe|*.bin) continue ;;
  esac
  echo "----- $f -----"
  if [ "$(wc -c < "$f")" -gt 20000 ]; then
    echo "(truncated)"
    head -c 4000 "$f"
    echo
  else
    cat "$f"
  fi
done
