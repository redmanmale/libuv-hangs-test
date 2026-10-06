# libuv 1.53.0 hangs CMake's compiler check on Cygwin

On the µTox Cygwin job, `cmake` stops inside `try_compile` at
`-- Detecting C compiler ABI info` and never starts gcc. One `cmake` process
stays up, with no child. That job had cmake 4.4.4-1, libuv1 1.53.0-1, and
cygwin 3.6.11-1.

A two-line `project(abi C CXX)` with those same packages does not hang. The
ABI check returns `failed` in under a second. libuv 1.53.0-1 is required for
the full µTox hang (cmake 4.4.4 and cygwin 3.6.11 alone still configure), but
it is not sufficient for this small project.

Cygwin's `posix_spawn` is used by libuv 1.53.0 on every Unix that is not
Linux, AIX, or PASE ([libuv#3520](https://github.com/libuv/libuv/pull/3520)).

## Workflow

[`.github/workflows/repro.yml`](.github/workflows/repro.yml) keeps the hung
package trio and changes one piece of the µTox configure:

| job | what it adds | expected |
|---|---|---|
| toolchain | `toolchain-win64.cmake` and the µTox env (`CFLAGS`, `LDFLAGS`, `MAKEFLAGS`) | still running after 60s |
| toxcore flags | the c-toxcore `cmake` arguments and the same env, on this two-line project | still running after 60s |
| toxcore tree | that same command in a checkout of c-toxcore v0.2.23 | still running after 60s |

A red job whose log says `RESULT: hang reproduced` is the missing piece.
`RESULT: cmake finished` means that piece is not enough.
