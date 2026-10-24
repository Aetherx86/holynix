/*
 * HolyC Unix Kernel - Process & Task Scheduler Subsystem (Task.HC)
 * Process Control Blocks (CTask), Process Queues, Round-Robin Scheduler, and Context Management.
 */

#ifndef TASK_HC
#define TASK_HC

#include "Types.HC"
#include "VFS.HC"

class CTask {
    I64 pid;
    I64 ppid;
    U8 comm[32];
    I64 state;
    I64 exit_code;
    U8 cwd[MAX_PATH_LEN];
    I64 fd_table[MAX_FDS];
    I64 sleep_until_ms;
    I64 ticks_used;
    I64 priority;
    I64 uid;
    I64 gid;
    TaskEntryFn entry_fn;
    U0 *entry_arg;
};

static CTask g_tasks[MAX_TASKS];
static I64 g_current_pid = 0;
static I64 g_system_ticks = 0;
static I64 g_kernel_start_time_ms = 0;

I64 KernelGetUptimeSec() {
    I64 now = GetTimestampMs();
    return (now - g_kernel_start_time_ms) / 1000;
}

I64 KernelGetTicks() {
    return g_system_ticks;
}

CTask *TaskGetCurrent() {
    return &g_tasks[g_current_pid];
}

CTask *TaskGetByPid(I64 pid) {
    if (pid < 0 || pid >= MAX_TASKS) return NULL;
    if (g_tasks[pid].state == TASK_UNUSED) return NULL;
    return &g_tasks[pid];
}

I64 TaskFormatProcTasks(U8 *buf, I64 max_len) {
    if (!buf || max_len <= 0) return 0;
    I64 offset = 0;
    offset += snprintf((char*)buf + offset, max_len - offset,
        "  PID  PPID STATE     TICKS COMMAND\n");

    for (I64 i = 0; i < MAX_TASKS; ++i) {
        if (g_tasks[i].state == TASK_UNUSED) continue;
        const char *st_str = "UNKNOWN";
        switch (g_tasks[i].state) {
            case TASK_READY:    st_str = "READY   "; break;
            case TASK_RUNNING:  st_str = "RUNNING "; break;
            case TASK_SLEEPING: st_str = "SLEEPING"; break;
            case TASK_ZOMBIE:   st_str = "ZOMBIE  "; break;
            case TASK_STOPPED:  st_str = "STOPPED "; break;
        }
        offset += snprintf((char*)buf + offset, max_len - offset,
            "%5lld %5lld %s %7lld %s\n",
            (long long)g_tasks[i].pid,
            (long long)g_tasks[i].ppid,
            st_str,
            (long long)g_tasks[i].ticks_used,
            (const char*)g_tasks[i].comm);
        if (offset >= max_len - 100) break;
    }
    return offset;
}

/* Wrapper for procfs */
I64 KernelFormatProcTasks(U8 *buf, I64 max_len) {
    return TaskFormatProcTasks(buf, max_len);
}

I64 TaskSpawn(const U8 *name, TaskEntryFn fn, U0 *arg, I64 ppid) {
    I64 slot = -1;
    for (I64 i = 1; i < MAX_TASKS; ++i) {
        if (g_tasks[i].state == TASK_UNUSED) {
            slot = i;
            break;
        }
    }
    if (slot < 0) return -1; /* Process table full */

    CTask *t = &g_tasks[slot];
    MemSet(t, 0, sizeof(CTask));
    t->pid = slot;
    t->ppid = ppid;
    StrNCpy(t->comm, name, 31);
    t->state = TASK_READY;
    t->exit_code = 0;
    t->sleep_until_ms = 0;
    t->ticks_used = 0;
    t->priority = 10;
    t->uid = (ppid == 0) ? 0 : g_tasks[ppid].uid;
    t->gid = (ppid == 0) ? 0 : g_tasks[ppid].gid;
    t->entry_fn = fn;
    t->entry_arg = arg;

    /* Copy CWD from parent */
    if (ppid >= 0 && ppid < MAX_TASKS && g_tasks[ppid].state != TASK_UNUSED) {
        StrNCpy(t->cwd, g_tasks[ppid].cwd, MAX_PATH_LEN - 1);
    } else {
        StrCpy(t->cwd, "/");
    }

    /* Initialize FD table: stdin, stdout, stderr -> /dev/tty */
    for (I64 f = 0; f < MAX_FDS; ++f) {
        t->fd_table[f] = -1;
    }

    /* Open default standard streams */
    t->fd_table[STDIN_FILENO]  = VFSOpen("/dev/tty", "/", O_RDONLY);
    t->fd_table[STDOUT_FILENO] = VFSOpen("/dev/tty", "/", O_WRONLY);
    t->fd_table[STDERR_FILENO] = VFSOpen("/dev/tty", "/", O_WRONLY);

    return t->pid;
}

