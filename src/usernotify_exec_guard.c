#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/if_alg.h>
#include <linux/landlock.h>
#include <linux/seccomp.h>
#include <linux/unistd.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef SECCOMP_USER_NOTIF_FLAG_CONTINUE
#define SECCOMP_USER_NOTIF_FLAG_CONTINUE (1UL << 0)
#endif

#ifndef SYS_seccomp
#define SYS_seccomp __NR_seccomp
#endif

#ifndef SYS_landlock_create_ruleset
#define SYS_landlock_create_ruleset __NR_landlock_create_ruleset
#endif

#ifndef SYS_landlock_add_rule
#define SYS_landlock_add_rule __NR_landlock_add_rule
#endif

#ifndef SYS_landlock_restrict_self
#define SYS_landlock_restrict_self __NR_landlock_restrict_self
#endif

#define MAX_POLICY_ENTRIES 64
#define MAX_ARGV_CAPTURE 8
#define MAX_ARGV_COUNT_SCAN 256
#define MAX_JSON_DEPTH 64

static int audit_fd = STDERR_FILENO;
static FILE *audit_out = NULL;

typedef struct {
    char configured_path[PATH_MAX];
    char real_path[PATH_MAX];
    dev_t dev;
    ino_t ino;
    char sha256[65];
} PolicyEntry;

typedef struct {
    char policy_id[128];
    size_t count;
    PolicyEntry entries[MAX_POLICY_ENTRIES];
} Policy;

typedef struct {
    bool allowed;
    char reason[128];
    char raw_exe[4096];
    char real_path[PATH_MAX];
    char cwd[PATH_MAX];
    char sha256[65];
    dev_t dev;
    ino_t ino;
    char argv_json[2048];
    bool argv_truncated;
    size_t argv_total_count;
    bool argv_total_count_capped;
} Decision;

static void die(const char *msg) {
    perror(msg);
    exit(2);
}

static FILE *audit_stream(void) {
    return audit_out ? audit_out : stderr;
}

static void fatal_signal_handler(int signo) {
    const char *msg =
        "{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"UNKNOWN\"}\n";
    size_t msg_len = sizeof("{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"UNKNOWN\"}\n") - 1;
    if (signo == SIGTERM) {
        msg = "{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"SIGTERM\"}\n";
        msg_len = sizeof("{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"SIGTERM\"}\n") - 1;
    } else if (signo == SIGINT) {
        msg = "{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"SIGINT\"}\n";
        msg_len = sizeof("{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"SIGINT\"}\n") - 1;
    } else if (signo == SIGHUP) {
        msg = "{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"SIGHUP\"}\n";
        msg_len = sizeof("{\"event\":\"supervisor_exit\",\"reason\":\"killed_by_signal\",\"signal\":\"SIGHUP\"}\n") - 1;
    }
    ssize_t ignored = write(audit_fd, msg, msg_len);
    (void)ignored;
    _exit(128 + signo);
}

static void install_signal_handlers(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = fatal_signal_handler;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
}

static void reset_signal_handlers(void) {
    signal(SIGTERM, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGHUP, SIG_DFL);
}

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

static int install_exec_listener(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 0, 5),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execve, 1, 0),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_USER_NOTIF),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
    };
    struct sock_fprog prog = {
        .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        return -1;
    }

    return (int)syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER,
                        SECCOMP_FILTER_FLAG_NEW_LISTENER, &prog);
}

static void send_fd(int sock, int fd) {
    char buf[1] = {'F'};
    struct iovec io = {.iov_base = buf, .iov_len = sizeof(buf)};
    char cmsgbuf[CMSG_SPACE(sizeof(int))];
    memset(cmsgbuf, 0, sizeof(cmsgbuf));

    struct msghdr msg = {0};
    msg.msg_iov = &io;
    msg.msg_iovlen = 1;
    msg.msg_control = cmsgbuf;
    msg.msg_controllen = sizeof(cmsgbuf);

    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
    cmsg->cmsg_level = SOL_SOCKET;
    cmsg->cmsg_type = SCM_RIGHTS;
    cmsg->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(cmsg), &fd, sizeof(int));
    msg.msg_controllen = cmsg->cmsg_len;

    if (sendmsg(sock, &msg, 0) < 0) {
        die("sendmsg");
    }
}

static int recv_fd(int sock) {
    char buf[1];
    struct iovec io = {.iov_base = buf, .iov_len = sizeof(buf)};
    char cmsgbuf[CMSG_SPACE(sizeof(int))];
    memset(cmsgbuf, 0, sizeof(cmsgbuf));

    struct msghdr msg = {0};
    msg.msg_iov = &io;
    msg.msg_iovlen = 1;
    msg.msg_control = cmsgbuf;
    msg.msg_controllen = sizeof(cmsgbuf);

    if (recvmsg(sock, &msg, 0) < 0) {
        die("recvmsg");
    }

    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
    if (!cmsg || cmsg->cmsg_level != SOL_SOCKET || cmsg->cmsg_type != SCM_RIGHTS) {
        fprintf(stderr, "failed to receive listener fd\n");
        exit(2);
    }

    int fd = -1;
    memcpy(&fd, CMSG_DATA(cmsg), sizeof(int));
    return fd;
}

