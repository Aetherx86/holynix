/*
 * HolyC Unix Kernel - Virtual File System (VFS.HC)
 * Inode table, hierarchical path resolution, device nodes, pipes, and file operations.
 */

#ifndef VFS_HC
#define VFS_HC

#include "Types.HC"
#include "RingBuffer.HC"

class CVFSInode {
    I64 inode_num;
    U8 name[64];
    I64 type;             /* VFS_REGULAR, VFS_DIRECTORY, VFS_CHARDEV, VFS_PIPE, VFS_PROC, VFS_SYMLINK */
    I64 size;
    I64 capacity;
    U8 *data;
    I64 parent_inode;
    I64 children[MAX_CHILDREN];
    I64 num_children;
    DeviceReadFn read_fn;
    DeviceWriteFn write_fn;
    I64 permissions;
    I64 uid;
    I64 gid;
    I64 atime;
    I64 mtime;
    I64 ctime;
    U8 symlink_target[MAX_PATH_LEN];
};

class CFileDesc {
    I64 inode_num;
    I64 offset;
    I64 flags;
    I64 ref_count;
    CRingBuffer *pipe_rb;
    Bool is_pipe;
    Bool pipe_read_end;
};

static CVFSInode g_inodes[MAX_INODES];
static I64 g_inode_count = 0;

static CFileDesc g_open_files[MAX_OPEN_FILES];

I64 VFSAllocInode(const U8 *name, I64 type, I64 parent_num) {
    if (g_inode_count >= MAX_INODES) {
        return -1;
    }
    I64 inum = g_inode_count++;
    CVFSInode *node = &g_inodes[inum];
    MemSet(node, 0, sizeof(CVFSInode));
    node->inode_num = inum;
    StrNCpy(node->name, name, 63);
    node->type = type;
    node->parent_inode = parent_num;
    node->permissions = (type == VFS_DIRECTORY) ? 0755 : 0644;
    node->uid = 0;
    node->gid = 0;
    I64 now_sec = GetTimestampMs() / 1000;
    node->atime = now_sec;
    node->mtime = now_sec;
    node->ctime = now_sec;
    node->symlink_target[0] = '\0';
    node->size = 0;
    node->capacity = 0;
    node->data = NULL;
    node->num_children = 0;
    node->read_fn = NULL;
    node->write_fn = NULL;

    if (parent_num >= 0 && parent_num < g_inode_count) {
        CVFSInode *parent = &g_inodes[parent_num];
        if (parent->num_children < MAX_CHILDREN) {
            parent->children[parent->num_children++] = inum;
        }
    }
    return inum;
}

CVFSInode *VFSGetInode(I64 inum) {
    if (inum < 0 || inum >= g_inode_count) return NULL;
    return &g_inodes[inum];
}

I64 VFSFindChild(CVFSInode *parent, const U8 *name) {
    if (!parent || parent->type != VFS_DIRECTORY) return -1;
    if (StrCmp(name, ".") == 0) return parent->inode_num;
    if (StrCmp(name, "..") == 0) return parent->parent_inode;

    for (I64 i = 0; i < parent->num_children; ++i) {
        I64 cinum = parent->children[i];
        if (cinum >= 0 && cinum < g_inode_count) {
            if (StrCmp(g_inodes[cinum].name, name) == 0) {
                return cinum;
            }
        }
    }
    return -1;
}

