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

U0 TaskInit() {
    MemSet(g_tasks, 0, sizeof(g_tasks));
    g_kernel_start_time_ms = GetTimestampMs();
    g_system_ticks = 0;
    g_current_pid = 0;

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
}

#endif /* TASK_HC */
