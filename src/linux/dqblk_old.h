/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * dqblk_old.h
 * Headerfile for old quotafile format
 */

#ifndef _DQBLK_OLD_H
#define _DQBLK_OLD_H

/* Structure of quota for communication with kernel */
struct old_kern_dqblk {
   u_int32_t dqb_bhardlimit;       /* absolute limit on disk blks alloc */
   u_int32_t dqb_bsoftlimit;       /* preferred limit on disk blks */
   u_int32_t dqb_curblocks;        /* current block count */
   u_int32_t dqb_ihardlimit;       /* maximum # allocated inodes */
   u_int32_t dqb_isoftlimit;       /* preferred inode limit */
   u_int32_t dqb_curinodes;        /* current # allocated inodes */
   time_t dqb_btime;       /* time limit for excessive disk use */
   time_t dqb_itime;       /* time limit for excessive files */
};

/* Values of quota calls */
#define Q_OLD_RSQUASH	0x1000
#define Q_OLD_GETQUOTA	0x300
#define Q_OLD_SETQUOTA	0x400
#define Q_OLD_GETSTATS	0x800

#endif
