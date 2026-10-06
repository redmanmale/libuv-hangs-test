#!/bin/sh
# EXPECT=hang: cmake must still be running after 60s.
# EXPECT=ok: cmake must finish.
# MODE=plain | toolchain | toxcore-flags | toxcore-tree | stdbuf | sodium
set -eu

echo "=== mode ${MODE:-plain} ==="
uname -a || true
cygcheck -c libuv1 cmake cygwin mingw64-x86_64-gcc-core make git || true
x86_64-w64-mingw32-gcc --version || true

ROOT=$(pwd)
MODE=${MODE:-plain}

apply_utox_env() {
    CACHE_DIR="${CACHE_DIR:-$HOME/cache}"
    export CACHE_DIR
    mkdir -p "$CACHE_DIR/usr/include/opus" "$CACHE_DIR/usr/lib/pkgconfig"
    export CFLAGS="-I$CACHE_DIR/usr/include -I$CACHE_DIR/usr/include/opus"
    export LDFLAGS="-L$CACHE_DIR/usr/lib"
    export LD_LIBRARY_PATH="$CACHE_DIR/usr/lib:/usr/lib"
    export PKG_CONFIG_PATH="$CACHE_DIR/usr/lib/pkgconfig"
    export MAKEFLAGS="-j8"
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0=core.autocrlf
    export GIT_CONFIG_VALUE_0=false
    export GIT_CONFIG_KEY_1=core.eol
    export GIT_CONFIG_VALUE_1=lf
    export TARGET_HOST="--host=x86_64-w64-mingw32"
    export TARGET_TRGT="--target=x86_64-win64-gcc"
    export CROSS="x86_64-w64-mingw32-"
    echo "=== env ==="
    echo "CFLAGS=$CFLAGS"
    echo "LDFLAGS=$LDFLAGS"
    echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
    echo "MAKEFLAGS=$MAKEFLAGS"
    echo "CACHE_DIR=$CACHE_DIR"
}

run_cmake() {
    case "$MODE" in
    plain)
        cmake .. \
            -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
            -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
            -DCMAKE_SYSTEM_NAME=Windows
        ;;
    toolchain)
        apply_utox_env
        export CFLAGS="-I$CACHE_DIR/usr/include -I/usr/share/mingw-w64/include/ "
        echo "CFLAGS=$CFLAGS"
        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$ROOT/toolchain-win64.cmake" \
            -DCMAKE_PREFIX_PATH="$CACHE_DIR/usr" \
            -DCMAKE_INCLUDE_PATH="$CACHE_DIR/usr/include" \
            -DCMAKE_LIBRARY_PATH="$CACHE_DIR/usr/lib" \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
            -DSTATIC_ALL=ON \
            -DCMAKE_BUILD_TYPE=Release
        ;;
    stdbuf)
        apply_utox_env
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
            -B_build -H.
        ;;
    sodium|toxcore-flags|toxcore-tree)
        apply_utox_env
        cmake \
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
            -DBUILD_TOXAV=ON \
            -DMUST_BUILD_TOXAV=ON \
            -DBOOTSTRAP_DAEMON=OFF \
            -DDHT_BOOTSTRAP=OFF \
            -DBUILD_MISC_TESTS=OFF \
            -DAUTOTEST=OFF \
            -DUNITTEST=OFF \
            -B_build -H.
        ;;
    *)
        echo "unknown MODE=$MODE" >&2
        return 2
        ;;
    esac
}

case "$MODE" in
plain|toolchain)
    rm -rf build
    mkdir build
    cd build
    ;;
toxcore-tree)
    rm -rf toxcore
    git clone --depth=1 --recurse-submodules --branch=v0.2.23 \
        https://github.com/TokTok/c-toxcore.git toxcore
    cd toxcore
    ;;
toxcore-flags|stdbuf)
    ;;
sodium)
    apply_utox_env
    rm -rf libsodium
    git clone --depth=1 --branch=1.0.22-RELEASE https://github.com/jedisct1/libsodium.git
    (
        cd libsodium
        ./autogen.sh
        set +e
        ./configure --host=x86_64-w64-mingw32 \
            --prefix="$CACHE_DIR/usr" \
            --disable-shared \
            --enable-static
        echo "sodium configure exit $?"
    )
    make -C libsodium -j8
    make -C libsodium install
    ;;
*)
    echo "unknown MODE=$MODE" >&2
    exit 2
    ;;
esac

echo "=== cmake cwd $(pwd) ==="
run_cmake &
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
        ps -W || true
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
