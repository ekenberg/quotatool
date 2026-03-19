/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * quota.c
 * middle layer to talk to quotactl
 */

#include <config.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "output.h"
#include "system.h"
#include "quota.h"
#include "quotatool.h"

#define Q_USER_FILENAME  "/quota.user"
#define Q_GROUP_FILENAME "/quota.group"

quota_t *quota_new (int q_type, int id, char *fs_spec)
{
  quota_t *myquota;
  fs_t *fs;
  char *qfile;
  char *qfile_alloc; /* preserve original malloc pointer for free() */
  char *q_filename;

  if (q_type > MAXQUOTAS) {
    output_error ("Unknown quota type: %d", q_type);
    return 0;
  }

  if (q_type == QUOTA_USER) q_filename = Q_USER_FILENAME;
  else q_filename = Q_GROUP_FILENAME;

  --q_type;                    /* see defs in quota.h */

  myquota = (quota_t *) malloc (sizeof(quota_t));
  if (! myquota) {
    output_error ("Insufficient memory");
    exit (ERR_MEM);
  }

  fs = system_getfs (fs_spec);
  if ( ! fs ) {
    free (myquota);
    return NULL;
  }

  qfile = malloc (strlen(fs->mount_pt) + strlen(q_filename) + 1);
  if (! qfile) {
    output_error ("Insufficient memory");
    free (myquota);
    free (fs);
    exit (ERR_MEM);
  }
  qfile_alloc = qfile; /* save original pointer for free() */

#if HAVE_STRLCPY
  strlcpy(qfile, fs->mount_pt, strlen(fs->mount_pt) + 1);
#else
  strcpy (qfile, fs->mount_pt);
#endif /* HAVE_STRLCPY */

#if HAVE_STRLCAT
  strlcat(qfile, q_filename, strlen(qfile) + strlen(q_filename) + 1);
#else
  strcat (qfile, q_filename);
#endif /* HAVE_STRLCAT */

  /* Skip duplicated / at start of qfile.
   * Use memmove to shift in-place instead of pointer arithmetic,
   * which would break free() on the original malloc'd address. */
  while (strlen(qfile) > 1 && qfile[0] == '/' && qfile[1] == '/')
    memmove(qfile, qfile + 1, strlen(qfile));

  output_debug ("qfile is \"%s\"\n", qfile);

  myquota->_id = id;
  myquota->_id_type = q_type;
  myquota->_qfile = qfile;

  free (fs);
  return myquota;
}

inline void quota_delete (quota_t *myquota) {

  free (myquota->_qfile);
  free (myquota);
}

int quota_get (quota_t *myquota)
{
  struct dqblk sysquota;
  int retval;

  output_debug ("fetching quotas: device='%s',id='%d'",
               myquota->_qfile, myquota->_id);
  retval = quotactl (myquota->_qfile, QCMD(Q_GETQUOTA, myquota->_id_type),
                   myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotas: %s", strerror (errno));
    return 0;
  }

  /* here, linux.c does a memcpy(), it should also work for bsd,
   * but it's better to be on the safe side
   */
  myquota->block_hard  = sysquota.dqb_bhardlimit;
  myquota->block_soft  = sysquota.dqb_bsoftlimit;
  myquota->diskspace_used  = sysquota.dqb_curblocks * BLOCK_SIZE;
  myquota->inode_hard  = sysquota.dqb_ihardlimit;
  myquota->inode_soft  = sysquota.dqb_isoftlimit;
  myquota->inode_used  = sysquota.dqb_curinodes ;
  myquota->block_time = (time_t) sysquota.dqb_btime;
  myquota->inode_time = (time_t) sysquota.dqb_itime;
  /* Initialize grace fields from the kernel's timer values.
   * Without this, block_grace/inode_grace contain garbage from
   * malloc, which quota_set() would then write to dqb_btime/itime. */
  myquota->block_grace = (time_t) sysquota.dqb_btime;
  myquota->inode_grace = (time_t) sysquota.dqb_itime;

#if __NetBSD__
  /* Seems a bug in NetBSD (at least 6.0), quotas are returned one block/inode less than previously set */
  myquota->block_hard++;
  myquota->block_soft++;
  myquota->inode_hard++;
  myquota->inode_soft++;
#endif

  return 1;
}

