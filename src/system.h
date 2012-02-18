/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * system.h
 * interact with various system databases
 */
#ifndef INCLUDE_SYSTEM
#define INCLUDE_SYSTEM 1

#include <config.h>

#if HAVE_LIMITS_H
#  include <limits.h>
#else
#  warn "ignorantly setting PATH_MAX"
#  define PATH_MAX 256
#endif

#include <sys/types.h>		/* for [gu]id_t */

struct _fs_t {
  char device[PATH_MAX];
  char mount_pt[PATH_MAX];
#if PLATFORM_LINUX
   char mnt_type[PATH_MAX]; /* xfs, reiserfs, ext2 etc */
#endif /* PLATFORM_LINUX */
};
typedef struct _fs_t fs_t;

fs_t *  system_getfs    (char *fs_spec);
uid_t   system_getuid   (char *user);
gid_t   system_getgid   (char *group);


#endif /* INCLUDE_SYSTEM */
