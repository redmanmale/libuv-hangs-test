# libuv 1.53.0 hangs CMake's compiler check on Cygwin

`cmake` stops at `-- Detecting C compiler ABI info` and never starts gcc.
That happened with cmake 4.4.4-1, libuv 1.53.0-1, and cygwin 3.6.11-1.
libuv 1.53.0-1 with cmake 4.4.3-1 and cygwin 3.6.10-1 does not hang: the ABI
check returns `failed` in a few seconds.

Cygwin's `posix_spawn` is used by libuv 1.53.0 on every Unix that is not
Linux, AIX, or PASE ([libuv#3520](https://github.com/libuv/libuv/pull/3520)).

## Workflow

[`.github/workflows/repro.yml`](.github/workflows/repro.yml) runs both versions.

| job | libuv | cmake | cygwin | result |
|---|---|---|---|---|
| hang | 1.53.0-1 | 4.4.4-1 | 3.6.11-1 | fails after 60s and prints `ps` |
| ok | 1.52.1-1 | 4.4.4-1 | 3.6.11-1 | reaches the end of the ABI check |

The red job is the demonstration. Its log should show one `cmake` process and
no `gcc`, `make`, or `ld`.

## Local run

```sh
cmake -S . -B build \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_SYSTEM_NAME=Windows
```
