/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * system.c
 * interact with various system databases
 */

#include <config.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <grp.h>
#include <pwd.h>
#include <errno.h>

#if HAVE_MNTENT_H
#  include <mntent.h>
#  define MOUNTFILE "/etc/mtab"
#  define mnt_special mnt_fsname
#  define mnt_mountp mnt_dir
#elif HAVE_SYS_MNTTAB_H
#  include <sys/mnttab.h>
#  define MOUNTFILE "/etc/mnttab"
#  define mntent mnttab
#  define setmntent(file,mode) fopen((file),(mode))
#  define endmntent(file)      fclose((file))
#elif HAVE_SYS_MNTCTL_H /* AIX :( */
#  include <sys/mntctl.h>
struct mntent {
  char *mnt_fsname;
  char *mnt_dir;
  char *mnt_special;
  char *mnt_mountp;
  int  vmt_flags;
};
#endif

#include <sys/types.h>

/*
#include "output.h"
*/
#include "quotatool.h"
#include "system.h"



/* 
 * system_getfs
 * find and verify the device file for
 * a given filesystem
 */
fs_t *system_getfs (char *fs_spec) {
  struct mntent *current_fs;
  FILE *etc_mtab;
  fs_t *ent;
  int done;
#if HAVE_SYS_MNTCTL_H /* AIX :( */
  char *vmnt_buffer;
  struct vmount   *vmnt;
  int vmnt_retval, vmnt_size, vmnt_nent;
#endif

  ent = (fs_t *) malloc (sizeof(fs_t));
  if ( ! ent ) {
    output_error ("Insufficient Memory");
    exit (ERR_MEM);
  }


#if HAVE_SYS_MNTCTL_H /* AIX, we are again in trouble. */
  /* first mntctl call is only for getting the size of 
   * vmnt array. is there a better way? */
  vmnt_retval = mntctl (MCTL_QUERY, sizeof(int), (char*)&vmnt_size);
  if (vmnt_retval != -1) {
    vmnt_buffer=(char*)malloc(vmnt_size);
    vmnt_retval = mntctl (MCTL_QUERY, vmnt_size, vmnt_buffer);
  }
  if ( vmnt_retval == -1 ) {
    output_error ("Failed getting vmnt info: %s", strerror(errno));
    return NULL;
  }
  vmnt_nent = vmnt_retval; /* number of entries */
  vmnt = (struct vmount*) vmnt_buffer;
  current_fs=(struct mntent*)malloc(sizeof(struct mntent));
#else
  etc_mtab = setmntent (MOUNTFILE, "r");
  if ( ! etc_mtab ) {
    output_error ("Failed opening %s for reading: %s", MOUNTFILE,
				  strerror(errno));
    return NULL;
  }
#endif


  output_debug ("Looking for fs_spec '%s'", fs_spec);

  done = 0;

  /* loop through mtab until we get a match */
  do {
    
    /* read the next entry */
#if HAVE_SYS_MNTTAB_H
    int retval;
    retval = getmntent(etc_mtab, current_fs);
    if ( retval != 0 ) {
#elif HAVE_MNTENT_H
    current_fs=getmntent(etc_mtab);
    if ( ! current_fs ) {
#elif HAVE_SYS_MNTCTL_H /* AIX, we are again in trouble. */
   current_fs->mnt_special = 
	(char*)vmnt + (vmnt->vmt_data[VMT_OBJECT].vmt_off);
   current_fs->mnt_mountp = 
	(char*)vmnt + (vmnt->vmt_data[VMT_STUB].vmt_off);
   current_fs->vmt_flags = vmnt->vmt_flags;
   vmnt = (struct vmount*) ((char*)vmnt + vmnt->vmt_length);
   if ( --vmnt_nent < 0 ) {
#endif
      output_error ("Filesystem %s does not exist", fs_spec);
      return NULL;
    }
    
    output_debug ("Checking device '%s', mounted at '%s'",
		  current_fs->mnt_special, current_fs->mnt_mountp);

    /* does the name given match the mount pt or device file ? */
    if ( ! strcmp(current_fs->mnt_special, fs_spec)
	 || ! strcmp(current_fs->mnt_mountp, fs_spec) ) {

#if HAVE_MNTENT_H
      #define LOOP_PREFIX "loop="
      char *loopd_start = NULL, *loopd_end = NULL;

      #if PLATFORM_LINUX
      strncpy(ent->mnt_type, current_fs->mnt_type, PATH_MAX-1);
      #endif

      if ((loopd_start = strstr(current_fs->mnt_opts, LOOP_PREFIX "/")) != NULL) {
	loopd_start += strlen(LOOP_PREFIX);
	output_debug("%s looks like a loop device, trying to grok opts: %s",
		     current_fs->mnt_special, current_fs->mnt_opts);
	for (loopd_end = loopd_start;
	     *loopd_end != '\0' && *loopd_end != ',';
	     loopd_end++);
	if (loopd_end > loopd_start) {
	  strncpy(ent->device, loopd_start, loopd_end - loopd_start);
	  ent->device[loopd_end - loopd_start] = '\0';
	  output_debug("found loop device %s", ent->device);
	}
	else {
	  output_error("%s seems like a loop device but I "
		       "can't grok the device from opts: %s\n",
		       current_fs->mnt_special,
		       current_fs->mnt_opts);
	  endmntent(etc_mtab);
	  return NULL;
	}
      }
      else {
#endif /* HAVE_MNTENT_H */	
      strncpy (ent->device, current_fs->mnt_special, PATH_MAX-1);
      strncpy (ent->mount_pt, current_fs->mnt_mountp, PATH_MAX-1);
#if HAVE_MNTENT_H
      }
#endif
      done = 1;
      continue;
    }

  } while ( ! done ) ;  


  /* can we write to the device? */
#if HAVE_SYS_MNTCTL_H
  if( ! (current_fs->vmt_flags && MNT_READONLY) ) {
    printf("0x%x\n", current_fs->vmt_flags);
    output_error ("Filesystem %s is mounted read-only\n", fs_spec);
    free(current_fs);
    free(vmnt_buffer);
#else 
  if ( hasmntopt(current_fs, "ro") ) {
    output_error ("Filesystem %s is mounted read-only\n", fs_spec);
    endmntent (etc_mtab);
#endif
    return NULL;
  }

  /* we're good -- cleanup and return */
  output_info ("filesystem %s has device node %s", fs_spec, ent->device);
#if HAVE_SYS_MNTCTL_H
  free(current_fs);
  free(vmnt_buffer);
#else 
  endmntent (etc_mtab);
#endif
  return ent;
}



/*
 * system_getuser
 * get the uid of the given user (or uid)
 */
uid_t system_getuid (char *user) {
  struct passwd *pwent;
  int uid;
  char *temp_str;
  /* seach by name first */
   pwent = getpwnam (user);
 
   if ( pwent == NULL ) {

     /* maybe we were given a numerical id */
     uid = strtol(user, &temp_str, 10);
     pwent = getpwuid ((uid_t) uid); 
     if ( (user == temp_str) || ( pwent == NULL ) ) {
       output_error ("User %s does not exist\n", user);
       return -1;
     }
   }
   output_info ("user '%s' has uid %d", user, pwent->pw_uid);
   return (pwent->pw_uid);
}



gid_t system_getgid (char *group) {
  struct group  *grent;
  int gid;
  char *temp_str;
  
  /* check for group name first */
  grent = getgrnam (group);
  if ( grent == NULL ) {
    gid = strtol(group, &temp_str, 10);
    grent = getgrgid ((gid_t) gid);   // numeric gid
    if ( (group == temp_str) || ( grent == NULL ) )
      {
	output_error ("Group %s does not exist\n", group);
	return (gid_t) -1;
      }
  }
  output_info ("group '%s' has gid %d", group, grent->gr_gid);  
  return (grent->gr_gid);
}