static bool read_child_bytes(pid_t pid, uint64_t addr, void *buf, size_t len) {
    struct iovec local = {.iov_base = buf, .iov_len = len};
    struct iovec remote = {.iov_base = (void *)(uintptr_t)addr, .iov_len = len};
    return process_vm_readv(pid, &local, 1, &remote, 1, 0) == (ssize_t)len;
}

static bool read_child_string(pid_t pid, uint64_t addr, char *buf, size_t buf_len) {
    if (buf_len == 0) {
        return false;
    }
    memset(buf, 0, buf_len);

    for (size_t offset = 0; offset < buf_len - 1; offset++) {
        char ch = '\0';
        if (!read_child_bytes(pid, addr + offset, &ch, sizeof(ch))) {
            return offset > 0;
        }
        buf[offset] = ch;
        if (ch == '\0') {
            return true;
        }
    }
    buf[buf_len - 1] = '\0';
    return true;
}

static bool read_child_string_ex(pid_t pid, uint64_t addr, char *buf, size_t buf_len,
                                 bool *truncated) {
    if (truncated) {
        *truncated = false;
    }
    if (buf_len == 0) {
        return false;
    }
    memset(buf, 0, buf_len);

    for (size_t offset = 0; offset < buf_len - 1; offset++) {
        char ch = '\0';
        if (!read_child_bytes(pid, addr + offset, &ch, sizeof(ch))) {
            return offset > 0;
        }
        buf[offset] = ch;
        if (ch == '\0') {
            return true;
        }
    }
    buf[buf_len - 1] = '\0';
    if (truncated) {
        *truncated = true;
    }
    return true;
}

static void json_escape(FILE *out, const char *s) {
    fputc('"', out);
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        switch (*p) {
        case '"':
            fputs("\\\"", out);
            break;
        case '\\':
            fputs("\\\\", out);
            break;
        case '\b':
            fputs("\\b", out);
            break;
        case '\f':
            fputs("\\f", out);
            break;
        case '\n':
            fputs("\\n", out);
            break;
        case '\r':
            fputs("\\r", out);
            break;
        case '\t':
            fputs("\\t", out);
            break;
        default:
            if (*p < 0x20) {
                fprintf(out, "\\u%04x", *p);
            } else {
                fputc(*p, out);
            }
        }
    }
    fputc('"', out);
}

static void json_escape_bytes(FILE *out, const char *s, size_t len) {
    fputc('"', out);
    for (size_t i = 0; i < len; i++) {
        unsigned char ch = (unsigned char)s[i];
        switch (ch) {
        case '"':
            fputs("\\\"", out);
            break;
        case '\\':
            fputs("\\\\", out);
            break;
        case '\b':
            fputs("\\b", out);
            break;
        case '\f':
            fputs("\\f", out);
            break;
        case '\n':
            fputs("\\n", out);
            break;
        case '\r':
            fputs("\\r", out);
            break;
        case '\t':
            fputs("\\t", out);
            break;
        default:
            if (ch < 0x20) {
                fprintf(out, "\\u%04x", ch);
            } else {
                fputc(ch, out);
            }
        }
    }
    fputc('"', out);
}

static void iso8601_now(char *buf, size_t buf_len) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm;
    gmtime_r(&ts.tv_sec, &tm);
    strftime(buf, buf_len, "%Y-%m-%dT%H:%M:%S", &tm);
    size_t used = strlen(buf);
    snprintf(buf + used, buf_len - used, ".%03ldZ", ts.tv_nsec / 1000000L);
}

