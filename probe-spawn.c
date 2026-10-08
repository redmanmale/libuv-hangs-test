#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

static long ms_now(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long)ts.tv_sec * 1000L + (long)ts.tv_nsec / 1000000L;
}

int main(int argc, char **argv) {
  const char *file;
  int n, chdir_flag, pipe_flag, i;
  char *args[8];

  if (argc < 5) {
    fprintf(stderr, "usage: %s file n chdir pipes [args...]\n", argv[0]);
    return 2;
  }
  file = argv[1];
  n = atoi(argv[2]);
  chdir_flag = atoi(argv[3]);
  pipe_flag = atoi(argv[4]);

  args[0] = (char *)file;
  if (argc > 5) {
    int k = 1;
    for (i = 5; i < argc && k < 7; i++)
      args[k++] = argv[i];
    args[k] = NULL;
  } else {
    args[1] = NULL;
  }

  if (chdir_flag && mkdir("spawn-cwd", 0755) != 0 && errno != EEXIST) {
    perror("mkdir");
    return 1;
  }

  printf("probe file=%s n=%d chdir=%d pipes=%d\n", file, n, chdir_flag, pipe_flag);
  fflush(stdout);

  for (i = 0; i < n; i++) {
    posix_spawn_file_actions_t fa;
    posix_spawnattr_t sa;
    sigset_t set;
    pid_t pid = 0;
    int err, status, pfd[2];
    long t0, dt;

    posix_spawn_file_actions_init(&fa);
    posix_spawnattr_init(&sa);
    posix_spawnattr_setflags(&sa, POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK);
    sigfillset(&set);
    posix_spawnattr_setsigdefault(&sa, &set);
    sigemptyset(&set);
    posix_spawnattr_setsigmask(&sa, &set);

    if (chdir_flag)
      posix_spawn_file_actions_addchdir(&fa, "spawn-cwd");

    pfd[0] = pfd[1] = -1;
    if (pipe_flag) {
      if (pipe(pfd) != 0) {
        perror("pipe");
        return 1;
      }
      posix_spawn_file_actions_adddup2(&fa, pfd[1], STDOUT_FILENO);
      posix_spawn_file_actions_adddup2(&fa, pfd[1], STDERR_FILENO);
    }

    t0 = ms_now();
    printf("spawn %d calling\n", i);
    fflush(stdout);
    err = posix_spawn(&pid, file, &fa, &sa, args, environ);
    dt = ms_now() - t0;
    printf("spawn %d err=%d pid=%ld ms=%ld\n", i, err, (long)pid, dt);
    fflush(stdout);

    if (pipe_flag) {
      char buf[256];
      close(pfd[1]);
      while (read(pfd[0], buf, sizeof buf) > 0) {
      }
      close(pfd[0]);
    }
    if (err == 0) {
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
      }
    }
    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&sa);
  }
  printf("done\n");
  return 0;
}
