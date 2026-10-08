/* Spawn a short-lived child through libuv and report what waitpid sees
 * if the exit callback does not run. Distinguishes a lost SIGCHLD from a
 * child that is still alive. */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <uv.h>

static int finished;
static int64_t exit_status;
static uv_process_t child;
static uv_timer_t timer;
static uv_pipe_t outpipe;

static void close_cb(uv_handle_t* handle) {
  (void) handle;
}

static void exit_cb(uv_process_t* process, int64_t status, int term_signal) {
  (void) term_signal;
  finished = 1;
  exit_status = status;
  uv_close((uv_handle_t*) process, close_cb);
  if (!uv_is_closing((uv_handle_t*) &timer)) {
    uv_timer_stop(&timer);
    uv_close((uv_handle_t*) &timer, close_cb);
  }
  if (outpipe.loop != NULL && !uv_is_closing((uv_handle_t*) &outpipe))
    uv_close((uv_handle_t*) &outpipe, close_cb);
}

static void timer_cb(uv_timer_t* handle) {
  int status = 0;
  pid_t pid = child.pid;
  pid_t got;

  finished = 2;
  got = waitpid(pid, &status, WNOHANG);
  printf("TIMEOUT pid=%d waitpid=%d errno=%d status=0x%x kill0=%d\n",
         (int) pid,
         (int) got,
         got < 0 ? errno : 0,
         got > 0 ? status : 0,
         kill(pid, 0) == 0 ? 1 : errno);
  fflush(stdout);
  uv_timer_stop(handle);
  uv_close((uv_handle_t*) handle, close_cb);
  if (!uv_is_closing((uv_handle_t*) &child))
    uv_close((uv_handle_t*) &child, close_cb);
  if (outpipe.loop != NULL && !uv_is_closing((uv_handle_t*) &outpipe))
    uv_close((uv_handle_t*) &outpipe, close_cb);
}

static int one(uv_loop_t* loop, int use_pipe, char* file, char** args) {
  uv_process_options_t opts;
  uv_stdio_container_t stdio[3];
  int err;

  memset(&child, 0, sizeof child);
  memset(&outpipe, 0, sizeof outpipe);
  memset(&opts, 0, sizeof opts);
  memset(stdio, 0, sizeof stdio);
  finished = 0;
  exit_status = -1;

  stdio[0].flags = UV_IGNORE;
  stdio[2].flags = UV_IGNORE;
  if (use_pipe) {
    uv_pipe_init(loop, &outpipe, 0);
    stdio[1].flags = UV_CREATE_PIPE | UV_WRITABLE_PIPE;
    stdio[1].data.stream = (uv_stream_t*) &outpipe;
  } else {
    stdio[1].flags = UV_IGNORE;
  }

  opts.file = file;
  opts.args = args;
  opts.stdio = stdio;
  opts.stdio_count = 3;
  opts.exit_cb = exit_cb;

  uv_timer_init(loop, &timer);
  uv_timer_start(&timer, timer_cb, 2000, 0);

  err = uv_spawn(loop, &child, &opts);
  if (err != 0) {
    printf("SPAWN_FAIL %s (%s)\n", uv_strerror(err), file);
    uv_timer_stop(&timer);
    uv_close((uv_handle_t*) &timer, close_cb);
    if (outpipe.loop != NULL)
      uv_close((uv_handle_t*) &outpipe, close_cb);
    uv_run(loop, UV_RUN_DEFAULT);
    return 2;
  }

  uv_run(loop, UV_RUN_DEFAULT);
  if (finished == 1) {
    printf("OK pid was reaped status=%lld\n", (long long) exit_status);
    return 0;
  }
  return 1;
}

int main(int argc, char** argv) {
  uv_loop_t* loop;
  int rounds;
  int use_pipe;
  int i;
  int hung = 0;
  int ok = 0;
  int fail = 0;
  char* file;
  char** args;

  if (argc < 4) {
    fprintf(stderr, "usage: race <rounds> <ignore|pipe> <file> [args...]\n");
    return 2;
  }

  rounds = atoi(argv[1]);
  use_pipe = strcmp(argv[2], "pipe") == 0;
  file = argv[3];
  args = argv + 3;

  loop = uv_default_loop();
  printf("file=%s mode=%s rounds=%d\n", file, use_pipe ? "pipe" : "ignore", rounds);
  fflush(stdout);

  for (i = 0; i < rounds; i++) {
    int rc = one(loop, use_pipe, file, args);
    if (rc == 0)
      ok++;
    else if (rc == 1)
      hung++;
    else
      fail++;
  }

  printf("SUMMARY ok=%d hung=%d spawn_fail=%d\n", ok, hung, fail);
  return hung ? 1 : fail ? 2 : 0;
}
