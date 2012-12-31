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
#include <stdio.h>
#include <sys/stat.h>

#include "output.h"
#include "system.h"
#include "quota.h"
#include "quotatool.h"

#ifndef ENOTSUP
#define ENOTSUP EOPNOTSUPP
#endif

/* Handy macros */
#define QF_IS_OLD(qf)		(qf & (1 << QF_VFSOLD))
#define QF_IS_V0(qf)		(qf & (1 << QF_VFSV0))
#define QF_IS_V1(qf)		(qf & (1 << QF_VFSV1))
#define QF_IS_XFS(qf)		(qf & (1 << QF_XFS))
#define QF_IS_TOO_NEW(qf)	(qf == QF_TOONEW)
#define IF_GENERIC		(kernel_iface == IFACE_GENERIC)

static int quota_format;
static int kernel_iface;

static int old_quota_get(quota_t *);
static int old_quota_set(quota_t *);
static int v0_quota_get(quota_t *);
static int v0_quota_set(quota_t *);
static int generic_quota_get(quota_t *);
static int generic_quota_set(quota_t *);
static int xfs_quota_get(quota_t *);
static int xfs_quota_set(quota_t *);

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

  /*
   * Detect quota format
   */
  output_debug("Detecting quota format");
  if (kern_quota_format(fs, q_type) == QF_ERROR) {
     output_error("Cannot determine quota format!");
     exit (ERR_SYS);
  }
  if (QF_IS_TOO_NEW(quota_format)) {
     output_error("Quota format too new (?)");
     exit (ERR_SYS);
  }
  if (QF_IS_XFS(quota_format)) {
     output_debug("Detected quota format: XFS");
  }
  if (QF_IS_V0(quota_format)) {
     output_debug("Detected quota format: VFSV0");
     if (IF_GENERIC) {
       output_debug("Detected quota interface: GENERIC");
     }
     else {
       myquota->_v0_quotainfo = (struct v0_kern_dqinfo *) 0;
       myquota->_v0_quotainfo = (struct v0_kern_dqinfo *) malloc (sizeof(struct v0_kern_dqinfo));
       if ( ! myquota->_v0_quotainfo ) {
	 output_error ("Insufficient memory");
	 exit (ERR_MEM);
       }
     }
  }
  else if (QF_IS_V1(quota_format)) {
     output_debug("Detected quota format: VFSV1");
     if (IF_GENERIC) {
       output_debug("Detected quota interface: GENERIC");
     }
     else {
       output_error("Unsupported quota format: VFSV1 but not GENERIC, please report Issue on github: https://github.com/ekenberg/quotatool");
       exit(ERR_SYS);
     }
  }
  else if (QF_IS_OLD(quota_format)) {
     output_debug("Detected quota format: OLD");
     if (IF_GENERIC) {
       output_debug("Detected quota interface: GENERIC");
     }
  }
  else if (! QF_IS_XFS(quota_format)) {
     output_error("Unknown quota format!");
     exit(ERR_SYS);
  }
  if (IF_GENERIC) {
       myquota->_generic_quotainfo = (struct if_dqinfo *) 0;
       myquota->_generic_quotainfo = (struct if_dqinfo *) malloc (sizeof(struct if_dqinfo));
       if ( ! myquota->_generic_quotainfo ) {
	 output_error ("Insufficient memory");
	 exit (ERR_MEM);
       }
  }

  qfile = strdup (fs->device);

  myquota->_id = id;
  myquota->_id_type = q_type;
  myquota->_qfile = qfile;

  free (fs);
  return myquota;
}

inline void quota_delete (quota_t *myquota) {
  free (myquota->_qfile);
  if (IF_GENERIC) {
    free (myquota->_generic_quotainfo);
  }
  else if (QF_IS_V0(quota_format)) {
     free (myquota->_v0_quotainfo);
  }

  free (myquota);
}

