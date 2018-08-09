/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * quota.h
 * middle layer to talk to quotactl
 */
#ifndef INCLUDE_QUOTATOOL_QUOTA
#define INCLUDE_QUOTATOOL_QUOTA

#include "quotatool.h"
#include <config.h>

/* Find out the system BLOCK_SIZE */
#if HAVE_LINUX_FS_H
#  include <linux/version.h>
#  if LINUX_VERSION_CODE >= KERNEL_VERSION(2,4,0)
#    define BLOCK_SIZE 1024
#  else
#    include <linux/fs.h>
#  endif
#elif PLATFORM_DARWIN /* Macos does the right thing - count bytes instead of silly blocks! */
#  define BLOCK_SIZE 1
#elif HAVE_STD_H
#  include <std.h>
#  define BLOCK_SIZE MULBSIZE
#elif HAVE_UFS_UFS_QUOTA_H || HAVE_UFS_UFS_QUOTA1_H
#  define BLOCK_SIZE 512
#else
/* WARNING: Making up a block-size */
#  define BLOCK_SIZE 1024
#endif

/* Include system quota headers */
#if PLATFORM_LINUX
#  include <linux/types.h>
#  include "linux/linux_quota.h"
#  define QUOTA_USER  USRQUOTA + 1
#  define QUOTA_GROUP GRPQUOTA + 1
#elif PLATFORM_DARWIN
#  include <sys/types.h>
#  include <sys/quota.h>
#  define QUOTA_USER  USRQUOTA + 1
#  define QUOTA_GROUP GRPQUOTA + 1
#elif HAVE_SYS_FS_UFS_QUOTA_H
#  include <sys/types.h>
#  include <sys/fs/ufs_quota.h>
#  define QUOTA_USER 1
#  define QUOTA_GROUP 2
#elif HAVE_JFS_QUOTA_H
#  include <sys/types.h>
#  include <jfs/quota.h>
#  define QUOTA_USER  USRQUOTA + 1
#  define QUOTA_GROUP GRPQUOTA + 1
#elif HAVE_UFS_UFS_QUOTA_H /* FreeBSD || OpenBSD */
#  include <sys/types.h>
#  include <ufs/ufs/quota.h>
#  define QUOTA_USER  USRQUOTA + 1
#  define QUOTA_GROUP GRPQUOTA + 1
#elif HAVE_UFS_UFS_QUOTA1_H /* NetBSD */
#  include <sys/types.h>
#  include <ufs/ufs/quota1.h>
#  define QUOTA_USER  USRQUOTA + 1
#  define QUOTA_GROUP GRPQUOTA + 1
#else
#  error "no quota headers found"
#endif


// Upwards integer division, always make room for remainder
#define DIV_UP(a, b) ( (a) % (b) == 0 ? (a) / (b) : ((a) / (b) + 1))

// Convert bytes to system blocks
#define BYTES_TO_BLOCKS(bytes) DIV_UP(bytes, BLOCK_SIZE)

// Convert from system block-size to Kb. The constant 8 allows for BLOCK_SIZE >= 1024 / 8 (= 128 bytes)
#define BLOCKS_TO_KB(num_blocks) ((BLOCK_SIZE == 1) ? DIV_UP(num_blocks, 1024) : DIV_UP((num_blocks) * ((BLOCK_SIZE * 8) / 1024), 8))

struct _quota_t {
   u_int64_t	block_hard;
   u_int64_t	block_soft;
   u_int64_t	diskspace_used;
   u_int64_t	inode_hard;
   u_int64_t	inode_soft;
   u_int64_t	inode_used;
   time_t  block_time;
   time_t  inode_time;
   time_t  block_grace;
   time_t  inode_grace;
   int     _id;
   int     _id_type;
   char *  _qfile;
   int     _do_set_global_block_gracetime;
   int     _do_set_global_inode_gracetime;
   void *  _v0_quotainfo;
   void *  _generic_quotainfo;
};

#define GRACE_BLOCK 1
#define GRACE_INODE 2

typedef struct _quota_t quota_t;

quota_t *   quota_new      (int q_type, int id, char *device);
void        quota_delete   (quota_t *myquota);

int         quota_get      (quota_t *myquota);
int         quota_set      (quota_t *myquota);

int         quota_reset_grace(quota_t *myquota, int grace_type);


#endif /* INCLUDE_QUOTATOOL_QUOTA */
