#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/landlock.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef SYS_landlock_create_ruleset
#define SYS_landlock_create_ruleset __NR_landlock_create_ruleset
#endif

#ifndef SYS_landlock_add_rule
#define SYS_landlock_add_rule __NR_landlock_add_rule
#endif

#ifndef SYS_landlock_restrict_self
#define SYS_landlock_restrict_self __NR_landlock_restrict_self
#endif

static int landlock_create_ruleset_wrap(const struct landlock_ruleset_attr *attr,
                                        size_t size, __u32 flags) {
    return (int)syscall(SYS_landlock_create_ruleset, attr, size, flags);
}

static int landlock_add_rule_wrap(int ruleset_fd, enum landlock_rule_type type,
                                  const void *attr, __u32 flags) {
    return (int)syscall(SYS_landlock_add_rule, ruleset_fd, type, attr, flags);
}

static int landlock_restrict_self_wrap(int ruleset_fd, __u32 flags) {
    return (int)syscall(SYS_landlock_restrict_self, ruleset_fd, flags);
}

static void die(const char *msg) {
    fprintf(stderr, "%s: %s\n", msg, strerror(errno));
    exit(2);
}

static void add_exec_rule(int ruleset_fd, const char *path) {
    int fd = open(path, O_PATH | O_CLOEXEC);
    if (fd < 0) {
        die("open rule path");
    }

    struct landlock_path_beneath_attr rule = {
        .allowed_access = LANDLOCK_ACCESS_FS_EXECUTE,
        .parent_fd = fd,
    };
    if (landlock_add_rule_wrap(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &rule, 0) < 0) {
        die("landlock_add_rule file execute");
    }
    close(fd);
}

static int run_child(const char *allowed, const char *target) {
    pid_t pid = fork();
    if (pid < 0) {
        die("fork");
    }
    if (pid == 0) {
        struct landlock_ruleset_attr ruleset = {
            .handled_access_fs = LANDLOCK_ACCESS_FS_EXECUTE,
        };
        int ruleset_fd = landlock_create_ruleset_wrap(&ruleset, sizeof(ruleset), 0);
        if (ruleset_fd < 0) {
            die("landlock_create_ruleset");
        }
        add_exec_rule(ruleset_fd, allowed);
        if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
            die("prctl no_new_privs");
        }
        if (landlock_restrict_self_wrap(ruleset_fd, 0) < 0) {
            die("landlock_restrict_self");
        }
        close(ruleset_fd);
        execl(target, target, (char *)NULL);
        fprintf(stderr, "exec target failed path=%s errno=%d %s\n", target, errno, strerror(errno));
        _exit(errno == EACCES ? 126 : 127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        die("waitpid");
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 125;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s allowed_static blocked_static\n", argv[0]);
        return 2;
    }

    int abi = landlock_create_ruleset_wrap(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 0) {
        die("landlock ABI probe");
    }
    printf("landlock_abi=%d\n", abi);
    printf("execute_flag=0x%llx\n", (unsigned long long)LANDLOCK_ACCESS_FS_EXECUTE);

    int allowed_rc = run_child(argv[1], argv[1]);
    int blocked_rc = run_child(argv[1], argv[2]);

    printf("allowed_exec_exit=%d\n", allowed_rc);
    printf("blocked_exec_exit=%d\n", blocked_rc);

    if (allowed_rc == 0 && blocked_rc == 126) {
        printf("RESULT file_level_execute_rule=PASS\n");
        return 0;
    }
    printf("RESULT file_level_execute_rule=FAIL\n");
    return 1;
}