int quota_get (quota_t *myquota) {
   int retval;

   output_debug ("fetching quotas: device='%s',id='%d'", myquota->_qfile,
		myquota->_id);
   if (QF_IS_XFS(quota_format)) {
      retval = xfs_quota_get(myquota);
   }
   else if (IF_GENERIC) {
      retval = generic_quota_get(myquota);
   }
   else if (QF_IS_V0(quota_format)) {
      retval = v0_quota_get(myquota);
   }
   else {
      retval = old_quota_get(myquota);
   }
   return retval;
}

static int old_quota_get (quota_t *myquota) {
  struct old_kern_dqblk sysquota;
  int retval;

  retval = quotactl(QCMD(Q_OLD_GETQUOTA,myquota->_id_type), myquota->_qfile,
		    myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotas (old): %s", strerror(errno));
    return 0;
  }

  /* copy the linux-formatted quota info into our struct */
  myquota->block_hard  = sysquota.dqb_bhardlimit;
  myquota->block_soft  = sysquota.dqb_bsoftlimit;
  myquota->diskspace_used  = sysquota.dqb_curblocks;
  myquota->inode_hard  = sysquota.dqb_ihardlimit;
  myquota->inode_soft  = sysquota.dqb_isoftlimit;
  myquota->inode_used  = sysquota.dqb_curinodes;
  myquota->block_time  = sysquota.dqb_btime;
  myquota->inode_time  = sysquota.dqb_itime;
  /* yes, something fishy here. quota old seems to lack separate fields
   for user grace times and global grace times.
  is it like XFS - root's limits sets global? */
  myquota->block_grace  = sysquota.dqb_btime;
  myquota->inode_grace  = sysquota.dqb_itime;

  return 1;
}

static int v0_quota_get (quota_t *myquota) {
  struct v0_kern_dqblk sysquota;
  int retval;

  retval = quotactl(QCMD(Q_V0_GETQUOTA,myquota->_id_type), myquota->_qfile,
		    myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotas (vfsv0): %s", strerror(errno));
    return 0;
  }

  /* copy the linux-formatted quota info into our struct */
  myquota->block_hard = sysquota.dqb_bhardlimit;
  myquota->block_soft = sysquota.dqb_bsoftlimit;
  myquota->diskspace_used = sysquota.dqb_curspace;
  myquota->inode_hard = sysquota.dqb_ihardlimit;
  myquota->inode_soft = sysquota.dqb_isoftlimit;
  myquota->inode_used = sysquota.dqb_curinodes;
  myquota->block_time = sysquota.dqb_btime;
  myquota->inode_time = sysquota.dqb_itime;

  retval = quotactl(QCMD(Q_V0_GETINFO,myquota->_id_type), myquota->_qfile,
		    myquota->_id, (caddr_t) myquota->_v0_quotainfo);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotainfo: %s", strerror(errno));
    return 0;
  }
  myquota->block_grace = ((struct v0_kern_dqinfo *) myquota->_v0_quotainfo)->dqi_bgrace;
  myquota->inode_grace = ((struct v0_kern_dqinfo *) myquota->_v0_quotainfo)->dqi_igrace;

  return 1;
}

static int generic_quota_get (quota_t *myquota) {
  struct if_dqblk sysquota;
  long retval;
  retval = quotactl(QCMD(Q_GETQUOTA,myquota->_id_type), myquota->_qfile,
		    myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotas (generic): %s", strerror(errno));
    return 0;
  }

  /* copy the linux-formatted quota info into our struct */
  myquota->block_hard = sysquota.dqb_bhardlimit;
  myquota->block_soft = sysquota.dqb_bsoftlimit;
  myquota->diskspace_used = sysquota.dqb_curspace;
  myquota->inode_hard = sysquota.dqb_ihardlimit;
  myquota->inode_soft = sysquota.dqb_isoftlimit;
  myquota->inode_used = sysquota.dqb_curinodes;
  myquota->block_time = sysquota.dqb_btime;
  myquota->inode_time = sysquota.dqb_itime;

  retval = quotactl(QCMD(Q_GETINFO,myquota->_id_type), myquota->_qfile,
		    myquota->_id, (caddr_t) myquota->_generic_quotainfo);
  if ( retval < 0 ) {
    output_error ("Failed fetching quotainfo (generic): %s", strerror(errno));
    return 0;
  }
  myquota->block_grace = ((struct if_dqinfo *) myquota->_generic_quotainfo)->dqi_bgrace;
  myquota->inode_grace = ((struct if_dqinfo *) myquota->_generic_quotainfo)->dqi_igrace;

  return 1;
}

