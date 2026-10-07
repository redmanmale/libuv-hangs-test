#!/bin/sh
# EXPECT=hang: cmake must still be running after 60s (libuv 1.53.0).
# EXPECT=ok: cmake must finish (libuv 1.52.1).
set -eu

echo "=== packages ==="
uname -a || true
cygcheck -c libuv1 cmake cygwin mingw64-x86_64-gcc-core make || true
x86_64-w64-mingw32-gcc --version || true

CACHE_DIR="${CACHE_DIR:-$HOME/cache}"
export CACHE_DIR
mkdir -p "$CACHE_DIR/usr/include/opus" "$CACHE_DIR/usr/lib/pkgconfig"
export CFLAGS="-I$CACHE_DIR/usr/include -I$CACHE_DIR/usr/include/opus"
export LDFLAGS="-L$CACHE_DIR/usr/lib"
export LD_LIBRARY_PATH="$CACHE_DIR/usr/lib:/usr/lib"
export PKG_CONFIG_PATH="$CACHE_DIR/usr/lib/pkgconfig"
export MAKEFLAGS="-j8"

rm -rf _build
stdbuf -oL -eL cmake --debug-trycompile \
    -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
    -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_FIND_ROOT_PATH="$CACHE_DIR/usr" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_INSTALL_PREFIX:PATH="$CACHE_DIR/usr" \
    -DCMAKE_PREFIX_PATH="$CACHE_DIR/usr" \
    -DENABLE_SHARED=OFF \
    -DENABLE_STATIC=ON \
    -B_build -H. &
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
        echo "=== try_compile dirs ==="
        find . \( -path '*TryCompile*' -o -path '*CMakeTmp*' \) -print || true
        if [ "${EXPECT:-ok}" = "hang" ]; then
            echo "RESULT: hang reproduced"
        else
            echo "RESULT: unexpected hang"
        fi
        kill -9 "$pid" 2>/dev/null || true
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
