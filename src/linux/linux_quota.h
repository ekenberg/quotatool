/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * linux/quota.h
 *
 * quota defs for linux
 * We don't use <linux/quota.h>
 */

#ifndef LINUX_QUOTA_H
#define LINUX_QUOTA_H

#include <sys/cdefs.h>
#include <sys/types.h>
#include "system.h"

typedef u_int32_t qid_t;	/* Type in which we store ids in memory */
typedef u_int64_t qsize_t;	/* Type in which we store size limitations */

#define MAXQUOTAS 2
#define USRQUOTA  0		/* element used for user quotas */
#define GRPQUOTA  1		/* element used for group quotas */

/*
 * Command definitions for the 'quotactl' system call.
 * The commands are broken into a main command defined below
 * and a subcommand that is used to convey the type of
 * quota that is being manipulated (see above).
 */
#define SUBCMDMASK  0x00ff
#define SUBCMDSHIFT 8
#define QCMD(cmd, type)  (((cmd) << SUBCMDSHIFT) | ((type) & SUBCMDMASK))

/* Interface versions */
#define IFACE_VFSOLD 1
#define IFACE_VFSV0 2
#define IFACE_GENERIC 3

/* _6_5_ are the older defs */
#define Q_6_5_SYNC     0x0600	/* sync disk copy of a filesystems quotas */

#if 0				/* not used */
  #define Q_6_5_QUOTAOFF 0x0200	/* disable quotas */
  #define Q_6_5_QUOTAON  0x0100	/* enable quotas */
#endif

#define Q_SYNC     0x800001     /* sync disk copy of a filesystems quotas */
#if 0				/* not used */
  #define Q_QUOTAON  0x800002     /* turn quotas on */
  #define Q_QUOTAOFF 0x800003     /* turn quotas off */
#endif
#define Q_GETFMT   0x800004     /* get quota format used on given filesystem */
#define Q_GETINFO  0x800005     /* get information about quota files */
#define Q_SETINFO  0x800006     /* set information about quota files */
#define Q_GETQUOTA 0x800007     /* get user quota structure */
#define Q_SETQUOTA 0x800008     /* set user quota structure */

/*
 * Quota structure used for communication with userspace via quotactl
 * Following flags are used to specify which fields are valid
 */
#define QIF_BLIMITS     1
#define QIF_SPACE       2
#define QIF_ILIMITS     4
#define QIF_INODES      8
#define QIF_BTIME       16
#define QIF_ITIME       32
#define QIF_LIMITS      (QIF_BLIMITS | QIF_ILIMITS)
#define QIF_USAGE       (QIF_SPACE | QIF_INODES)
#define QIF_TIMES       (QIF_BTIME | QIF_ITIME)
#define QIF_ALL         (QIF_LIMITS | QIF_USAGE | QIF_TIMES)


/* The generic diskblock-struct: */
struct if_dqblk {
  u_int64_t dqb_bhardlimit;
  u_int64_t dqb_bsoftlimit;
  u_int64_t dqb_curspace;
  u_int64_t dqb_ihardlimit;
  u_int64_t dqb_isoftlimit;
  u_int64_t dqb_curinodes;
  u_int64_t dqb_btime;
  u_int64_t dqb_itime;
  u_int32_t dqb_valid;
};

/* version-specific info */
struct v0_mem_dqinfo {};
struct old_mem_dqinfo {
  unsigned int dqi_blocks;
  unsigned int dqi_free_blk;
  unsigned int dqi_free_entry;
};

/* According to 'man quotactl' these are defined in sys/quota.h
   but that seems to not always be the case */
#ifndef IIF_BGRACE
#define IIF_BGRACE  1
#endif

#ifndef IIF_IGRACE
#define IIF_IGRACE  2
#endif

#ifndef IIF_FLAGS
#define IIF_FLAGS   4
#endif

#ifndef IIF_ALL
#define IIF_ALL     (IIF_BGRACE | IIF_IGRACE | IIF_FLAGS)
#endif


/* The generic diskinfo-struct: */
struct if_dqinfo {
  u_int64_t dqi_bgrace;
  u_int64_t dqi_igrace;
  u_int32_t dqi_flags;
  u_int32_t dqi_valid;
};

/* Ioctl for getting quota size */
#include <sys/ioctl.h>
#ifndef FIOQSIZE
	#if defined(__alpha__) || defined(__powerpc__) || defined(__sh__) || defined(__sparc__) || defined(__sparc64__)
		#define FIOQSIZE _IOR('f', 128, loff_t)
	#elif defined(__arm__) || defined(__mc68000__) || defined(__s390__)
		#define FIOQSIZE 0x545E
        #elif defined(__i386__) || defined(__i486__) || defined(__i586__) || defined(__ia64__) || defined(__parisc__) || defined(__cris__) || defined(__hppa__)
		#define FIOQSIZE 0x5460
	#elif defined(__mips__) || defined(__mips64__)
		#define FIOQSIZE 0x6667
	#endif
#endif

long quotactl (int, const char *, qid_t, caddr_t);

/*
 * runtime detection of quota format
 */

/* Values for format handling */
#define QF_TOONEW -2            /* Quota format is too new to handle */
#define QF_ERROR -1             /* There was error while detecting format (maybe unknown format...) */
#define QF_VFSOLD 0             /* Old quota format */
#define QF_VFSV0 1              /* New quota format - version 0 */
#define QF_VFSV1 2              /* Newer quota format - version 1 */
#define QF_XFS 3		/* XFS quota */

#define KERN_KNOWN_QUOTA_VERSION (6*10000 + 5*100 + 2)
int kern_quota_format(fs_t *, int);

#include "dqblk_old.h"
#include "dqblk_v0.h"
#include "xfs_quota.h"

#endif /* _QUOTA_ */