static int xfs_quota_get(quota_t *myquota) {
   fs_disk_quota_t sysquota;
   fs_quota_stat_t quotastat;
   int block_diff;	// XFS quota always uses BB (Basic Blocks = 512 bytes)
   int retval;

   block_diff = BLOCK_SIZE / 512;
   retval = quotactl(QCMD(Q_XGETQUOTA, myquota->_id_type), myquota->_qfile,
		     myquota->_id, (caddr_t) &sysquota);
   /*
      ** 2005-04-26  : fmicaux@actilis.net -
                        handling a non-set quota for a user/group
                                             who owns nothing here
   */
   if ( retval < 0 ) {
      // This error has to be explained :
      // if UID/GID has no quota defined, and owns no data, ENOENT error occures
      // but at this point of the code, whe know that this XFS has quotas.
      // We make the choice to produce a "0 0 0 0 0 0 0 0" line.
      if ( errno == ENOENT ) {
         myquota->block_hard 	 = 0;
         myquota->block_soft	 = 0;
         myquota->diskspace_used = 0;
         myquota->inode_hard     = 0;
         myquota->inode_soft     = 0;
         myquota->inode_used     = 0;
         myquota->block_grace	 = 0;
         myquota->inode_grace	 = 0;
         myquota->block_time	 = 0;
         myquota->inode_time	 = 0;
         return 1;
      }
      output_error ("Failed fetching quotas: errno=%d, %s", errno, strerror(errno));
      return 0;
   }

   retval = quotactl(QCMD(Q_XGETQSTAT, myquota->_id_type), myquota->_qfile,
		     myquota->_id, (caddr_t) &quotastat);

   /* copy the linux-xfs-formatted quota info into our struct */
   myquota->block_hard	=  sysquota.d_blk_hardlimit / block_diff;
   myquota->block_soft	=  sysquota.d_blk_softlimit / block_diff;
   myquota->diskspace_used = sysquota.d_bcount / block_diff * 1024; // XFS really uses blocks, all other formats in this file use bytes
   myquota->inode_hard  =  sysquota.d_ino_hardlimit;
   myquota->inode_soft  =  sysquota.d_ino_softlimit;
   myquota->inode_used  =  sysquota.d_icount;
   myquota->block_grace	=  quotastat.qs_btimelimit;
   myquota->inode_grace	=  quotastat.qs_itimelimit;
   myquota->block_time	=  sysquota.d_btimer;
   myquota->inode_time	=  sysquota.d_itimer;

   return 1;
}

int quota_set (quota_t *myquota){
   int retval;

   if ( geteuid() != 0 ) {
      output_error ("Only root can set quotas");
      return 0;
   }

   /* set quota */
   if (QF_IS_XFS(quota_format)) {
      retval = xfs_quota_set(myquota);
   }
   else if (IF_GENERIC) {
      retval = generic_quota_set(myquota);
   }
   else if (QF_IS_V0(quota_format)) {
      retval = v0_quota_set(myquota);
   }
   else {
      retval = old_quota_set(myquota);
   }

   if (! retval)
      return retval;
   if (QF_IS_XFS(quota_format))
      return 1;	// no sync needed for XFS

   /* sync */
   retval = quotactl (QCMD(IF_GENERIC ? Q_SYNC : Q_6_5_SYNC
			   ,myquota->_id_type), myquota->_qfile,
		      0, NULL);
   if (retval < 0) {
      output_error ("Failed syncing quotas on %s: %s", myquota->_qfile,
		    strerror(errno));
      return 0;
   }
   return 1;
}