I64 VFSResolvePathEx(const U8 *path, const U8 *cwd, Bool follow_symlink) {
    if (!path || path[0] == '\0') return -1;

    I64 curr_inum = 0; /* root inode is 0 */
    U8 full_path[MAX_PATH_LEN];

    if (path[0] == '/') {
        StrNCpy(full_path, path, MAX_PATH_LEN - 1);
    } else {
        if (!cwd || cwd[0] == '\0' || cwd[0] != '/') {
            cwd = "/";
        }
        if (StrCmp(cwd, "/") == 0) {
            snprintf((char*)full_path, MAX_PATH_LEN, "/%s", (const char*)path);
        } else {
            snprintf((char*)full_path, MAX_PATH_LEN, "%s/%s", (const char*)cwd, (const char*)path);
        }
    }

    /* Tokenize path components */
    U8 token_buf[MAX_PATH_LEN];
    StrNCpy(token_buf, full_path, MAX_PATH_LEN - 1);

    char *saveptr = NULL;
    char *part = strtok_r((char*)token_buf, "/", &saveptr);
    while (part != NULL) {
        if (strlen(part) > 0) {
            CVFSInode *curr_node = VFSGetInode(curr_inum);
            if (!curr_node) return -1;
            I64 next_inum = VFSFindChild(curr_node, (const U8*)part);
            if (next_inum < 0) {
                return -1; /* Not found */
            }

            char *next_part = strtok_r(NULL, "/", &saveptr);
            CVFSInode *next_node = VFSGetInode(next_inum);
            if (next_node && next_node->type == VFS_SYMLINK) {
                if (next_part != NULL || follow_symlink) {
                    I64 resolved_link = VFSResolvePathEx((const U8*)next_node->symlink_target, "/", TRUE);
                    if (resolved_link < 0) return -1;
                    curr_inum = resolved_link;
                    part = next_part;
                    continue;
                }
            }

            curr_inum = next_inum;
            part = next_part;
        } else {
            part = strtok_r(NULL, "/", &saveptr);
        }
    }
    return curr_inum;
}

I64 VFSResolvePath(const U8 *path, const U8 *cwd) {
    return VFSResolvePathEx(path, cwd, TRUE);
}

I64 VFSMkdir(const U8 *path, const U8 *cwd) {
    if (!path || path[0] == '\0') return -1;

    /* Check if directory already exists */
    if (VFSResolvePath(path, cwd) >= 0) {
        return -1; /* EEXIST */
    }

    U8 full_path[MAX_PATH_LEN];
    if (path[0] == '/') {
        StrNCpy(full_path, path, MAX_PATH_LEN - 1);
    } else {
        if (!cwd || cwd[0] == '\0') cwd = "/";
        if (StrCmp(cwd, "/") == 0) {
            snprintf((char*)full_path, MAX_PATH_LEN, "/%s", (const char*)path);
        } else {
            snprintf((char*)full_path, MAX_PATH_LEN, "%s/%s", (const char*)cwd, (const char*)path);
        }
    }

    /* Find last '/' to separate dirname and basename */
    char *last_slash = strrchr((char*)full_path, '/');
    if (!last_slash) return -1;

    *last_slash = '\0';
    const char *parent_path = (full_path[0] == '\0') ? "/" : (char*)full_path;
    const char *dir_name = last_slash + 1;

    if (strlen(dir_name) == 0) return -1;

    I64 parent_inum = VFSResolvePath((const U8*)parent_path, "/");
    if (parent_inum < 0) return -1;

    CVFSInode *parent = VFSGetInode(parent_inum);
    if (!parent || parent->type != VFS_DIRECTORY) return -1;

    return VFSAllocInode((const U8*)dir_name, VFS_DIRECTORY, parent_inum);
}

