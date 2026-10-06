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

Toolchain, the c-toxcore arguments, and a c-toxcore checkout all return from
the ABI check. The hung µTox job also had the full Cygwin package list,
`stdbuf -oL cmake --debug-trycompile`, and a library install in the same
shell before `cmake`. The workflow probes those three.

| job | what it adds | expected |
|---|---|---|
| full packages | the µTox package list, then cmake in c-toxcore v0.2.23 | still running after 60s |
| stdbuf | `stdbuf -oL -eL cmake --debug-trycompile` with the toxcore arguments | still running after 60s |
| after libsodium | build and install libsodium, then the same cmake in that shell | still running after 60s |

A red job whose log says `RESULT: hang reproduced` is the missing piece.
`RESULT: cmake finished` means that piece is not enough.

µTox itself stays on libuv 1.52.1 until this hang has a smaller repro.