static int generic_quota_set(quota_t *myquota) {
   struct if_dqblk sysquota;
   int retval;

   /* copy our data into the linux dqblk */
   sysquota.dqb_bhardlimit = myquota->block_hard;
   sysquota.dqb_bsoftlimit = myquota->block_soft;
   sysquota.dqb_curspace   = myquota->diskspace_used;
   sysquota.dqb_ihardlimit = myquota->inode_hard;
   sysquota.dqb_isoftlimit = myquota->inode_soft;
   sysquota.dqb_curinodes  = myquota->inode_used;
//   sysquota.dqb_btime      = myquota->block_time;
//   sysquota.dqb_itime      = myquota->inode_time;
   sysquota.dqb_valid	   = QIF_LIMITS;
   /* make the syscall */
   retval = quotactl (QCMD(Q_SETQUOTA,myquota->_id_type),myquota->_qfile,
		      myquota->_id, (caddr_t) &sysquota);
   if ( retval < 0 ) {
     output_error ("Failed setting quota (generic): %s", strerror(errno));
     return 0;
   }
   /* update quotainfo (global gracetimes) */
   if (myquota->_do_set_global_block_gracetime || myquota->_do_set_global_inode_gracetime) {
     struct if_dqinfo *foo = ((struct if_dqinfo *) myquota->_generic_quotainfo);
      if (myquota->_do_set_global_block_gracetime)
	foo->dqi_bgrace = myquota->block_grace;
      if (myquota->_do_set_global_inode_gracetime)
	foo->dqi_igrace = myquota->inode_grace;
      retval = quotactl (QCMD(Q_SETINFO,myquota->_id_type),myquota->_qfile,
			 myquota->_id, (caddr_t) myquota->_generic_quotainfo);
      if ( retval < 0 ) {
	 output_error ("Failed setting gracetime (generic): %s", strerror(errno));
	 return 0;
      }
   }
   /* success */
   return 1;
}

static int v0_quota_set(quota_t *myquota) {
   struct v0_kern_dqblk sysquota;
   int retval;

   /* copy our data into the linux dqblk */
   sysquota.dqb_bhardlimit = myquota->block_hard;
   sysquota.dqb_bsoftlimit = myquota->block_soft;
   sysquota.dqb_curspace   = myquota->diskspace_used;
   sysquota.dqb_ihardlimit = myquota->inode_hard;
   sysquota.dqb_isoftlimit = myquota->inode_soft;
   sysquota.dqb_curinodes  = myquota->inode_used;
//   sysquota.dqb_btime      = myquota->block_time;
//   sysquota.dqb_itime      = myquota->inode_time;

   /* make the syscall */
   retval = quotactl (QCMD(Q_V0_SETQUOTA,myquota->_id_type),myquota->_qfile,
		      myquota->_id, (caddr_t) &sysquota);
   if ( retval < 0 ) {
      output_error ("Failed setting quota (vfsv0): %s", strerror(errno));
      return 0;
   }

   /* update quotainfo (global gracetimes) */
   if (myquota->_do_set_global_block_gracetime || myquota->_do_set_global_inode_gracetime) {
      if (myquota->_do_set_global_block_gracetime)
	 ((struct v0_kern_dqinfo *) myquota->_v0_quotainfo)->dqi_bgrace = myquota->block_grace;
      if (myquota->_do_set_global_inode_gracetime)
	 ((struct v0_kern_dqinfo *) myquota->_v0_quotainfo)->dqi_igrace = myquota->inode_grace;
      retval = quotactl (QCMD(Q_V0_SETGRACE,myquota->_id_type),myquota->_qfile,
			 myquota->_id, (caddr_t) myquota->_v0_quotainfo);
      if ( retval < 0 ) {
	 output_error ("Failed setting gracetime: %s", strerror(errno));
	 return 0;
      }
   }
   /* success */
   return 1;
}

