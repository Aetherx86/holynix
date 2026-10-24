/*
 * HolyC Unix Kernel - System Call Interface (Syscall.HC)
 * Dispatches POSIX-compatible Unix syscalls to the HolyC kernel core.
 */

#ifndef SYSCALL_HC
#define SYSCALL_HC

#include "Types.HC"
#include "VFS.HC"
#include "Task.HC"

I64 SysRead(I64 fd, U8 *buf, I64 count) {
    CTask *t = TaskGetCurrent();
    if (!buf || count <= 0) return 0;
    if (t && fd >= 0 && fd < MAX_FDS) {
        I64 vfs_fd = t->fd_table[fd];
        if (vfs_fd >= 0) {
            return VFSRead(vfs_fd, buf, count);
        }
    }
    if (fd == STDIN_FILENO) {
        return TermRead(buf, count);
    }
    return -1;
}

I64 SysWrite(I64 fd, const U8 *buf, I64 count) {
    CTask *t = TaskGetCurrent();
    if (!buf || count <= 0) return 0;
    if (t && fd >= 0 && fd < MAX_FDS) {
        I64 vfs_fd = t->fd_table[fd];
        if (vfs_fd >= 0) {
            return VFSWrite(vfs_fd, buf, count);
        }
    }
    if (fd == STDOUT_FILENO || fd == STDERR_FILENO) {
        return TermWrite(buf, count);
    }
    return -1;
}

static I64 SysCheckAccess(CVFSInode *inode, I64 flags, I64 uid, I64 gid) {
    if (!inode) return -K_ENOENT;
    if (uid == 0) return 0; /* root has full bypass */

    I64 perm = inode->permissions;
    I64 req = 0;
    I64 acc = flags & 3;
    if (acc == O_RDONLY) req |= 4;
    else if (acc == O_WRONLY) req |= 2;
    else if (acc == O_RDWR) req |= 6;

    I64 bits = 0;
    if (uid == inode->uid) {
        bits = (perm >> 6) & 7;
    } else if (gid == inode->gid) {
        bits = (perm >> 3) & 7;
    } else {
        bits = perm & 7;
    }

    if ((bits & req) != req) {
        return -K_EACCES;
    }
    return 0;
}

I64 SysOpen(const U8 *path, I64 flags) {
    CTask *t = TaskGetCurrent();
    if (!t || !path) return -K_EINVAL;

    I64 inum = VFSResolvePath(path, t->cwd);
    if (inum >= 0) {
        CVFSInode *inode = VFSGetInode(inum);
        if (inode && inode->type == VFS_REGULAR) {
            I64 acc_err = SysCheckAccess(inode, flags, t->uid, t->gid);
            if (acc_err < 0) return acc_err;
        }
    }

    I64 pfd = -1;
    for (I64 i = 0; i < MAX_FDS; ++i) {
        if (t->fd_table[i] < 0) {
            pfd = i;
            break;
        }
    }
    if (pfd < 0) return -K_EMFILE;

    I64 vfs_fd = VFSOpen(path, t->cwd, flags);
    if (vfs_fd < 0) return vfs_fd;

    if (inum < 0) {
        CVFSInode *created_node = VFSGetInode(g_open_files[vfs_fd].inode_num);
        if (created_node) {
            created_node->uid = t->uid;
            created_node->gid = t->gid;
        }
    }

    t->fd_table[pfd] = vfs_fd;
    return pfd;
}

I64 SysClose(I64 fd) {
    CTask *t = TaskGetCurrent();
    if (!t || fd < 0 || fd >= MAX_FDS) return -K_EBADF;
    I64 vfs_fd = t->fd_table[fd];
    if (vfs_fd < 0) return -K_EBADF;

    VFSClose(vfs_fd);
    t->fd_table[fd] = -1;
    return 0;
}

I64 SysSeek(I64 fd, I64 offset, I64 whence) {
    CTask *t = TaskGetCurrent();
    if (!t || fd < 0 || fd >= MAX_FDS) return -K_EBADF;
    I64 vfs_fd = t->fd_table[fd];
    if (vfs_fd < 0) return -K_EBADF;
    return VFSSeek(vfs_fd, offset, whence);
}