U0 TaskExit(I64 exit_code) {
    CTask *curr = TaskGetCurrent();
    if (!curr || curr->pid == 0) return; /* Never exit idle task */

    curr->state = TASK_ZOMBIE;
    curr->exit_code = exit_code;

    /* Close all open file descriptors */
    for (I64 f = 0; f < MAX_FDS; ++f) {
        if (curr->fd_table[f] >= 0) {
            VFSClose(curr->fd_table[f]);
            curr->fd_table[f] = -1;
        }
    }
}

I64 TaskWaitPid(I64 pid, I64 *status) {
    if (pid <= 0 || pid >= MAX_TASKS) return -1;
    CTask *child = &g_tasks[pid];
    if (child->state == TASK_UNUSED) return -1;

    /* Loop until child becomes zombie */
    while (child->state != TASK_ZOMBIE && child->state != TASK_UNUSED) {
        /* Run child task if ready */
        if (child->state == TASK_READY || child->state == TASK_RUNNING) {
            if (child->entry_fn) {
                I64 prev = g_current_pid;
                g_current_pid = child->pid;
                child->state = TASK_RUNNING;
                I64 code = child->entry_fn(child->entry_arg);
                TaskExit(code);
                g_current_pid = prev;
                break;
            }
        }
        SleepMs(1);
    }

    if (child->state == TASK_ZOMBIE) {
        if (status) *status = child->exit_code;
        I64 reaped_pid = child->pid;
        child->state = TASK_UNUSED; /* Free slot */
        return reaped_pid;
    }
    return -1;
}

I64 TaskKill(I64 pid, I64 sig) {
    if (pid <= 0 || pid >= MAX_TASKS) return -1;
    CTask *t = &g_tasks[pid];
    if (t->state == TASK_UNUSED) return -1;

    if (sig == SIGKILL || sig == SIGTERM || sig == SIGINT) {
        t->state = TASK_ZOMBIE;
        t->exit_code = 128 + sig;
        for (I64 f = 0; f < MAX_FDS; ++f) {
            if (t->fd_table[f] >= 0) {
                VFSClose(t->fd_table[f]);
                t->fd_table[f] = -1;
            }
        }
        return 0;
    }
    return 0;
}

U0 TaskYield() {
    g_system_ticks++;
    CTask *curr = TaskGetCurrent();
    if (curr) curr->ticks_used++;

    I64 now_ms = GetTimestampMs();
    /* Wake up sleeping tasks */
    for (I64 i = 0; i < MAX_TASKS; ++i) {
        if (g_tasks[i].state == TASK_SLEEPING && now_ms >= g_tasks[i].sleep_until_ms) {
            g_tasks[i].state = TASK_READY;
        }
    }
}

#define MAX_JOBS 16
#define JOB_RUNNING 1
#define JOB_STOPPED 2
#define JOB_DONE    3

class CJob {
    I64 job_id;
    I64 pid;
    char comm[64];
    I64 status;
    Bool active;
};

static CJob g_jobs[MAX_JOBS];
static I64 g_next_job_id = 1;

I64 JobAdd(I64 pid, const char *comm) {
    for (I64 i = 0; i < MAX_JOBS; ++i) {
        if (!g_jobs[i].active) {
            g_jobs[i].job_id = g_next_job_id++;
            g_jobs[i].pid = pid;
            strncpy(g_jobs[i].comm, comm ? comm : "command", sizeof(g_jobs[i].comm) - 1);
            g_jobs[i].status = JOB_RUNNING;
            g_jobs[i].active = TRUE;
            return g_jobs[i].job_id;
        }
    }
    return -1;
}

CJob *JobGet(I64 job_id) {
    for (I64 i = 0; i < MAX_JOBS; ++i) {
        if (g_jobs[i].active && g_jobs[i].job_id == job_id) {
            return &g_jobs[i];
        }
    }
    return NULL;
}