static bool file_sha256(const char *path, char out[65]) {
    int file_fd = open(path, O_RDONLY | O_CLOEXEC);
    if (file_fd < 0) {
        return false;
    }

    int tfm_fd = socket(AF_ALG, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    if (tfm_fd < 0) {
        close(file_fd);
        return false;
    }

    struct sockaddr_alg sa;
    memset(&sa, 0, sizeof(sa));
    sa.salg_family = AF_ALG;
    snprintf((char *)sa.salg_type, sizeof(sa.salg_type), "hash");
    snprintf((char *)sa.salg_name, sizeof(sa.salg_name), "sha256");
    if (bind(tfm_fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
        close(tfm_fd);
        close(file_fd);
        return false;
    }

    int op_fd = accept4(tfm_fd, NULL, 0, SOCK_CLOEXEC);
    close(tfm_fd);
    if (op_fd < 0) {
        close(file_fd);
        return false;
    }

    char buf[8192];
    for (;;) {
        ssize_t nread = read(file_fd, buf, sizeof(buf));
        if (nread < 0) {
            close(op_fd);
            close(file_fd);
            return false;
        }
        if (nread == 0) {
            break;
        }
        ssize_t written = 0;
        while (written < nread) {
            ssize_t nw = write(op_fd, buf + written, (size_t)(nread - written));
            if (nw < 0) {
                close(op_fd);
                close(file_fd);
                return false;
            }
            written += nw;
        }
    }

    unsigned char digest[32];
    ssize_t got = read(op_fd, digest, sizeof(digest));
    close(op_fd);
    close(file_fd);
    if (got != (ssize_t)sizeof(digest)) {
        snprintf(out, 65, "unavailable");
        return false;
    }
    for (size_t i = 0; i < sizeof(digest); i++) {
        snprintf(out + (i * 2), 3, "%02x", digest[i]);
    }
    out[64] = '\0';
    return true;
}

static bool slurp_file(const char *path, char **out, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        return false;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return false;
    }
    long len = ftell(f);
    if (len < 0 || len > 1024 * 1024) {
        fclose(f);
        return false;
    }
    rewind(f);
    char *buf = calloc((size_t)len + 1, 1);
    if (!buf) {
        fclose(f);
        return false;
    }
    if (fread(buf, 1, (size_t)len, f) != (size_t)len) {
        free(buf);
        fclose(f);
        return false;
    }
    fclose(f);
    *out = buf;
    *out_len = (size_t)len;
    return true;
}

static void add_policy_path(Policy *policy, const char *path) {
    if (policy->count >= MAX_POLICY_ENTRIES) {
        fprintf(stderr, "too many policy entries\n");
        exit(2);
    }

    PolicyEntry *entry = &policy->entries[policy->count];
    snprintf(entry->configured_path, sizeof(entry->configured_path), "%s", path);
    if (!realpath(path, entry->real_path)) {
        fprintf(stderr, "policy path does not resolve: %s\n", path);
        exit(2);
    }

    struct stat st;
    if (stat(entry->real_path, &st) < 0) {
        perror("stat policy path");
        exit(2);
    }
    entry->dev = st.st_dev;
    entry->ino = st.st_ino;
    file_sha256(entry->real_path, entry->sha256);
    policy->count++;
}

static void json_parse_error(const char *msg) {
    fprintf(stderr, "policy JSON parse error: %s\n", msg);
    exit(2);
}

static void skip_ws(const char **p) {
    while (**p == ' ' || **p == '\n' || **p == '\r' || **p == '\t') {
        (*p)++;
    }
}

static int json_hex_value(char ch) {
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f') {
        return 10 + ch - 'a';
    }
    if (ch >= 'A' && ch <= 'F') {
        return 10 + ch - 'A';
    }
    return -1;
}

static bool append_utf8_codepoint(char *out, size_t out_len, size_t *used, unsigned cp) {
    unsigned char bytes[4];
    size_t count = 0;

    if (cp <= 0x7f) {
        bytes[count++] = (unsigned char)cp;
    } else if (cp <= 0x7ff) {
        bytes[count++] = (unsigned char)(0xc0 | (cp >> 6));
        bytes[count++] = (unsigned char)(0x80 | (cp & 0x3f));
    } else if (cp >= 0xd800 && cp <= 0xdfff) {
        return false;
    } else if (cp <= 0xffff) {
        bytes[count++] = (unsigned char)(0xe0 | (cp >> 12));
        bytes[count++] = (unsigned char)(0x80 | ((cp >> 6) & 0x3f));
        bytes[count++] = (unsigned char)(0x80 | (cp & 0x3f));
    } else if (cp <= 0x10ffff) {
        bytes[count++] = (unsigned char)(0xf0 | (cp >> 18));
        bytes[count++] = (unsigned char)(0x80 | ((cp >> 12) & 0x3f));
        bytes[count++] = (unsigned char)(0x80 | ((cp >> 6) & 0x3f));
        bytes[count++] = (unsigned char)(0x80 | (cp & 0x3f));
    } else {
        return false;
    }

    if (*used + count >= out_len) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        out[(*used)++] = (char)bytes[i];
    }
    return true;
}

