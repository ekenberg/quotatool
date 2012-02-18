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

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/stat.h>

#include "output.h"
#include "quota.h"
#include "quotatool.h"
#include "system.h"


#define QUOTAFILE "quotas"

int xfs_reset_grace(quota_t *, int);

inline quota_t *quota_new (int q_type, int id, char *fs_spec) {
  quota_t *myquota;
  fs_t *fs;
  char *qfile;
  int len;

  myquota = (quota_t *) malloc (sizeof(quota_t));
  if ( ! myquota ) {
    output_error ("Insufficient memory");
    exit (ERR_MEM);
  }

  fs = system_getfs (fs_spec);
  if ( ! fs ) {
    return NULL;
  }

  len = strlen(fs->mount_pt) + strlen(QUOTAFILE) + 2;
  qfile = (char *) malloc (len);
  snprintf (qfile, len, "%s/%s", fs->mount_pt, QUOTAFILE);

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
  struct quotctl qinfo;
  int retval, qfd;

  /* open the quota file */
  qfd = open (myquota->_qfile, O_RDWR);
  if ( qfd < 0 ) {
    output_error ("Failed opening %s for reading", myquota->_qfile);
    return 0;
  }

  /* set up struct quotctl */
  qinfo.op = Q_GETQUOTA;
  qinfo.uid = (uid_t) myquota->_id;
  qinfo.addr = (caddr_t) &sysquota;

  /* make the call */
  output_info ("fetching quotas from %s", myquota->_qfile);
  retval = ioctl (qfd, Q_QUOTACTL, &qinfo);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotas: %s (%d)", strerror(errno),
	errno);
    return 0;
  }

  /* copy the system-formatted quota info into our struct */
  myquota->block_hard  = sysquota.dqb_bhardlimit;
  myquota->block_soft  = sysquota.dqb_bsoftlimit;
  myquota->block_used  = sysquota.dqb_curblocks;
  myquota->inode_hard  = sysquota.dqb_fhardlimit;
  myquota->inode_soft  = sysquota.dqb_fsoftlimit;
  myquota->inode_used  = sysquota.dqb_curfiles;
  myquota->block_grace = sysquota.dqb_btimelimit;
  myquota->inode_grace = sysquota.dqb_ftimelimit;
  
  /* it worked! */
  return 1;
}



int quota_set (quota_t *myquota)
{
  struct dqblk sysquota;
  struct quotctl qinfo;
  int retval;
  int qfd;

  if ( geteuid() != 0 ) {
    output_error ("Only root can set quotas");
    return 0;
  }

  /* copy our data into the system dqblk */
  sysquota.dqb_bhardlimit = myquota->block_hard;
  sysquota.dqb_bsoftlimit = myquota->block_soft;
  sysquota.dqb_curblocks  = myquota->block_used;
  sysquota.dqb_fhardlimit = myquota->inode_hard;
  sysquota.dqb_fsoftlimit = myquota->inode_soft;
  sysquota.dqb_curfiles   = myquota->inode_used;
  sysquota.dqb_btimelimit = myquota->block_grace;
  sysquota.dqb_ftimelimit = myquota->inode_grace;

  /* set up struct quotctl */
  qinfo.op = Q_SETQUOTA;
  qinfo.uid = myquota->_id;
  qinfo.addr = (caddr_t) &sysquota;

  /* open the quota file */
  qfd = open (myquota->_qfile, O_WRONLY);
  if ( ! qfd ) {
    output_error ("Failed opening %s for writing", myquota->_qfile);
    return 0;
  }

  /* make the syscall */
  retval = ioctl (qfd, Q_QUOTACTL, &qinfo);
  if ( retval < 0 ) {
    output_error ("Failed setting quota: %s", strerror(errno));
    return 0;
  }

  qinfo.op = Q_SYNC;
  retval = ioctl (qfd, Q_QUOTACTL, &qinfo);
  if ( retval < 0 ) {
    output_error ("Failed syncing quotas on %s: %s", myquota->_qfile,
		  strerror(errno));
    return 0;
  }

  return 1;
}

int xfs_reset_grace(quota_t *myquota, int grace_type) {
  /* NOOP. Placeholder. Sorry.
       // Johan 
  */
  return 1;
}
