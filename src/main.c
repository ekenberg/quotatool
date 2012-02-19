/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * parse.c
 * command line parsing routines
 */
#include <config.h>

#include <stdio.h>
#include <stdlib.h>

#include "quotatool.h"
#include "output.h"
#include "parse.h"
#include "quota.h"
#include "system.h"

int main (int argc, char **argv) {
  u_int64_t block_sav, inode_sav;
  u_int64_t old_quota;
  int id;
  time_t old_grace;
  argdata_t *argdata;
  quota_t *quota;
  

  
  /* parse commandline and fill argdata */
  argdata = parse_commandline (argc, argv);
  if ( ! argdata ) {
    exit (ERR_PARSE);
  }


  /* initialize the id to use */
  if ( ! argdata->id ) {
    id = 0;
  }
  else if ( argdata->id_type == QUOTA_USER ) {
    id = (int) system_getuid (argdata->id);
  }
  else {
    id = (int) system_getgid (argdata->id);
  }
  if ( id < 0 ) {
    exit (ERR_ARG);
  }
  
  
  /* get the quota info */
  quota = quota_new (argdata->id_type, id, argdata->qfile);
  if ( ! quota ) {
    exit (ERR_SYS);
  }
  
  if ( ! quota_get(quota) ) {
    exit (ERR_SYS);
  }

  if (argdata->dump_info) {
     time_t now = time(NULL);
     u_int64_t display_blocks_used = 0;

     output_info ("");
     output_info ("%s Filesystem blocks quota limit grace files quota limit grace",
		  argdata->id_type == QUOTA_USER ? "uid" : "gid");

     /*
       Except on XFS, quota->block_used is bytes. Divide by 1024 to show kilobytes
      */

     display_blocks_used = quota->block_used / 1024;
     if (quota->block_used % 1024 != 0) display_blocks_used += 1;
     printf("%d %s %llu %llu %llu %d %llu %llu %llu %d\n",
	    id,
	    argdata->qfile,
	    display_blocks_used,
	    quota->block_soft,
	    quota->block_hard,
	    quota->block_time ? quota->block_time - now : 0,
	    quota->inode_used,
	    quota->inode_soft,
	    quota->inode_hard,
	    quota->inode_time ? quota->inode_time - now : 0);
     exit(0);
  }

  /* print a header for verbose info */
  output_info ("");
  output_info ("%-14s %-16s %-16s", "Limit", "Old", "New");
  output_info ("%-14s %-16s %-16s", "-----", "---", "---");



  /*
   *  BEGIN  setting global grace periods
   */

  if ( argdata->block_grace ) {
    old_grace = quota->block_grace;
    quota->block_grace = parse_timespan (old_grace, argdata->block_grace);
    quota->_do_set_global_block_gracetime = 1;
    output_info ("%-14s %-16d %-16d", "block grace:", old_grace, quota->block_grace);
  }

  if ( argdata->inode_grace ) {
    old_grace = quota->inode_grace;
    quota->inode_grace = parse_timespan (old_grace, argdata->inode_grace);
    quota->_do_set_global_inode_gracetime = 1;
    output_info ("%-14s %-16d %-16d", "inode grace:", old_grace, quota->inode_grace);
  }



  /* 
   *  FINISH setting global grace periods
   *  BEGIN  preparing to set quotas
   */  


  /* update quota info from the command line */
  if ( argdata->block_hard ) {
    old_quota = quota->block_hard;
    quota->block_hard = parse_size (old_quota, argdata->block_hard);
    if ( quota->block_hard < 0 ) {
      exit (ERR_ARG);
    }
    if ( argdata->raise_only && quota->block_hard <= old_quota) {
       output_info ("New block quota not higher than current, won't change");
       quota->block_hard = old_quota;
    }
    output_info ("%-14s %-16llu %llu", "block hard:", old_quota, quota->block_hard);
  }

  if ( argdata->block_soft ) {
    old_quota = quota->block_soft;
    quota->block_soft= parse_size (old_quota, argdata->block_soft);
    if ( quota->block_soft < 0 ) {
      exit (ERR_ARG);
    }
    if ( argdata->raise_only && quota->block_soft <= old_quota) {
       output_info ("New block soft limit not higher than current, won't change");
       quota->block_soft = old_quota;
    }
    output_info ("%-14s %-16llu %-16llu", "block soft:", old_quota, quota->block_soft);
  }

  if ( argdata->inode_hard ) {
    old_quota = quota->inode_hard;
    quota->inode_hard = parse_size (old_quota, argdata->inode_hard);
    if ( quota->inode_hard < 0 ) {
      exit (ERR_ARG);
    }
    if ( argdata->raise_only && quota->inode_hard <= old_quota) {
       output_info ("New inode quota not higher than current, won't change");
       quota->inode_hard = old_quota;
    }
    output_info ("%-14s %-16llu %-16llu", "inode hard:", old_quota, quota->inode_hard);
  }

  if ( argdata->inode_soft ) {
    old_quota = quota->inode_soft;
    quota->inode_soft = parse_size (old_quota, argdata->inode_soft);
    if ( quota->inode_soft < 0 ) {
      exit (ERR_ARG);
    }
    if ( argdata->raise_only && quota->inode_soft <= old_quota) {
       output_info ("New inode soft limit not higher than current, won't change");
       quota->inode_soft = old_quota;
    }
    output_info ("%-14s %-16llu %-16llu", "inode_soft:", old_quota, quota->inode_soft);
  }


  /* 
   * FINISH preparing to set quotas
   *  BEGIN  resetting grace periods
   *   
   * to "reset" the grace period, we really
   * set the current used {blocks,inodes}
   * to the soft limit - 1, call quota_set,
   * then reinstate the original usage.
   *
   * NB: This doesn't work with XFS. Hence the (ugly ?) hack below. /Johan
   */


  if ( argdata->block_reset || argdata->inode_reset) {
     block_sav = quota->block_used;
     inode_sav = quota->inode_used;
     if ( argdata->block_reset ) {
	xfs_reset_grace(quota, GRACE_BLOCK);
	quota->block_used = quota->block_soft - 1;
     }
     if ( argdata->inode_reset ) {
	xfs_reset_grace(quota, GRACE_INODE);
	quota->inode_used = quota->inode_soft - 1;
     }
     if ( ! argdata->noaction ) {
	if ( ! quota_set (quota) ) {
	   exit (ERR_SYS);
	}
     }     
     quota->block_used = block_sav;
     quota->inode_used = inode_sav;
  }

  /*
   * FINISH resetting grace periods
   * FINALLY really set new quotas
   */
  
  if ( ! argdata->noaction ) {
    if ( ! quota_set (quota) ) {
      exit (ERR_SYS);
    }
  }


  quota_delete (quota);
  exit (0);
}