static bool parse_json_string(const char **p, char *out, size_t out_len) {
    skip_ws(p);
    if (**p != '"') {
        return false;
    }
    (*p)++;
    size_t used = 0;
    while (**p && **p != '"') {
        unsigned char ch = (unsigned char)**p;
        if (ch < 0x20) {
            return false;
        }
        if (ch == '\\') {
            (*p)++;
            ch = (unsigned char)**p;
            if (!ch) {
                return false;
            }
            switch (ch) {
            case '"':
            case '\\':
            case '/':
                break;
            case 'b':
                ch = '\b';
                break;
            case 'f':
                ch = '\f';
                break;
            case 'n':
                ch = '\n';
                break;
            case 'r':
                ch = '\r';
                break;
            case 't':
                ch = '\t';
                break;
            case 'u': {
                unsigned cp = 0;
                for (int i = 0; i < 4; i++) {
                    (*p)++;
                    int hv = json_hex_value(**p);
                    if (hv < 0) {
                        return false;
                    }
                    cp = (cp << 4) | (unsigned)hv;
                }
                if (!append_utf8_codepoint(out, out_len, &used, cp)) {
                    return false;
                }
                (*p)++;
                continue;
            }
            default:
                return false;
            }
        }
        if (used + 1 >= out_len) {
            return false;
        }
        out[used++] = (char)ch;
        (*p)++;
    }
    if (**p != '"') {
        return false;
    }
    (*p)++;
    out[used] = '\0';
    return true;
}

static bool skip_json_value(const char **p, unsigned depth);

static bool skip_json_array(const char **p, unsigned depth) {
    if (depth > MAX_JSON_DEPTH) {
        return false;
    }
    if (**p != '[') {
        return false;
    }
    (*p)++;
    skip_ws(p);
    if (**p == ']') {
        (*p)++;
        return true;
    }
    for (;;) {
        if (!skip_json_value(p, depth + 1)) {
            return false;
        }
        skip_ws(p);
        if (**p == ']') {
            (*p)++;
            return true;
        }
        if (**p != ',') {
            return false;
        }
        (*p)++;
    }
}

static bool skip_json_object(const char **p, unsigned depth) {
    if (depth > MAX_JSON_DEPTH) {
        return false;
    }
    char key[256];
    if (**p != '{') {
        return false;
    }
    (*p)++;
    skip_ws(p);
    if (**p == '}') {
        (*p)++;
        return true;
    }
    for (;;) {
        if (!parse_json_string(p, key, sizeof(key))) {
            return false;
        }
        skip_ws(p);
        if (**p != ':') {
            return false;
        }
        (*p)++;
        if (!skip_json_value(p, depth + 1)) {
            return false;
        }
        skip_ws(p);
        if (**p == '}') {
            (*p)++;
            return true;
        }
        if (**p != ',') {
            return false;
        }
        (*p)++;
    }
}

static bool skip_json_literal(const char **p, const char *literal) {
    size_t len = strlen(literal);
    if (strncmp(*p, literal, len) != 0) {
        return false;
    }
    *p += len;
    return true;
}

static bool skip_json_number(const char **p) {
    const char *start = *p;
    if (**p == '-') {
        (*p)++;
    }
    if (**p == '0') {
        (*p)++;
    } else if (**p >= '1' && **p <= '9') {
        while (**p >= '0' && **p <= '9') {
            (*p)++;
        }
    } else {
        return false;
    }
    if (**p == '.') {
        (*p)++;
        if (!(**p >= '0' && **p <= '9')) {
            return false;
        }
        while (**p >= '0' && **p <= '9') {
            (*p)++;
        }
    }
    if (**p == 'e' || **p == 'E') {
        (*p)++;
        if (**p == '+' || **p == '-') {
            (*p)++;
        }
        if (!(**p >= '0' && **p <= '9')) {
            return false;
        }
        while (**p >= '0' && **p <= '9') {
            (*p)++;
        }
    }
    return *p > start;
}

static bool skip_json_value(const char **p, unsigned depth) {
    if (depth > MAX_JSON_DEPTH) {
        return false;
    }
    char ignored[256];
    skip_ws(p);
    switch (**p) {
    case '"':
        return parse_json_string(p, ignored, sizeof(ignored));
    case '{':
        return skip_json_object(p, depth + 1);
    case '[':
        return skip_json_array(p, depth + 1);
    case 't':
        return skip_json_literal(p, "true");
    case 'f':
        return skip_json_literal(p, "false");
    case 'n':
        return skip_json_literal(p, "null");
    default:
        return skip_json_number(p);
    }
}