I64 VFSCreateFile(const U8 *path, const U8 *cwd, const U8 *content, I64 len) {
    U8 full_path[MAX_PATH_LEN];
    if (path[0] == '/') {
        StrNCpy(full_path, path, MAX_PATH_LEN - 1);
    } else {
        if (!cwd || cwd[0] == '\0') cwd = "/";
        if (StrCmp(cwd, "/") == 0) {
            snprintf((char*)full_path, MAX_PATH_LEN, "/%s", (const char*)path);
        } else {
            snprintf((char*)full_path, MAX_PATH_LEN, "%s/%s", (const char*)cwd, (const char*)path);
        }
    }

    I64 existing_inum = VFSResolvePath(full_path, "/");
    if (existing_inum >= 0) {
        CVFSInode *inode = VFSGetInode(existing_inum);
        if (inode->type != VFS_REGULAR) return -1;
        if (inode->data) Free(inode->data);
        inode->size = len;
        inode->capacity = len + 1;
        inode->data = (U8*)MAlloc(inode->capacity);
        if (content && len > 0) {
            MemCpy(inode->data, content, len);
        }
        inode->data[len] = '\0';
        inode->mtime = GetTimestampMs() / 1000;
        return existing_inum;
    }

    char *last_slash = strrchr((char*)full_path, '/');
    if (!last_slash) return -1;

    *last_slash = '\0';
    const char *parent_path = (full_path[0] == '\0') ? "/" : (char*)full_path;
    const char *file_name = last_slash + 1;

    I64 parent_inum = VFSResolvePath((const U8*)parent_path, "/");
    if (parent_inum < 0) return -1;

    I64 inum = VFSAllocInode((const U8*)file_name, VFS_REGULAR, parent_inum);
    if (inum < 0) return -1;

    CVFSInode *inode = VFSGetInode(inum);
    inode->size = len;
    inode->capacity = (len > 0) ? (len + 1) : 64;
    inode->data = (U8*)MAlloc(inode->capacity);
    if (content && len > 0) {
        MemCpy(inode->data, content, len);
    }
    inode->data[len] = '\0';
    return inum;
}

I64 VFSAllocFileDesc() {
    for (I64 i = 0; i < MAX_OPEN_FILES; ++i) {
        if (g_open_files[i].ref_count == 0) {
            MemSet(&g_open_files[i], 0, sizeof(CFileDesc));
            g_open_files[i].ref_count = 1;
            return i;
        }
    }
    return -1;
}

I64 VFSOpen(const U8 *path, const U8 *cwd, I64 flags) {
    I64 inum = VFSResolvePath(path, cwd);
    if (inum >= 0) {
        if ((flags & O_CREAT) && (flags & O_EXCL)) {
            return -K_EEXIST;
        }
    } else {
        if (flags & O_CREAT) {
            inum = VFSCreateFile(path, cwd, NULL, 0);
            if (inum < 0) return -K_ENFILE;
        } else {
            return -K_ENOENT;
        }
    }

    CVFSInode *inode = VFSGetInode(inum);
    if (!inode) return -K_ENOENT;

    if ((flags & O_TRUNC) && inode->type == VFS_REGULAR) {
        if (inode->data) Free(inode->data);
        inode->size = 0;
        inode->capacity = 64;
        inode->data = (U8*)MAlloc(inode->capacity);
        inode->data[0] = '\0';
    }

    I64 fd = VFSAllocFileDesc();
    if (fd < 0) return -K_ENFILE;

    g_open_files[fd].inode_num = inum;
    g_open_files[fd].flags = flags;
    g_open_files[fd].offset = (flags & O_APPEND) ? inode->size : 0;
    g_open_files[fd].is_pipe = FALSE;
    g_open_files[fd].pipe_rb = NULL;
    return fd;
}

U0 VFSClose(I64 fd) {
    if (fd < 0 || fd >= MAX_OPEN_FILES) return;
    if (g_open_files[fd].ref_count > 0) {
        g_open_files[fd].ref_count--;
        if (g_open_files[fd].ref_count == 0) {
            if (g_open_files[fd].is_pipe && g_open_files[fd].pipe_rb) {
                g_open_files[fd].pipe_rb->ref_count--;
                if (g_open_files[fd].pipe_rb->ref_count <= 0) {
                    RingBufFree(g_open_files[fd].pipe_rb);
                }
                g_open_files[fd].pipe_rb = NULL;
            }
        }
    }
}

