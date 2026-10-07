# libuv 1.53.0 hangs CMake on Cygwin

`stdbuf -oL cmake --debug-trycompile` stops at `-- Detecting C compiler ABI info`
with libuv 1.53.0-1. The same command finishes with libuv 1.52.1-1.
cmake is 4.4.4-1 and cygwin is 3.6.11-1 in both jobs.

libuv 1.53.0 uses `posix_spawn` on Cygwin
([libuv#3520](https://github.com/libuv/libuv/pull/3520)).
One `cmake` stays running and never starts gcc.

## Workflow

| job | libuv | result |
|---|---|---|
| ok | 1.52.1-1 | ABI check returns |
| hang | 1.53.0-1 | still running after 60s, then the log prints `ps` |

The hang job should show `RESULT: hang reproduced` and a single `cmake` process.