static void load_policy(const char *path, Policy *policy) {
    memset(policy, 0, sizeof(*policy));
    snprintf(policy->policy_id, sizeof(policy->policy_id), "unknown");

    char *buf = NULL;
    size_t len = 0;
    if (!slurp_file(path, &buf, &len)) {
        perror("read policy");
        exit(2);
    }

    const char *cursor = buf;
    bool saw_allowed = false;
    skip_ws(&cursor);
    if (*cursor != '{') {
        free(buf);
        json_parse_error("root must be object");
    }
    cursor++;
    skip_ws(&cursor);
    if (*cursor != '}') {
        for (;;) {
            char key[256];
            if (!parse_json_string(&cursor, key, sizeof(key))) {
                free(buf);
                json_parse_error("object key must be string");
            }
            skip_ws(&cursor);
            if (*cursor != ':') {
                free(buf);
                json_parse_error("missing ':' after key");
            }
            cursor++;
            skip_ws(&cursor);

            if (strcmp(key, "policy_id") == 0) {
                if (!parse_json_string(&cursor, policy->policy_id, sizeof(policy->policy_id))) {
                    free(buf);
                    json_parse_error("policy_id must be string");
                }
            } else if (strcmp(key, "allowed_executables") == 0) {
                saw_allowed = true;
                if (*cursor != '[') {
                    free(buf);
                    json_parse_error("allowed_executables must be array");
                }
                cursor++;
                skip_ws(&cursor);
                if (*cursor == ']') {
                    cursor++;
                } else {
                    for (;;) {
                        char candidate[PATH_MAX];
                        if (!parse_json_string(&cursor, candidate, sizeof(candidate))) {
                            free(buf);
                            json_parse_error("allowed_executables entries must be strings");
                        }
                        if (candidate[0] != '/') {
                            free(buf);
                            json_parse_error("allowed_executables entries must be absolute paths");
                        }
                        add_policy_path(policy, candidate);
                        skip_ws(&cursor);
                        if (*cursor == ']') {
                            cursor++;
                            break;
                        }
                        if (*cursor != ',') {
                            free(buf);
                            json_parse_error("malformed allowed_executables array");
                        }
                        cursor++;
                    }
                }
            } else if (!skip_json_value(&cursor, 0)) {
                free(buf);
                json_parse_error("malformed JSON value");
            }

            skip_ws(&cursor);
            if (*cursor == '}') {
                cursor++;
                break;
            }
            if (*cursor != ',') {
                free(buf);
                json_parse_error("missing ',' between object fields");
            }
            cursor++;
            skip_ws(&cursor);
        }
    } else {
        cursor++;
    }
    skip_ws(&cursor);
    if (*cursor != '\0') {
        free(buf);
        json_parse_error("trailing data after root object");
    }

    free(buf);
    if (!saw_allowed || policy->count == 0) {
        fprintf(stderr, "policy has no allowed executable paths\n");
        exit(2);
    }
}

static bool read_child_cwd(pid_t pid, char *buf, size_t buf_len) {
    char proc_path[64];
    snprintf(proc_path, sizeof(proc_path), "/proc/%d/cwd", pid);
    ssize_t n = readlink(proc_path, buf, buf_len - 1);
    if (n < 0) {
        snprintf(buf, buf_len, "<unavailable>");
        return false;
    }
    buf[n] = '\0';
    return true;
}

static bool resolve_child_exe(pid_t pid, const char *raw, char *cwd, size_t cwd_len,
                              char *resolved, size_t resolved_len) {
    read_child_cwd(pid, cwd, cwd_len);

    char candidate[PATH_MAX];
    if (strncmp(raw, "/proc/self/", 11) == 0) {
        snprintf(candidate, sizeof(candidate), "/proc/%d/%s", pid, raw + 11);
    } else if (strcmp(raw, "/proc/self") == 0) {
        snprintf(candidate, sizeof(candidate), "/proc/%d", pid);
    } else if (raw[0] == '/') {
        snprintf(candidate, sizeof(candidate), "/proc/%d/root%s", pid, raw);
    } else if (strchr(raw, '/')) {
        snprintf(candidate, sizeof(candidate), "%s/%s", cwd, raw);
    } else {
        snprintf(resolved, resolved_len, "<unresolved-no-slash:%s>", raw);
        return false;
    }

    char real[PATH_MAX];
    if (!realpath(candidate, real)) {
        snprintf(resolved, resolved_len, "<unresolved>");
        return false;
    }
    snprintf(resolved, resolved_len, "%s", real);
    return true;
}

static void capture_argv_json(pid_t pid, uint64_t argv_addr, char *out, size_t out_len,
                              bool *truncated, size_t *total_count, bool *count_capped) {
    if (truncated) {
        *truncated = false;
    }
    if (total_count) {
        *total_count = 0;
    }
    if (count_capped) {
        *count_capped = false;
    }
    size_t used = 0;
    used += snprintf(out + used, out_len - used, "[");
    bool saw_argv_terminator = false;
    for (size_t i = 0; i < MAX_ARGV_COUNT_SCAN; i++) {
        uint64_t ptr = 0;
        if (!read_child_bytes(pid, argv_addr + (i * sizeof(uint64_t)), &ptr, sizeof(ptr))) {
            break;
        }
        if (ptr == 0) {
            saw_argv_terminator = true;
            break;
        }
        if (total_count) {
            (*total_count)++;
        }
        if (i >= MAX_ARGV_CAPTURE) {
            if (truncated) {
                *truncated = true;
            }
            continue;
        }
        if (used >= out_len) {
            if (truncated) {
                *truncated = true;
            }
            continue;
        }
        char arg[512];
        bool arg_truncated = false;
        if (!read_child_string_ex(pid, ptr, arg, sizeof(arg), &arg_truncated)) {
            snprintf(arg, sizeof(arg), "<unreadable>");
        }
        if (arg_truncated && truncated) {
            *truncated = true;
        }
        if (i > 0) {
            used += snprintf(out + used, out_len - used, ",");
        }
        FILE *mem = fmemopen(out + used, out_len - used, "w");
        if (!mem) {
            break;
        }
        json_escape(mem, arg);
        long written = ftell(mem);
        fclose(mem);
        if (written < 0) {
            break;
        }
        used += (size_t)written;
        if (used >= out_len && truncated) {
            *truncated = true;
        }
    }
    if (!saw_argv_terminator) {
        if (truncated) {
            *truncated = true;
        }
        if (count_capped) {
            *count_capped = true;
        }
    }
    if (used < out_len) {
        snprintf(out + used, out_len - used, "]");
    } else if (out_len > 0) {
        out[out_len - 1] = '\0';
        if (truncated) {
            *truncated = true;
        }
    }
}