I64 VFSRead(I64 fd, U8 *buf, I64 count) {
    if (fd < 0 || fd >= MAX_OPEN_FILES || !buf || count <= 0) return -1;
    CFileDesc *desc = &g_open_files[fd];
    if (desc->ref_count <= 0) return -1;

    if (desc->is_pipe) {
        if (!desc->pipe_rb) return 0;
        return RingBufRead(desc->pipe_rb, buf, count);
    }

    CVFSInode *inode = VFSGetInode(desc->inode_num);
    if (!inode) return -1;

    /* Custom read handler for chardev & proc */
    if (inode->read_fn) {
        I64 n = inode->read_fn(inode, buf, count, desc->offset);
        if (n > 0) desc->offset += n;
        return n;
    }

    if (inode->type == VFS_DIRECTORY) {
        return -1; /* Use getdents or readdir */
    }

    if (desc->offset >= inode->size) return 0; /* EOF */

    I64 avail = inode->size - desc->offset;
    I64 to_read = Min(avail, count);
    MemCpy(buf, inode->data + desc->offset, to_read);
    desc->offset += to_read;
    return to_read;
}

I64 VFSWrite(I64 fd, const U8 *buf, I64 count) {
    if (fd < 0 || fd >= MAX_OPEN_FILES || !buf || count <= 0) return -K_EBADF;
    CFileDesc *desc = &g_open_files[fd];
    if (desc->ref_count <= 0) return -K_EBADF;

    if (desc->is_pipe) {
        if (!desc->pipe_rb) return -K_EPIPE;
        if (desc->pipe_rb->ref_count < 2) {
            /* Read end was closed: broken pipe! */
            return -K_EPIPE;
        }
        return RingBufWrite(desc->pipe_rb, buf, count);
    }

    CVFSInode *inode = VFSGetInode(desc->inode_num);
    if (!inode) return -K_EBADF;

    /* Custom write handler for chardev */
    if (inode->write_fn) {
        I64 n = inode->write_fn(inode, buf, count, desc->offset);
        if (n > 0) desc->offset += n;
        return n;
    }

    if (inode->type != VFS_REGULAR) return -K_EINVAL;

    I64 req_cap = desc->offset + count + 1;
    if (req_cap > inode->capacity) {
        I64 new_cap = (req_cap * 3) / 2 + 64;
        U8 *new_data = (U8*)MAlloc(new_cap);
        if (inode->data && inode->size > 0) {
            MemCpy(new_data, inode->data, inode->size);
            Free(inode->data);
        }
        inode->data = new_data;
        inode->capacity = new_cap;
    }

    /* Zero-fill any sparse gap created by lseek past EOF */
    if (desc->offset > inode->size && inode->data) {
        MemSet(inode->data + inode->size, 0, desc->offset - inode->size);
    }

    MemCpy(inode->data + desc->offset, buf, count);
    desc->offset += count;
    if (desc->offset > inode->size) {
        inode->size = desc->offset;
        inode->data[inode->size] = '\0';
    }
    inode->mtime = GetTimestampMs() / 1000;
    return count;
}

I64 VFSSeek(I64 fd, I64 offset, I64 whence) {
    if (fd < 0 || fd >= MAX_OPEN_FILES) return -K_EBADF;
    CFileDesc *desc = &g_open_files[fd];
    if (desc->ref_count <= 0) return -K_EBADF;
    if (desc->is_pipe) return -K_ESPIPE;

    CVFSInode *inode = VFSGetInode(desc->inode_num);
    if (!inode) return -K_EBADF;

    I64 new_off = desc->offset;
    if (whence == VFS_SEEK_SET) {
        new_off = offset;
    } else if (whence == VFS_SEEK_CUR) {
        new_off += offset;
    } else if (whence == VFS_SEEK_END) {
        new_off = inode->size + offset;
    } else {
        return -K_EINVAL;
    }

    if (new_off < 0) return -K_EINVAL;
    desc->offset = new_off;
    return new_off;
}

