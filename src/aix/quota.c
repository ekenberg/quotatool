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

int xfs_reset_grace(quota_t *, int);

quota_t *quota_new (int q_type, int id, char *fs_spec)
{
  quota_t *myquota;
  fs_t *fs;
  char *qfile;

  q_type--;			/* see defs in quota.h */
  if ( q_type >= MAXQUOTAS ) {
    output_error ("Unknown quota type: %d", q_type);
    return 0;
  }

  myquota = (quota_t *) malloc (sizeof(quota_t));
  if ( ! myquota ) {
    output_error ("Insufficient memory");
    exit (ERR_MEM);
  }

  fs = system_getfs (fs_spec);
  if ( ! fs ) {
    return NULL;
  }


  /* AIX requires a(ny) file in quota enabled file system as an arg. to
   * quotactl(). "quota.user" should be a good choice. maybe we should
   * also check for "quota.group".
   */
  qfile = malloc (strlen(fs->mount_pt)+13);  
  strcpy(qfile,fs->mount_pt);
  strcat(qfile,"/quota.user");
output_debug("qfile is, %s\n", qfile);

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


  output_debug ("fetching quotas: device='%s',id='%d'", myquota->_qfile,
		myquota->_id);
  retval = quotactl(myquota->_qfile,QCMD(Q_GETQUOTA,myquota->_id_type), 
		    myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotas: %s", strerror(errno));
    return 0;
  }
 
  /* here, linux.c does a memcpy(), it should also work for aix, 
   * but it's better to be on the safe side 
   */
  myquota->block_hard  = sysquota.dqb_bhardlimit;
  myquota->block_soft  = sysquota.dqb_bsoftlimit;
  myquota->block_used  = sysquota.dqb_curblocks ;
  myquota->inode_hard  = sysquota.dqb_ihardlimit;
  myquota->inode_soft  = sysquota.dqb_isoftlimit;
  myquota->inode_used  = sysquota.dqb_curinodes ;
  myquota->block_grace = sysquota.dqb_btime     ;
  myquota->inode_grace = sysquota.dqb_itime     ;
  
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
  sysquota.dqb_curblocks  = myquota->block_used;
  sysquota.dqb_ihardlimit = myquota->inode_hard;
  sysquota.dqb_isoftlimit = myquota->inode_soft;
  sysquota.dqb_curinodes  = myquota->inode_used;
  sysquota.dqb_btime      = myquota->block_grace;
  sysquota.dqb_itime      = myquota->inode_grace;


  /* make the syscall */
  retval = quotactl (myquota->_qfile, QCMD(Q_SETQUOTA,myquota->_id_type),
		     myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed setting quota: %s", strerror(errno));
    return 0;
  }

  retval = quotactl (myquota->_qfile, QCMD(Q_SYNC,myquota->_id_type), 
	0, NULL);
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

/* int quota_on (int q_type, char *device);
 * int quota_off (int q_type, char *device);
 */