static bool policy_allows_identity(const Policy *policy, const char *real_path, dev_t dev, ino_t ino) {
    for (size_t i = 0; i < policy->count; i++) {
        const PolicyEntry *entry = &policy->entries[i];
        if (entry->dev == dev && entry->ino == ino && strcmp(entry->real_path, real_path) == 0) {
            return true;
        }
    }
    return false;
}

static bool landlock_path_already_added(const char added[][PATH_MAX], size_t count, const char *path) {
    for (size_t i = 0; i < count; i++) {
        if (strcmp(added[i], path) == 0) {
            return true;
        }
    }
    return false;
}

static int landlock_add_exec_file_rule(int ruleset_fd, const char *path) {
    int fd = open(path, O_PATH | O_CLOEXEC);
    if (fd < 0) {
        return -1;
    }

    struct landlock_path_beneath_attr rule = {
        .allowed_access = LANDLOCK_ACCESS_FS_EXECUTE,
        .parent_fd = fd,
    };
    int rc = landlock_add_rule_wrap(ruleset_fd, LANDLOCK_RULE_PATH_BENEATH, &rule, 0);
    close(fd);
    return rc;
}

static int landlock_add_unique_exec_path(int ruleset_fd, char added[][PATH_MAX],
                                         size_t *added_count, const char *path) {
    char resolved[PATH_MAX];
    if (!realpath(path, resolved)) {
        return 0;
    }
    if (landlock_path_already_added(added, *added_count, resolved)) {
        return 0;
    }
    if (landlock_add_exec_file_rule(ruleset_fd, resolved) < 0) {
        return -1;
    }
    if (*added_count < MAX_POLICY_ENTRIES + 8) {
        snprintf(added[*added_count], PATH_MAX, "%s", resolved);
        (*added_count)++;
    }
    return 0;
}

static int install_landlock_execute_underlay(const Policy *policy) {
    int abi = landlock_create_ruleset_wrap(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION);
    if (abi < 0) {
        return -1;
    }

    struct landlock_ruleset_attr ruleset = {
        .handled_access_fs = LANDLOCK_ACCESS_FS_EXECUTE,
    };
    int ruleset_fd = landlock_create_ruleset_wrap(&ruleset, sizeof(ruleset), 0);
    if (ruleset_fd < 0) {
        return -1;
    }

    char added[MAX_POLICY_ENTRIES + 8][PATH_MAX];
    memset(added, 0, sizeof(added));
    size_t added_count = 0;

    for (size_t i = 0; i < policy->count; i++) {
        if (landlock_add_unique_exec_path(ruleset_fd, added, &added_count,
                                          policy->entries[i].real_path) < 0) {
            close(ruleset_fd);
            return -1;
        }
    }

    const char *loaders[] = {
        "/lib64/ld-linux-x86-64.so.2",
        "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
        "/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
    };
    for (size_t i = 0; i < sizeof(loaders) / sizeof(loaders[0]); i++) {
        if (landlock_add_unique_exec_path(ruleset_fd, added, &added_count, loaders[i]) < 0) {
            close(ruleset_fd);
            return -1;
        }
    }

    if (landlock_restrict_self_wrap(ruleset_fd, 0) < 0) {
        close(ruleset_fd);
        return -1;
    }
    close(ruleset_fd);
    return 0;
}