I64 VFSUnlink(const U8 *path, const U8 *cwd) {
    I64 inum = VFSResolvePath(path, cwd);
    if (inum < 0) return -K_ENOENT;
    if (inum == 0) return -K_EPERM;

    CVFSInode *node = VFSGetInode(inum);
    if (!node) return -K_ENOENT;
    if (node->type == VFS_DIRECTORY) return -K_EISDIR;

    CVFSInode *parent = VFSGetInode(node->parent_inode);
    if (!parent) return -K_ENOENT;

    /* Remove from parent's children array */
    for (I64 i = 0; i < parent->num_children; ++i) {
        if (parent->children[i] == inum) {
            for (I64 j = i; j < parent->num_children - 1; ++j) {
                parent->children[j] = parent->children[j + 1];
            }
            parent->num_children--;
            break;
        }
    }

    if (node->data) {
        Free(node->data);
        node->data = NULL;
    }
    node->size = 0;
    node->name[0] = '\0';
    return 0;
}

I64 VFSPipe(I64 *pipe_fds) {
    if (!pipe_fds) return -1;

    I64 r_fd = VFSAllocFileDesc();
    if (r_fd < 0) return -1;

    I64 w_fd = VFSAllocFileDesc();
    if (w_fd < 0) {
        VFSClose(r_fd);
        return -1;
    }

    CRingBuffer *rb = RingBufCreate(PIPE_BUFFER_SIZE);
    rb->ref_count = 2;

    g_open_files[r_fd].is_pipe = TRUE;
    g_open_files[r_fd].pipe_rb = rb;
    g_open_files[r_fd].pipe_read_end = TRUE;
    g_open_files[r_fd].flags = O_RDONLY;

    g_open_files[w_fd].is_pipe = TRUE;
    g_open_files[w_fd].pipe_rb = rb;
    g_open_files[w_fd].pipe_read_end = FALSE;
    g_open_files[w_fd].flags = O_WRONLY;

    pipe_fds[0] = r_fd;
    pipe_fds[1] = w_fd;
    return 0;
}

I64 VFSSymlink(const U8 *target, const U8 *linkpath, const U8 *cwd) {
    if (!target || !linkpath || linkpath[0] == '\0') return -K_EINVAL;

    if (VFSResolvePathEx(linkpath, cwd, FALSE) >= 0) {
        return -K_EEXIST;
    }

    U8 full_path[MAX_PATH_LEN];
    if (linkpath[0] == '/') {
        StrNCpy(full_path, linkpath, MAX_PATH_LEN - 1);
    } else {
        if (!cwd || cwd[0] == '\0') cwd = "/";
        if (StrCmp(cwd, "/") == 0) {
            snprintf((char*)full_path, MAX_PATH_LEN, "/%s", (const char*)linkpath);
        } else {
            snprintf((char*)full_path, MAX_PATH_LEN, "%s/%s", (const char*)cwd, (const char*)linkpath);
        }
    }

    char *last_slash = strrchr((char*)full_path, '/');
    if (!last_slash) return -K_ENOENT;

    *last_slash = '\0';
    const char *parent_path = (full_path[0] == '\0') ? "/" : (char*)full_path;
    const char *link_name = last_slash + 1;

    I64 parent_inum = VFSResolvePath((const U8*)parent_path, "/");
    if (parent_inum < 0) return -K_ENOENT;

    I64 inum = VFSAllocInode((const U8*)link_name, VFS_SYMLINK, parent_inum);
    if (inum < 0) return -K_ENFILE;

    CVFSInode *node = VFSGetInode(inum);
    StrNCpy(node->symlink_target, target, MAX_PATH_LEN - 1);
    node->size = StrLen(target);
    node->permissions = 0777;
    return 0;
}

I64 VFSReadlink(const U8 *path, const U8 *cwd, U8 *buf, I64 bufsiz) {
    if (!path || !buf || bufsiz <= 0) return -K_EINVAL;
    I64 inum = VFSResolvePathEx(path, cwd, FALSE);
    if (inum < 0) return -K_ENOENT;

    CVFSInode *node = VFSGetInode(inum);
    if (!node || node->type != VFS_SYMLINK) return -K_EINVAL;

    I64 len = StrLen(node->symlink_target);
    I64 to_copy = Min(len, bufsiz - 1);
    MemCpy(buf, node->symlink_target, to_copy);
    buf[to_copy] = '\0';
    return to_copy;
}

