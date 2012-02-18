/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * dqblk_v2.h
 * Header file for disk format of new quotafile format
 */

#ifndef _DQBLK_V2_H
#define _DQBLK_V2_H

#include <sys/types.h>

#define Q_V2_GETQUOTA	0x0D00	/* Get limits and usage */
#define Q_V2_SETQUOTA	0x0E00	/* Set limits and usage */
#define Q_V2_GETINFO	0x0900	/* Get information about quota */
#define Q_V2_SETINFO	0x0A00	/* Set information about quota */
#define Q_V2_SETGRACE	0x0B00	/* set inode and block grace */
#define Q_V2_GETSTATS	0x1100	/* get collected stats (before proc was used) */

/* Structure of quota for communication with kernel */
struct v2_kern_dqblk {
   unsigned int dqb_ihardlimit;
   unsigned int dqb_isoftlimit;
   unsigned int dqb_curinodes;
   unsigned int dqb_bhardlimit;
   unsigned int dqb_bsoftlimit;
   qsize_t dqb_curspace;
   time_t dqb_btime;
   time_t dqb_itime;
};

/* Structure of quotafile info for communication with kernel */
struct v2_kern_dqinfo {
   unsigned int dqi_bgrace;
   unsigned int dqi_igrace;
   unsigned int dqi_flags;
   unsigned int dqi_blocks;
   unsigned int dqi_free_blk;
   unsigned int dqi_free_entry;
};

/* Structure with gathered statistics from kernel */
struct v2_dqstats {
   u_int32_t lookups;
   u_int32_t drops;
   u_int32_t reads;
   u_int32_t writes;
   u_int32_t cache_hits;
   u_int32_t allocated_dquots;
   u_int32_t free_dquots;
   u_int32_t syncs;
   u_int32_t version;
};

#endif
