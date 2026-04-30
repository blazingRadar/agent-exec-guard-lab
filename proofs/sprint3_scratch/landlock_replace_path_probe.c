#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/landlock.h>
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

static int ll_create(const struct landlock_ruleset_attr *attr, size_t size, __u32 flags) {
    return (int)syscall(SYS_landlock_create_ruleset, attr, size, flags);
}

static int ll_add(int ruleset_fd, enum landlock_rule_type type, const void *attr, __u32 flags) {
    return (int)syscall(SYS_landlock_add_rule, ruleset_fd, type, attr, flags);
}

static int ll_restrict(int ruleset_fd, __u32 flags) {
    return (int)syscall(SYS_landlock_restrict_self, ruleset_fd, flags);
}

static void die(const char *msg) {
    fprintf(stderr, "%s: %s\n", msg, strerror(errno));
    exit(2);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s allowed_path replacement_path\n", argv[0]);
        return 2;
    }

    int abi = ll_create(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 0) {
        die("landlock ABI probe");
    }
    printf("landlock_abi=%d\n", abi);

    struct landlock_ruleset_attr ruleset = {
        .handled_access_fs = LANDLOCK_ACCESS_FS_EXECUTE,
    };
    int ruleset_fd = ll_create(&ruleset, sizeof(ruleset), 0);
    if (ruleset_fd < 0) {
        die("landlock_create_ruleset");
    }

    int allowed_fd = open(argv[1], O_PATH | O_CLOEXEC);
    if (allowed_fd < 0) {
        die("open allowed_path");
    }
    struct landlock_path_beneath_attr rule = {
        .allowed_access = LANDLOCK_ACCESS_FS_EXECUTE,
        .parent_fd = allowed_fd,
    };
    if (ll_add(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &rule, 0) < 0) {
        die("landlock_add_rule allowed_path");
    }
    close(allowed_fd);

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        die("prctl no_new_privs");
    }
    if (ll_restrict(ruleset_fd, 0) < 0) {
        die("landlock_restrict_self");
    }
    close(ruleset_fd);

    if (rename(argv[2], argv[1]) < 0) {
        die("rename replacement over allowed");
    }
    execl(argv[1], argv[1], (char *)NULL);
    printf("exec_after_replace_errno=%d %s\n", errno, strerror(errno));
    if (errno == EACCES) {
        printf("RESULT replacement_path_exec_denied=PASS\n");
        return 0;
    }
    printf("RESULT replacement_path_exec_denied=FAIL\n");
    return 1;
}