I64 VFSChmod(const U8 *path, const U8 *cwd, I64 mode) {
    I64 inum = VFSResolvePath(path, cwd);
    if (inum < 0) return -K_ENOENT;
    CVFSInode *node = VFSGetInode(inum);
    if (!node) return -K_ENOENT;
    node->permissions = mode & 07777;
    node->ctime = GetTimestampMs() / 1000;
    return 0;
}

I64 VFSChown(const U8 *path, const U8 *cwd, I64 uid, I64 gid) {
    I64 inum = VFSResolvePath(path, cwd);
    if (inum < 0) return -K_ENOENT;
    CVFSInode *node = VFSGetInode(inum);
    if (!node) return -K_ENOENT;
    if (uid >= 0) node->uid = uid;
    if (gid >= 0) node->gid = gid;
    node->ctime = GetTimestampMs() / 1000;
    return 0;
}

I64 VFSStat(const U8 *path, const U8 *cwd, CKernelStat *st, Bool follow_symlink) {
    if (!path || !st) return -K_EINVAL;
    I64 inum = VFSResolvePathEx(path, cwd, follow_symlink);
    if (inum < 0) return -K_ENOENT;

    CVFSInode *node = VFSGetInode(inum);
    if (!node) return -K_ENOENT;

    MemSet(st, 0, sizeof(CKernelStat));
    st->st_dev = 1;
    st->st_ino = node->inode_num;
    st->st_mode = node->permissions;
    if (node->type == VFS_DIRECTORY) st->st_mode |= 0040000;
    else if (node->type == VFS_SYMLINK) st->st_mode |= 0120000;
    else if (node->type == VFS_CHARDEV) st->st_mode |= 0020000;
    else if (node->type == VFS_PIPE) st->st_mode |= 0010000;
    else st->st_mode |= 0100000;

    st->st_nlink = (node->type == VFS_DIRECTORY) ? (2 + node->num_children) : 1;
    st->st_uid = node->uid;
    st->st_gid = node->gid;
    st->st_size = node->size;
    st->st_atime = node->atime;
    st->st_mtime = node->mtime;
    st->st_ctime = node->ctime;
    return 0;
}

I64 VFSCountFiles(I64 *out_total_bytes, I64 *out_total_lines) {
    I64 count = 0;
    I64 bytes = 0;
    I64 lines = 0;
    for (I64 i = 0; i < g_inode_count; ++i) {
        if (g_inodes[i].type == VFS_REGULAR) {
            count++;
            bytes += g_inodes[i].size;
            if (g_inodes[i].data) {
                for (I64 j = 0; j < g_inodes[i].size; ++j) {
                    if (g_inodes[i].data[j] == '\n') lines++;
                }
            }
        }
    }
    if (out_total_bytes) *out_total_bytes = bytes;
    if (out_total_lines) *out_total_lines = lines;
    return count;
}

U0 VFSInit() {
    g_inode_count = 0;
    MemSet(g_inodes, 0, sizeof(g_inodes));
    MemSet(g_open_files, 0, sizeof(g_open_files));

    /* Inode 0: Root Directory "/" */
    I64 root = VFSAllocInode("/", VFS_DIRECTORY, 0);
    g_inodes[root].parent_inode = 0;

    /* Create Standard Unix Directory Hierarchy */
    VFSMkdir("bin", "/");
    VFSMkdir("dev", "/");
    VFSMkdir("etc", "/");
    VFSMkdir("proc", "/");
    VFSMkdir("home", "/");
    VFSMkdir("home/terry", "/");
    VFSMkdir("home/god", "/");
    VFSMkdir("tmp", "/");
    VFSMkdir("var", "/");
}

#endif /* VFS_HC */