int quota_set (quota_t *myquota){
  struct dqblk sysquota;
  int retval;

  if ( geteuid() != 0 ) {
    output_error ("Only root can set quotas");
    return 0;
  }

  /* Zero the struct to avoid passing uninitialized padding bytes
   * or extra fields to the kernel via quotactl. */
  memset(&sysquota, 0, sizeof(sysquota));

  sysquota.dqb_bhardlimit = myquota->block_hard;
  sysquota.dqb_bsoftlimit = myquota->block_soft;
  sysquota.dqb_curblocks  = BYTES_TO_BLOCKS(myquota->diskspace_used);
  sysquota.dqb_ihardlimit = myquota->inode_hard;
  sysquota.dqb_isoftlimit = myquota->inode_soft;
  sysquota.dqb_curinodes  = myquota->inode_used;
  sysquota.dqb_btime      = myquota->block_grace;
  sysquota.dqb_itime      = myquota->inode_grace;

  /* make the syscall */
  retval = quotactl (myquota->_qfile, QCMD(Q_SETQUOTA, myquota->_id_type),
                       myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed setting quota: %s", strerror (errno));
    return 0;
  }

  /* Set global grace period via uid 0's dqb_btime/dqb_itime.
   * On BSD, the kernel ignores dqb_btime/dqb_itime for non-root
   * users in Q_SETQUOTA. The global default grace period is stored
   * on uid 0. This matches what edquota -t does. */
  if (myquota->_do_set_global_block_gracetime || myquota->_do_set_global_inode_gracetime) {
    struct dqblk grace_dq;
    memset(&grace_dq, 0, sizeof(grace_dq));

    /* Read uid 0's current quota to preserve existing fields */
    retval = quotactl(myquota->_qfile, QCMD(Q_GETQUOTA, myquota->_id_type),
                      0, (caddr_t) &grace_dq);
    if (retval < 0) {
      output_error("Failed reading global grace period: %s", strerror(errno));
      return 0;
    }

    if (myquota->_do_set_global_block_gracetime) {
      output_debug(">> set global block gracetime = %d", (int) myquota->block_grace);
      grace_dq.dqb_btime = myquota->block_grace;
    }
    if (myquota->_do_set_global_inode_gracetime) {
      output_debug(">> set global inode gracetime = %d", (int) myquota->inode_grace);
      grace_dq.dqb_itime = myquota->inode_grace;
    }

    retval = quotactl(myquota->_qfile, QCMD(Q_SETQUOTA, myquota->_id_type),
                      0, (caddr_t) &grace_dq);
    if (retval < 0) {
      output_error("Failed setting global grace period: %s", strerror(errno));
      return 0;
    }
  }

  /* Q_SYNC removed: Q_SETQUOTA already persists quota data via the
   * kernel's internal dqrele()/dqsync() path. An explicit Q_SYNC is
   * redundant — BSD edquota(8) doesn't use it either. On OpenBSD,
   * Q_SYNC hangs indefinitely on vnd-backed FFS due to dquot lock
   * contention or buffer cache stalls (softdep disabled since 2023).
   */

  return 1;
}

int quota_reset_grace(quota_t *myquota, int grace_type) {
   quota_t temp_quota;

   memcpy(&temp_quota, myquota, sizeof(quota_t));

   if (grace_type == GRACE_BLOCK)
       temp_quota.block_hard = temp_quota.block_soft = BYTES_TO_BLOCKS(temp_quota.diskspace_used) + 2; // > 1 needed because of bug in NetBSD
   else
       temp_quota.inode_hard = temp_quota.inode_soft = temp_quota.inode_used + 1;

   if (quota_set(&temp_quota) && quota_set(myquota))
       return 1;

   output_error("Cannot reset grace period!");
   return 0; // error, on success we return above
}