static void decide_exec(const Policy *policy, const struct seccomp_notif *req, Decision *decision) {
    memset(decision, 0, sizeof(*decision));
    snprintf(decision->reason, sizeof(decision->reason), "uninitialized");
    snprintf(decision->sha256, sizeof(decision->sha256), "unavailable");

    if (req->data.nr != __NR_execve) {
        decision->allowed = false;
        snprintf(decision->reason, sizeof(decision->reason), "execveat_not_supported_in_sprint2");
        snprintf(decision->raw_exe, sizeof(decision->raw_exe), "<execveat>");
        capture_argv_json(req->pid, req->data.args[2], decision->argv_json,
                          sizeof(decision->argv_json), &decision->argv_truncated,
                          &decision->argv_total_count, &decision->argv_total_count_capped);
        return;
    }

    if (!read_child_string(req->pid, req->data.args[0], decision->raw_exe,
                           sizeof(decision->raw_exe))) {
        decision->allowed = false;
        snprintf(decision->reason, sizeof(decision->reason), "unreadable_executable_path");
        return;
    }

    capture_argv_json(req->pid, req->data.args[1], decision->argv_json,
                      sizeof(decision->argv_json), &decision->argv_truncated,
                      &decision->argv_total_count, &decision->argv_total_count_capped);

    if (!resolve_child_exe(req->pid, decision->raw_exe, decision->cwd, sizeof(decision->cwd),
                           decision->real_path, sizeof(decision->real_path))) {
        decision->allowed = false;
        snprintf(decision->reason, sizeof(decision->reason), "unresolved_executable_identity");
        return;
    }

    struct stat st;
    if (stat(decision->real_path, &st) < 0) {
        decision->allowed = false;
        snprintf(decision->reason, sizeof(decision->reason), "stat_failed");
        return;
    }
    decision->dev = st.st_dev;
    decision->ino = st.st_ino;
    file_sha256(decision->real_path, decision->sha256);

    if (policy_allows_identity(policy, decision->real_path, decision->dev, decision->ino)) {
        decision->allowed = true;
        snprintf(decision->reason, sizeof(decision->reason), "allowed_executable_identity");
    } else {
        decision->allowed = false;
        snprintf(decision->reason, sizeof(decision->reason), "blocked_executable_identity");
    }
}

static void write_decision_json(const char *event, const Policy *policy,
                                const struct seccomp_notif *req,
                                const Decision *decision, int child_exit) {
    char ts[64];
    iso8601_now(ts, sizeof(ts));

    FILE *out = audit_stream();
    fprintf(out, "{\"event\":");
    json_escape(out, event);
    fprintf(out, ",\"timestamp\":");
    json_escape(out, ts);
    fprintf(out, ",\"policy_id\":");
    json_escape(out, policy->policy_id);
    if (req) {
        fprintf(out, ",\"pid\":%d,\"syscall\":%d,\"notif_id\":%llu",
                req->pid, req->data.nr, (unsigned long long)req->id);
    }
    if (decision) {
        fprintf(out, ",\"decision\":");
        json_escape(out, decision->allowed ? "ALLOW" : "BLOCK");
        fprintf(out, ",\"reason\":");
        json_escape(out, decision->reason);
        fprintf(out, ",\"raw_exe\":");
        json_escape(out, decision->raw_exe);
        fprintf(out, ",\"realpath\":");
        json_escape(out, decision->real_path);
        fprintf(out, ",\"cwd\":");
        json_escape(out, decision->cwd);
        fprintf(out, ",\"dev\":%llu,\"ino\":%llu,\"sha256\":",
                (unsigned long long)decision->dev, (unsigned long long)decision->ino);
        json_escape(out, decision->sha256);
        fprintf(out, ",\"argv\":%s", decision->argv_json[0] ? decision->argv_json : "[]");
        fprintf(out,
                ",\"argv_truncated\":%s,\"argv_total_count\":%zu,\"argv_total_count_capped\":%s",
                decision->argv_truncated ? "true" : "false", decision->argv_total_count,
                decision->argv_total_count_capped ? "true" : "false");
    }
    if (child_exit >= 0) {
        fprintf(out, ",\"child_exit\":%d", child_exit);
    }
    fprintf(out, "}\n");
    fflush(out);
}

static void write_child_stderr_json(const Policy *policy, const char *buf, size_t len) {
    char ts[64];
    iso8601_now(ts, sizeof(ts));
    FILE *out = audit_stream();
    fprintf(out, "{\"event\":\"child_stderr\",\"timestamp\":");
    json_escape(out, ts);
    fprintf(out, ",\"policy_id\":");
    json_escape(out, policy->policy_id);
    fprintf(out, ",\"data\":");
    json_escape_bytes(out, buf, len);
    fprintf(out, "}\n");
    fflush(out);
}

static bool notification_id_valid(int listener_fd, uint64_t id) {
    return ioctl(listener_fd, SECCOMP_IOCTL_NOTIF_ID_VALID, &id) == 0;
}