U0 JobRemove(I64 job_id) {
    for (I64 i = 0; i < MAX_JOBS; ++i) {
        if (g_jobs[i].active && g_jobs[i].job_id == job_id) {
            g_jobs[i].active = FALSE;
            return;
        }
    }
}

I64 JobFormatList(char *out_buf, I64 max_len) {
    if (!out_buf || max_len <= 0) return 0;
    I64 offset = 0;
    out_buf[0] = '\0';

    for (I64 i = 0; i < MAX_JOBS; ++i) {
        if (g_jobs[i].active) {
            /* Check if pid is still active */
            CTask *t = TaskGetByPid(g_jobs[i].pid);
            if (!t || t->state == TASK_ZOMBIE || t->state == TASK_UNUSED) {
                g_jobs[i].status = JOB_DONE;
            }
            const char *st_str = (g_jobs[i].status == JOB_RUNNING) ? "Running" :
                                 (g_jobs[i].status == JOB_STOPPED) ? "Stopped" : "Done";

            offset += snprintf(out_buf + offset, max_len - offset,
                               "[%lld]+  %-9s %s &\n",
                               (long long)g_jobs[i].job_id,
                               st_str,
                               g_jobs[i].comm);
            if (offset >= max_len - 128) break;
        }
    }
    return offset;
}

/* -------------------------------------------------------------------------
 * Cron Scheduled Task Subsystem
 * ------------------------------------------------------------------------- */
#define MAX_CRON_JOBS 8

class CCronEntry {
    I64 id;
    I64 interval_sec;
    I64 last_run_sec;
    char cmd[128];
    Bool active;
};

static CCronEntry g_cron_entries[MAX_CRON_JOBS];
static I64 g_next_cron_id = 1;

I64 CronAdd(I64 interval_sec, const char *cmd) {
    if (interval_sec <= 0 || !cmd || !*cmd) return -1;
    for (I64 i = 0; i < MAX_CRON_JOBS; ++i) {
        if (!g_cron_entries[i].active) {
            g_cron_entries[i].id = g_next_cron_id++;
            g_cron_entries[i].interval_sec = interval_sec;
            g_cron_entries[i].last_run_sec = KernelGetUptimeSec();
            strncpy(g_cron_entries[i].cmd, cmd, sizeof(g_cron_entries[i].cmd) - 1);
            g_cron_entries[i].active = TRUE;
            return g_cron_entries[i].id;
        }
    }
    return -1;
}

I64 CronList(char *out_buf, I64 max_len) {
    if (!out_buf || max_len <= 0) return 0;
    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "\033[93mID  INTERVAL(s)  LAST_RUN(s)  COMMAND\033[0m\n"
        "-----------------------------------------\n");

    for (I64 i = 0; i < MAX_CRON_JOBS; ++i) {
        if (g_cron_entries[i].active) {
            offset += snprintf(out_buf + offset, max_len - offset,
                               "%-3lld %-12lld %-12lld %s\n",
                               (long long)g_cron_entries[i].id,
                               (long long)g_cron_entries[i].interval_sec,
                               (long long)g_cron_entries[i].last_run_sec,
                               g_cron_entries[i].cmd);
            if (offset >= max_len - 128) break;
        }
    }
    return offset;
}

#define MAX_MODULES 16

class CModule {
    char name[32];
    I64 size;
    I64 ref_count;
    char author[32];
    Bool loaded;
};

static CModule g_modules[MAX_MODULES];
static I64 g_module_count = 0;

U0 ModuleInit() {
    MemSet(g_modules, 0, sizeof(g_modules));
    g_module_count = 0;

    strncpy(g_modules[0].name, "god_oracle", 31);
    g_modules[0].size = 16384;
    g_modules[0].ref_count = 1;
    strncpy(g_modules[0].author, "Terry A. Davis", 31);
    g_modules[0].loaded = TRUE;

    strncpy(g_modules[1].name, "vga_16color", 31);
    g_modules[1].size = 32768;
    g_modules[1].ref_count = 2;
    strncpy(g_modules[1].author, "TempleOS Kernel", 31);
    g_modules[1].loaded = TRUE;

    strncpy(g_modules[2].name, "redsea_fs", 31);
    g_modules[2].size = 24576;
    g_modules[2].ref_count = 1;
    strncpy(g_modules[2].author, "Terry A. Davis", 31);
    g_modules[2].loaded = TRUE;

    strncpy(g_modules[3].name, "snd_pcspeaker", 31);
    g_modules[3].size = 12288;
    g_modules[3].ref_count = 0;
    strncpy(g_modules[3].author, "HolyC Audio Core", 31);
    g_modules[3].loaded = TRUE;

    g_module_count = 4;
}