static int old_quota_set(quota_t *myquota) {
   struct old_kern_dqblk sysquota;
   int retval;

  /* copy our data into the linux dqblk */
  sysquota.dqb_bhardlimit = myquota->block_hard;
  sysquota.dqb_bsoftlimit = myquota->block_soft;
  sysquota.dqb_curblocks  = myquota->diskspace_used;
  sysquota.dqb_ihardlimit = myquota->inode_hard;
  sysquota.dqb_isoftlimit = myquota->inode_soft;
  sysquota.dqb_curinodes  = myquota->inode_used;
  /* is old like xfs - global grace set by root's limits? */
  sysquota.dqb_btime      = myquota->block_grace;
  sysquota.dqb_itime      = myquota->inode_grace;

  /* make the syscall */
  retval = quotactl (QCMD(Q_OLD_SETQUOTA,myquota->_id_type),myquota->_qfile,
		     myquota->_id, (caddr_t) &sysquota);
  if ( retval < 0 ) {
    output_error ("Failed setting quota (old): %s", strerror(errno));
    return 0;
  }
  /* success */
  return 1;
}

static int xfs_quota_set(quota_t *myquota) {
   fs_disk_quota_t sysquota;
   int retval;
   int block_diff= BLOCK_SIZE / 512;

   memset(&sysquota, 0, sizeof(fs_disk_quota_t));
   /* copy our data into the linux dqblk */
   sysquota.d_blk_hardlimit = myquota->block_hard * block_diff;
   sysquota.d_blk_softlimit = myquota->block_soft * block_diff;
   sysquota.d_bcount	    = myquota->diskspace_used * block_diff / 1024; // XFS really uses blocks, all other formats in this file use bytes
   sysquota.d_ino_hardlimit = myquota->inode_hard;
   sysquota.d_ino_softlimit = myquota->inode_soft;
   sysquota.d_icount        = myquota->inode_used;
/* For XFS, global grace time limits are set by the values set for root */
   sysquota.d_btimer        = myquota->block_grace;
   sysquota.d_itimer        = myquota->inode_grace;
   sysquota.d_fieldmask	    = FS_DQ_LIMIT_MASK;
   if (myquota->_do_set_global_block_gracetime || myquota->_do_set_global_inode_gracetime)
      sysquota.d_fieldmask |= FS_DQ_TIMER_MASK;

   retval = quotactl(QCMD(Q_XSETQLIM,myquota->_id_type), myquota->_qfile,
		     myquota->_id, (caddr_t) &sysquota);
   if (retval < 0) {
      output_error ("Failed setting quota (xfs): %s", strerror(errno));
      return(0);
   }

   /* success */
   return 1;
}

/*
 *	Check kernel quota version
 *	(ripped from quota-utils, all credits to Honza!)
 */