static int supervise(int listener_fd, int child_stderr_fd, pid_t child, const Policy *policy) {
    int child_status = 0;
    bool child_stderr_open = child_stderr_fd >= 0;

    for (;;) {
        pid_t waited = waitpid(child, &child_status, WNOHANG);
        if (waited == child) {
            break;
        }
        if (waited < 0) {
            perror("waitpid");
            return 2;
        }

        struct pollfd pfds[2];
        pfds[0].fd = listener_fd;
        pfds[0].events = POLLIN;
        pfds[0].revents = 0;
        pfds[1].fd = child_stderr_open ? child_stderr_fd : -1;
        pfds[1].events = POLLIN | POLLHUP;
        pfds[1].revents = 0;
        int poll_rc = poll(pfds, 2, 100);
        if (poll_rc < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("poll");
            return 2;
        }
        if (poll_rc == 0) {
            continue;
        }
        if (child_stderr_open && (pfds[1].revents & (POLLIN | POLLHUP))) {
            char buf[1024];
            ssize_t nread = read(child_stderr_fd, buf, sizeof(buf));
            if (nread > 0) {
                write_child_stderr_json(policy, buf, (size_t)nread);
            } else if (nread == 0 || (nread < 0 && errno != EINTR && errno != EAGAIN)) {
                close(child_stderr_fd);
                child_stderr_open = false;
            }
        }
        if (!(pfds[0].revents & POLLIN)) {
            continue;
        }

        struct seccomp_notif req;
        struct seccomp_notif_resp resp;
        memset(&req, 0, sizeof(req));
        memset(&resp, 0, sizeof(resp));

        if (ioctl(listener_fd, SECCOMP_IOCTL_NOTIF_RECV, &req) < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == ENOENT) {
                if (waitpid(child, &child_status, 0) == child) {
                    break;
                }
            }
            if (waitpid(child, &child_status, WNOHANG) == child) {
                break;
            }
            perror("ioctl(SECCOMP_IOCTL_NOTIF_RECV)");
            return 2;
        }

        Decision decision;
        decide_exec(policy, &req, &decision);

        resp.id = req.id;
        resp.val = 0;

        if (!notification_id_valid(listener_fd, req.id)) {
            decision.allowed = false;
            snprintf(decision.reason, sizeof(decision.reason), "notification_id_invalid");
        }

        if (decision.allowed) {
            resp.error = 0;
            resp.flags = SECCOMP_USER_NOTIF_FLAG_CONTINUE;
        } else {
            resp.error = -EPERM;
            resp.flags = 0;
        }

        write_decision_json("exec_decision", policy, &req, &decision, -1);

        if (ioctl(listener_fd, SECCOMP_IOCTL_NOTIF_SEND, &resp) < 0) {
            perror("ioctl(SECCOMP_IOCTL_NOTIF_SEND)");
            return 2;
        }
    }

    int exit_code = 2;
    if (WIFEXITED(child_status)) {
        exit_code = WEXITSTATUS(child_status);
    } else if (WIFSIGNALED(child_status)) {
        exit_code = 128 + WTERMSIG(child_status);
    }
    write_decision_json("supervisor_exit", policy, NULL, NULL, exit_code);
    return exit_code;
}

static void usage(const char *argv0) {
    fprintf(stderr, "usage: %s --policy policy.json /path/to/command [args...]\n", argv0);
}

int main(int argc, char **argv) {
    if (argc < 4 || strcmp(argv[1], "--policy") != 0) {
        usage(argv[0]);
        return 2;
    }

    Policy policy;
    load_policy(argv[2], &policy);

    audit_fd = fcntl(STDERR_FILENO, F_DUPFD_CLOEXEC, 3);
    if (audit_fd < 0) {
        die("dup audit fd");
    }
    audit_out = fdopen(audit_fd, "a");
    if (!audit_out) {
        die("fdopen audit fd");
    }
    setvbuf(audit_out, NULL, _IOLBF, 0);
    install_signal_handlers();

    int socks[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, socks) < 0) {
        die("socketpair");
    }

    int child_stderr[2];
    if (pipe2(child_stderr, O_CLOEXEC) < 0) {
        die("pipe2 child stderr");
    }
    int flags = fcntl(child_stderr[0], F_GETFL, 0);
    if (flags >= 0) {
        fcntl(child_stderr[0], F_SETFL, flags | O_NONBLOCK);
    }

    pid_t child = fork();
    if (child < 0) {
        die("fork");
    }

    if (child == 0) {
        reset_signal_handlers();
        close(child_stderr[0]);
        if (dup2(child_stderr[1], STDERR_FILENO) < 0) {
            _exit(2);
        }
        close(child_stderr[1]);
        close(audit_fd);
        close(socks[0]);
        int listener_fd = install_exec_listener();
        if (listener_fd < 0) {
            perror("install_exec_listener");
            _exit(2);
        }
        send_fd(socks[1], listener_fd);
        close(listener_fd);
        close(socks[1]);

        if (install_landlock_execute_underlay(&policy) < 0) {
            perror("install_landlock_execute_underlay");
            _exit(2);
        }

        execvp(argv[3], &argv[3]);
        int saved_errno = errno;
        perror("execvp");
        _exit(saved_errno == EACCES || saved_errno == EPERM ? 126 : 127);
    }

    close(socks[1]);
    close(child_stderr[1]);
    int listener_fd = recv_fd(socks[0]);
    close(socks[0]);
    return supervise(listener_fd, child_stderr[0], child, &policy);
}
