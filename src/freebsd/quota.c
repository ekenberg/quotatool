/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * Mats Erik Andersson
 * debian@gisladisker.se
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
    return NULL;
  }

  qfile = malloc (strlen(fs->mount_pt) + strlen(q_filename) + 1);
  if (! qfile) {
    output_error ("Insufficient memory");
    exit (ERR_MEM);
  }

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

  // skip duplicated / at start of qfile
  while (strlen(qfile) > 1 && qfile[0] == '/' && qfile[1] == '/') qfile++;

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

  return 1;
}

int quota_set (quota_t *myquota){
  struct dqblk sysquota;
  int retval;

  if ( geteuid() != 0 ) {
    output_error ("Only root can set quotas");
    return 0;
  }

  sysquota.dqb_bhardlimit = myquota->block_hard;
  sysquota.dqb_bsoftlimit = myquota->block_soft;
  sysquota.dqb_curblocks  = BYTES_TO_BLOCKS(myquota->diskspace_used);
  sysquota.dqb_ihardlimit = myquota->inode_hard;
  sysquota.dqb_isoftlimit = myquota->inode_soft;
  sysquota.dqb_curinodes  = myquota->inode_used;
  sysquota.dqb_btime      = (int32_t) myquota->block_grace;
  sysquota.dqb_itime      = (int32_t) myquota->inode_grace;

  /* make the syscall */
  retval = quotactl (myquota->_qfile, QCMD(Q_SETQUOTA, myquota->_id_type),
                       myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed setting quota: %s", strerror (errno));
    return 0;
  }

  retval = quotactl (myquota->_qfile, QCMD(Q_SYNC, myquota->_id_type),
                       0, NULL);
  if ( retval < 0 ) {
    output_error ("Failed syncing quotas on %s: %s", myquota->_qfile,
                 strerror (errno));
    return 0;
  }

  return 1;
}

int quota_reset_grace(quota_t *myquota, int grace_type) {
   quota_t temp_quota;

   memcpy(&temp_quota, myquota, sizeof(quota_t));

   if (grace_type == GRACE_BLOCK)
       temp_quota.block_hard = temp_quota.block_soft = BYTES_TO_BLOCKS(temp_quota.diskspace_used) + 1;
   else
       temp_quota.inode_hard = temp_quota.inode_soft = temp_quota.inode_used + 1;

   if (quota_set(&temp_quota) && quota_set(myquota))
       return 1;

   output_error("Cannot reset grace period!");
   return 0; // error, on success we return above
}
