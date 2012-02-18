/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * parse.h
 *
 */
#ifndef INCLUDE_QUOTATOOL_PARSE
#define INCLUDE_QUOTATOOL_PARSE 1

#include <config.h>

#include <time.h>

struct _argdata_t {
  char *id;
  char *qfile;
  short id_type;
  short silent;
  short noaction;
  short dump_info; // don't touch anything, just dump machine-readable info for user/group
  short raise_only; // When changing quotas, don't lower - just raise

  char *block_hard;
  char *block_soft;
  char *block_grace;
  short block_reset;

  char *inode_hard;
  char *inode_soft;
  char *inode_grace;
  short inode_reset;
};
typedef struct _argdata_t argdata_t;


argdata_t *   parse_commandline   (int argc, char **argv);
time_t        parse_timespan      (time_t orig, char *string);
u_int64_t     parse_size          (u_int64_t orig, char *string);


#endif /* INCLUDE_QUOTATOOL_PARSE */