int kern_quota_format(fs_t *fs, int q_type) {
   u_int32_t version;
   struct v0_dqstats v0_stats;
   FILE *f;
   int ret = 0;
   struct stat st;

   if (strcasecmp(fs->mnt_type, "xfs") == 0) {
      if (stat("/proc/fs/xfs/stat", &st) == 0) {
	 quota_format |= (1 << QF_XFS);
	 return ret;
      }
      else {
	 output_error("%s is mounted as XFS but no kernel support for XFS quota!", fs->device);
	 exit(ERR_SYS);
      }
   }

   if ((f = fopen("/proc/fs/quota", "r"))) {
      if (fscanf(f, "Version %u", &version) != 1) {
	 fclose(f);
	 return QF_TOONEW;
      }
      fclose(f);
   }
   else if (stat("/proc/sys/fs/quota", &st) == 0) {
      /* Either QF_VFSOLD or QF_VFSV0 or QF_VFSV1 */
      int actfmt, retval;
      kernel_iface = IFACE_GENERIC;
      retval = quotactl(QCMD(Q_GETFMT, q_type), fs->device, 0, (void *) &actfmt);
      if (retval < 0) {
	 if (! QF_IS_XFS(quota_format)) {
	    output_error("Error while detecting kernel quota version: %s\n", strerror(errno));
	    exit(ERR_SYS);
	 }
      }
      else {
	 if (actfmt == 1)  /* Q_GETFMT retval for QF_VFSOLD */
	    quota_format |= (1 << QF_VFSOLD);
	 else if (actfmt == 2)  /* Q_GETFMT retval for QF_VFSV0 */
	    quota_format |= (1 << QF_VFSV0);
	 else if (actfmt == 4)  /* Q_GETFMT retval for QF_VFSV1 */
	    quota_format |= (1 << QF_VFSV1);
	 else {
            output_debug("Unknown Q_GETFMT: %d\n", actfmt);
	    return QF_ERROR;
         }
      }
      return ret;
   }
   else if (quotactl(QCMD(Q_V0_GETSTATS, 0), NULL, 0, (void *) &v0_stats) >= 0) {
      version = v0_stats.version;	/* Copy the version */
   }
   else {
      if (errno == ENOSYS || errno == ENOTSUP)	/* Quota not compiled? */
	 return QF_ERROR;
      if (errno == EINVAL || errno == EFAULT || errno == EPERM) {	/* Old quota compiled? */
	 /* RedHat 7.1 (2.4.2-2) newquota check
	  * Q_V0_GETSTATS in it's old place, Q_GETQUOTA in the new place
	  * (they haven't moved Q_GETSTATS to its new value) */
	 int err_stat = 0;
	 int err_quota = 0;
	 char tmp[1024];         /* Just temporary buffer */

	 if (quotactl(QCMD(Q_OLD_GETSTATS, 0), NULL, 0, tmp))
	    err_stat = errno;
	 if (quotactl(QCMD(Q_OLD_GETQUOTA, 0), "/dev/null", 0, tmp))
	    err_quota = errno;

	 /* On a RedHat 2.4.2-2 	we expect 0, EINVAL
	  * On a 2.4.x 		we expect 0, ENOENT
	  * On a 2.4.x-ac	we wont get here */
	 if (err_stat == 0 && err_quota == EINVAL) {
	    quota_format |= (1 << QF_VFSV0);	/* New format supported */
	    kernel_iface = IFACE_VFSV0;
	 }
	 else {
	    quota_format |= (1 << QF_VFSOLD);
	    kernel_iface = IFACE_VFSOLD;
	 }
	 return ret;
      }
      output_error("Error while detecting kernel quota version: %s\n", strerror(errno));
      exit(ERR_SYS);
   }
   if (version > KERN_KNOWN_QUOTA_VERSION)	/* Newer kernel than we know? */
      quota_format = QF_TOONEW;
   if (version <= 6*10000+4*100+0) {		/* Old quota format? */
      quota_format |= (1 << QF_VFSOLD);
      kernel_iface = IFACE_VFSOLD;
   }
   else {
      quota_format |= (1 << QF_VFSV0);			/* New format supported */
      kernel_iface = IFACE_VFSOLD;
   }
   return ret;
}

int xfs_reset_grace(quota_t *myquota, int grace_type) {
   /*
     This is a hack for XFS which doesn't allow setting
     the current inode|block usage.
     Instead we temporarily raise the quota limits to
     current usage + 1, and then restore the previous limits.
     Either let it remain here, or rewrite the entire
     handling of resetting grace times.
   */

   quota_t temp_quota;

   if (! QF_IS_XFS(quota_format)) return 1;

   memcpy(&temp_quota, myquota, sizeof(quota_t));

   if (grace_type == GRACE_BLOCK) {
      output_debug("xfs_reset_grace: BLOCK");
      temp_quota.block_hard = temp_quota.block_soft = temp_quota.diskspace_used + 1;
      if (xfs_quota_set(&temp_quota) && xfs_quota_set(myquota)) {
	 return 1;
      }
   }
   else if (grace_type == GRACE_INODE) {
      output_debug("xfs_reset_grace: INODE");
      temp_quota.inode_hard = temp_quota.inode_soft = temp_quota.inode_used + 1;
      if (xfs_quota_set(&temp_quota) && xfs_quota_set(myquota)) {
	 return 1;
      }
   }
   else {
      // We shouldn't get here
      output_error("xfs_reset_grace(): wrong parameter for grace_type");
      return 0;
   }
   return 0; // error, on success we return above
}

/* int quota_on (int q_type, char *device);
 * int quota_off (int q_type, char *device);
 */