I64 SysGetPid() {
    CTask *t = TaskGetCurrent();
    return t ? t->pid : 0;
}

I64 SysGetPPid() {
    CTask *t = TaskGetCurrent();
    return t ? t->ppid : 0;
}

I64 SysKill(I64 pid, I64 sig) {
    if (pid < 0 || pid >= MAX_TASKS) return -K_ESRCH;
    CTask *t = TaskGetByPid(pid);
    if (!t || t->state == TASK_UNUSED) return -K_ESRCH;
    if (sig == 0) return 0;
    return TaskKill(pid, sig);
}

I64 SysSleep(I64 ms) {
    if (ms <= 0) return 0;
    CTask *t = TaskGetCurrent();
    if (t) {
        t->state = TASK_SLEEPING;
        t->sleep_until_ms = GetTimestampMs() + ms;
    }
    SleepMs(ms);
    if (t && t->state == TASK_SLEEPING) {
        t->state = TASK_RUNNING;
    }
    return 0;
}

I64 SysTime() {
    return GetTimestampMs() / 1000;
}

I64 SysPipe(I64 *pipe_fds) {
    CTask *t = TaskGetCurrent();
    if (!t || !pipe_fds) return -1;

    I64 pfd0 = -1, pfd1 = -1;
    for (I64 i = 0; i < MAX_FDS; ++i) {
        if (t->fd_table[i] < 0) {
            if (pfd0 < 0) pfd0 = i;
            else if (pfd1 < 0) { pfd1 = i; break; }
        }
    }
    if (pfd0 < 0 || pfd1 < 0) return -1;

    I64 vfs_pipe[2];
    if (VFSPipe(vfs_pipe) < 0) return -1;

    t->fd_table[pfd0] = vfs_pipe[0];
    t->fd_table[pfd1] = vfs_pipe[1];
    pipe_fds[0] = pfd0;
    pipe_fds[1] = pfd1;
    return 0;
}

I64 SysMkdir(const U8 *path) {
    CTask *t = TaskGetCurrent();
    if (!t || !path) return -1;
    return VFSMkdir(path, t->cwd);
}

I64 SysUnlink(const U8 *path) {
    CTask *t = TaskGetCurrent();
    if (!t || !path) return -1;
    return VFSUnlink(path, t->cwd);
}

I64 SysChdir(const U8 *path) {
    CTask *t = TaskGetCurrent();
    if (!t || !path) return -1;

    I64 inum = VFSResolvePath(path, t->cwd);
    if (inum < 0) return -1;

    CVFSInode *inode = VFSGetInode(inum);
    if (!inode || inode->type != VFS_DIRECTORY) return -1;

    /* Build normalized path */
    if (path[0] == '/') {
        StrNCpy(t->cwd, path, MAX_PATH_LEN - 1);
    } else {
        if (StrCmp(path, "..") == 0) {
            char *last_slash = strrchr((char*)t->cwd, '/');
            if (last_slash && last_slash != (char*)t->cwd) {
                *last_slash = '\0';
            } else {
                StrCpy(t->cwd, "/");
            }
        } else if (StrCmp(path, ".") != 0) {
            if (StrCmp(t->cwd, "/") == 0) {
                snprintf((char*)t->cwd, MAX_PATH_LEN, "/%s", (const char*)path);
            } else {
                I64 cur_len = StrLen(t->cwd);
                snprintf((char*)t->cwd + cur_len, MAX_PATH_LEN - cur_len, "/%s", (const char*)path);
            }
        }
    }
    return 0;
}

I64 SysGetCwd(U8 *buf, I64 size) {
    CTask *t = TaskGetCurrent();
    if (!t || !buf || size <= 0) return -1;
    StrNCpy(buf, t->cwd, size - 1);
    return 0;
}