I64 ModuleAdd(const char *name, I64 size, const char *author) {
    if (!name || !*name) return -1;
    for (I64 i = 0; i < MAX_MODULES; ++i) {
        if (g_modules[i].loaded && strcmp(g_modules[i].name, name) == 0) {
            return -1;
        }
    }
    for (I64 i = 0; i < MAX_MODULES; ++i) {
        if (!g_modules[i].loaded) {
            strncpy(g_modules[i].name, name, 31);
            g_modules[i].size = (size > 0) ? size : 16384;
            g_modules[i].ref_count = 0;
            strncpy(g_modules[i].author, author ? author : "Terry A. Davis", 31);
            g_modules[i].loaded = TRUE;
            g_module_count++;
            return 0;
        }
    }
    return -1;
}

I64 ModuleRemove(const char *name) {
    if (!name || !*name) return -1;
    for (I64 i = 0; i < MAX_MODULES; ++i) {
        if (g_modules[i].loaded && strcmp(g_modules[i].name, name) == 0) {
            if (g_modules[i].ref_count > 0) return -2;
            g_modules[i].loaded = FALSE;
            g_module_count--;
            return 0;
        }
    }
    return -1;
}

I64 ModuleFormatList(char *out_buf, I64 max_len) {
    if (!out_buf || max_len <= 0) return 0;
    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "Module                  Size  Used by\n");
    for (I64 i = 0; i < MAX_MODULES; ++i) {
        if (g_modules[i].loaded) {
            offset += snprintf(out_buf + offset, max_len - offset,
                "%-20s %6lld  %lld\n",
                g_modules[i].name, (long long)g_modules[i].size, (long long)g_modules[i].ref_count);
            if (offset >= max_len - 128) break;
        }
    }
    return offset;
}

I64 ModuleFormatProc(char *out_buf, I64 max_len) {
    if (!out_buf || max_len <= 0) return 0;
    I64 offset = 0;
    for (I64 i = 0; i < MAX_MODULES; ++i) {
        if (g_modules[i].loaded) {
            offset += snprintf(out_buf + offset, max_len - offset,
                "%s %lld %lld - Live 0x0000000000000000\n",
                g_modules[i].name, (long long)g_modules[i].size, (long long)g_modules[i].ref_count);
            if (offset >= max_len - 128) break;
        }
    }
    return offset;
}

I64 PSTreeFormat(char *out_buf, I64 max_len) {
    if (!out_buf || max_len <= 0) return 0;
    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "init(1)───holysh(2)──┬──top(3)\n"
        "                     ├──cron(4)\n"
        "                     └──pstree(%lld)\n",
        (long long)g_current_pid);
    return offset;
}

U0 TaskInit() {
    MemSet(g_tasks, 0, sizeof(g_tasks));
    MemSet(g_jobs, 0, sizeof(g_jobs));
    MemSet(g_cron_entries, 0, sizeof(g_cron_entries));
    ModuleInit();
    g_kernel_start_time_ms = GetTimestampMs();
    g_system_ticks = 0;
    g_current_pid = 0;
    g_next_job_id = 1;
    g_next_cron_id = 1;

    /* PID 0: Kernel Swapper / Idle Task */
    CTask *idle = &g_tasks[0];
    idle->pid = 0;
    idle->ppid = 0;
    StrCpy(idle->comm, "[swapper]");
    idle->state = TASK_RUNNING;
    StrCpy(idle->cwd, "/");
    idle->uid = 0;
    idle->gid = 0;
    for (I64 f = 0; f < MAX_FDS; ++f) idle->fd_table[f] = -1;
    idle->fd_table[STDIN_FILENO]  = VFSOpen("/dev/tty", "/", O_RDONLY);
    idle->fd_table[STDOUT_FILENO] = VFSOpen("/dev/tty", "/", O_WRONLY);
    idle->fd_table[STDERR_FILENO] = VFSOpen("/dev/tty", "/", O_WRONLY);

    /* Register default cron job: sync uptime every 60 seconds */
    CronAdd(60, "echo '[cron] HolyNix kernel health check: OK' >> /tmp/cron.log");
}

#endif /* TASK_HC */
