#!/bin/sh
# EXPECT=hang: cmake must still be running after 60s (libuv 1.53.0).
# EXPECT=ok: cmake must finish (libuv 1.52.1).
set -eu

echo "=== packages ==="
uname -a || true
cygcheck -c libuv1 cmake cygwin mingw64-x86_64-gcc-core make || true
x86_64-w64-mingw32-gcc --version || true

rm -rf build
mkdir build
cd build

cmake .. \
    -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
    -DCMAKE_SYSTEM_NAME=Windows &
pid=$!
waited=0

while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    if ! kill -0 "$pid" 2>/dev/null; then
        break
    fi
    waited=$((waited + 5))
    echo "cmake still running after ${waited}s"
    if [ "$waited" -ge 60 ]; then
        echo "=== cmake still running after ${waited}s ==="
        ps -ef || true
        ps -W | grep -E -i 'gcc|g\+\+|collect2|cc1|windres|ld\.exe|cmake|make' || true
        kill -9 "$pid" 2>/dev/null || true
        if [ "${EXPECT:-ok}" = "hang" ]; then
            echo "RESULT: hang reproduced"
        else
            echo "RESULT: unexpected hang"
        fi
        exit 1
    fi
done

set +e
wait "$pid"
rc=$?
set -e

if [ "${EXPECT:-ok}" = "hang" ]; then
    echo "RESULT: cmake finished (exit $rc), hang was not reproduced"
    exit 1
fi

echo "RESULT: cmake finished (exit $rc)"
exit "$rc"
