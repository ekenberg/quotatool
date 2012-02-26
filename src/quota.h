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

/* FIXME: this is getting to be a mess */
#if HAVE_LINUX_FS_H
#  include <linux/version.h>
#  if LINUX_VERSION_CODE >= KERNEL_VERSION(2,4,0)
#    define BLOCK_SIZE 1024
#  else
#    include <linux/fs.h>		
#  endif
#elif HAVE_STD_H
#  include <std.h>
#  define BLOCK_SIZE MULBSIZE
#else
/*#  warn "making up a block size" */
/* FIXME: "warn" directive does not work with gcc 2.8.1 on aix -cagri*/
#  define BLOCK_SIZE 1024
#endif

#if PLATFORM_LINUX
#  include <linux/types.h>
#  include "linux/linux_quota.h"
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
#else
#  error "no quota headers found"
#endif

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
   void *  _v2_quotainfo;
   void *  _generic_quotainfo;
};

#define GRACE_BLOCK 1
#define GRACE_INODE 2

typedef struct _quota_t quota_t;

quota_t *   quota_new      (int q_type, int id, char *device);
void        quota_delete   (quota_t *myquota);

int         quota_get      (quota_t *myquota);
int         quota_set      (quota_t *myquota);

int         xfs_reset_grace(quota_t *myquota, int grace_type);


#endif /* INCLUDE_QUOTATOOL_QUOTA */