I64 SysDup2(I64 oldfd, I64 newfd) {
    CTask *t = TaskGetCurrent();
    if (!t || oldfd < 0 || oldfd >= MAX_FDS || newfd < 0 || newfd >= MAX_FDS) return -K_EBADF;
    if (t->fd_table[oldfd] < 0) return -K_EBADF;

    if (oldfd == newfd) return newfd;

    if (t->fd_table[newfd] >= 0) {
        SysClose(newfd);
    }

    t->fd_table[newfd] = t->fd_table[oldfd];
    g_open_files[t->fd_table[oldfd]].ref_count++;
    return newfd;
}

I64 SysChmod(const U8 *path, I64 mode) {
    CTask *t = TaskGetCurrent();
    if (!t || !path) return -K_EINVAL;
    return VFSChmod(path, t->cwd, mode);
}

I64 SysChown(const U8 *path, I64 uid, I64 gid) {
    CTask *t = TaskGetCurrent();
    if (!t || !path) return -K_EINVAL;
    return VFSChown(path, t->cwd, uid, gid);
}

I64 SysSymlink(const U8 *target, const U8 *linkpath) {
    CTask *t = TaskGetCurrent();
    if (!t || !target || !linkpath) return -K_EINVAL;
    return VFSSymlink(target, linkpath, t->cwd);
}

I64 SysReadlink(const U8 *path, U8 *buf, I64 bufsiz) {
    CTask *t = TaskGetCurrent();
    if (!t || !path || !buf) return -K_EINVAL;
    return VFSReadlink(path, t->cwd, buf, bufsiz);
}

I64 SysStat(const U8 *path, CKernelStat *st) {
    CTask *t = TaskGetCurrent();
    if (!t || !path || !st) return -K_EINVAL;
    return VFSStat(path, t->cwd, st, TRUE);
}

I64 SysLStat(const U8 *path, CKernelStat *st) {
    CTask *t = TaskGetCurrent();
    if (!t || !path || !st) return -K_EINVAL;
    return VFSStat(path, t->cwd, st, FALSE);
}

I64 Syscall(I64 sys_num, I64 a1, I64 a2, I64 a3, I64 a4) {
    (U0)a4;
    switch (sys_num) {
        case SYS_EXIT:       TaskExit(a1); return 0;
        case SYS_READ:       return SysRead(a1, (U8*)a2, a3);
        case SYS_WRITE:      return SysWrite(a1, (const U8*)a2, a3);
        case SYS_OPEN:       return SysOpen((const U8*)a1, a2);
        case SYS_CLOSE:      return SysClose(a1);
        case SYS_WAITPID:    return TaskWaitPid(a1, (I64*)a2);
        case SYS_KILL:       return TaskKill(a1, a2);
        case SYS_GETPID:     return SysGetPid();
        case SYS_GETPPID:    return SysGetPPid();
        case SYS_SLEEP:      return SysSleep(a1);
        case SYS_TIME:       return SysTime();
        case SYS_PIPE:       return SysPipe((I64*)a1);
        case SYS_SEEK:       return SysSeek(a1, a2, a3);
        case SYS_MKDIR:      return SysMkdir((const U8*)a1);
        case SYS_UNLINK:     return SysUnlink((const U8*)a1);
        case SYS_CHDIR:      return SysChdir((const U8*)a1);
        case SYS_GETCWD:     return SysGetCwd((U8*)a1, a2);
        case SYS_DUP2:       return SysDup2(a1, a2);
        case SYS_CHMOD:      return SysChmod((const U8*)a1, a2);
        case SYS_CHOWN:      return SysChown((const U8*)a1, a2, a3);
        case SYS_SYMLINK:    return SysSymlink((const U8*)a1, (const U8*)a2);
        case SYS_READLINK:   return SysReadlink((const U8*)a1, (U8*)a2, a3);
        case SYS_STAT_INODE: return SysStat((const U8*)a1, (CKernelStat*)a2);
        case SYS_YIELD:      TaskYield(); return 0;
        default:
            return -1;
    }
}

#endif /* SYSCALL_HC */
