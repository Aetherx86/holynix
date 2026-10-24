/*
 * HolyC Unix Kernel - Core Types and Constants (Types.HC)
 * "Simplicity is the ultimate sophistication." - Terry A. Davis
 */

#ifndef TYPES_HC
#define TYPES_HC

/* System Limits */
#define MAX_TASKS          64
#define MAX_FDS            32
#define MAX_PATH_LEN       256
#define MAX_INODES         256
#define MAX_OPEN_FILES     128
#define PIPE_BUFFER_SIZE   4096
#define DMESG_BUFFER_SIZE  8192
#define MAX_CHILDREN       32

/* Task / Process States */
#define TASK_UNUSED        0
#define TASK_READY         1
#define TASK_RUNNING       2
#define TASK_SLEEPING      3
#define TASK_ZOMBIE        4
#define TASK_STOPPED       5

/* File System Node Types */
#define VFS_REGULAR        1
#define VFS_DIRECTORY      2
#define VFS_CHARDEV        3
#define VFS_PIPE           4
#define VFS_PROC           5
#define VFS_SYMLINK        6

/* File Open Flags */
#ifndef O_RDONLY
#define O_RDONLY           0x0000
#endif
#ifndef O_WRONLY
#define O_WRONLY           0x0001
#endif
#ifndef O_RDWR
#define O_RDWR             0x0002
#endif
#ifndef O_CREAT
#define O_CREAT            0x0100
#endif
#ifndef O_TRUNC
#define O_TRUNC            0x0200
#endif
#ifndef O_APPEND
#define O_APPEND           0x0400
#endif
#ifndef O_EXCL
#define O_EXCL             0x0800
#endif

/* Linux / POSIX Errno Constants */
#define K_EPERM            1
#define K_ENOENT           2
#define K_ESRCH            3
#define K_EINTR            4
#define K_EIO              5
#define K_EBADF            9
#define K_ECHILD           10
#define K_EACCES           13
#define K_EEXIST           17
#define K_ENODEV           19
#define K_ENOTDIR          20
#define K_EISDIR           21
#define K_EINVAL           22
#define K_ENFILE           23
#define K_EMFILE           24
#define K_ESPIPE           29
#define K_EPIPE            32

/* Seek Whence */
#define VFS_SEEK_SET       0
#define VFS_SEEK_CUR       1
#define VFS_SEEK_END       2

/* Standard Signals */
#define SIGHUP             1
#define SIGINT             2
#define SIGQUIT            3
#define SIGKILL            9
#define SIGSEGV            11
#define SIGPIPE            13
#define SIGALRM            14
#define SIGTERM            15

/* Unix System Call Numbers */
#define SYS_EXIT           1
#define SYS_FORK           2
#define SYS_READ           3
#define SYS_WRITE          4
#define SYS_OPEN           5
#define SYS_CLOSE          6
#define SYS_WAITPID        7
#define SYS_KILL           8
#define SYS_GETPID         9
#define SYS_GETPPID        10
#define SYS_SLEEP          11
#define SYS_TIME           12
#define SYS_PIPE           13
#define SYS_SEEK           14
#define SYS_STAT           15
#define SYS_MKDIR          16
#define SYS_UNLINK         17
#define SYS_CHDIR          18
#define SYS_GETCWD         19
#define SYS_DUP2           20
#define SYS_YIELD          21
#define SYS_CHMOD          22
#define SYS_CHOWN          23
#define SYS_SYMLINK        24
#define SYS_READLINK       25
#define SYS_STAT_INODE     26

/* Standard File Descriptors */
#define STDIN_FILENO       0
#define STDOUT_FILENO      1
#define STDERR_FILENO      2

/* Kernel Stat Structure */
class CKernelStat {
    I64 st_dev;
    I64 st_ino;
    I64 st_mode;
    I64 st_nlink;
    I64 st_uid;
    I64 st_gid;
    I64 st_rdev;
    I64 st_size;
    I64 st_atime;
    I64 st_mtime;
    I64 st_ctime;
};

/* Forward Declarations of Kernel Structures */
class CVFSInode;
class CFileDesc;
class CTask;
class CRingBuffer;

/* Function pointer types */
typedef I64 (*DeviceReadFn)(CVFSInode *inode, U8 *buf, I64 count, I64 offset);
typedef I64 (*DeviceWriteFn)(CVFSInode *inode, const U8 *buf, I64 count, I64 offset);
typedef I64 (*TaskEntryFn)(U0 *arg);

#endif /* TYPES_HC */
