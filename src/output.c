/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * output.c
 * talk to the nice people
 */

#include <config.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "output.h"
#include "quotatool.h"

#define OUTPUT_NOTHING  0
#define OUTPUT_ERROR    1
#define OUTPUT_INFO     2
#define OUTPUT_DEBUG    3

int output_level = OUTPUT_ERROR;



/*
 * output_version
 * print version and copyright info
 */
void output_version () {
   fprintf (stderr, "  %s version %d.%d.%s\n", PROGNAME, MAJOR_VERSION,
      MINOR_VERSION, PATCHLEVEL);
   fprintf (stderr, "  %s\n", COPYRIGHT_NOTICE);
   fprintf (stderr, "  Distributed under the GNU General Public License\n\n");
   fprintf (stderr, "  %s\n", WWW_URL);
}



/*
 * output_help
 * print a short usage message
 */
void output_help () {

  output_version ();
  fprintf (stderr, "\nUsage: quotatool -u uid | -g gid options [...] filesystem\n");
  fprintf (stderr, "       quotatool -u | -g -i | -b  -t time filesystem\n");
  fprintf (stderr, "Options:\n");
  fprintf (stderr, "  -b      : set block limits\n");
  fprintf (stderr, "  -i      : set inode limits\n");
  fprintf (stderr, "\n");

  fprintf (stderr, "  -q n    : set soft limit to n blocks/inodes\n");
  fprintf (stderr, "  -l n    : set hard limit to n blocks/inodes\n");
  fprintf (stderr, "     limits accept optional modifiers: Kb, Mb, Gb, Tb (see manpage)\n");
  fprintf (stderr, "\n");

  fprintf (stderr, "  -t time : set global grace period to time\n");
  fprintf (stderr, "  -r      : restart grace period for uid or gid\n");
  fprintf (stderr, "  -R      : raise-only, never lower quotas for uid/gid\n");
  fprintf (stderr, "  -d      : dump quota info in machine readable format (see manpage)\n");
  fprintf (stderr, "  -h      : show this help\n");
  fprintf (stderr, "  -v      : be verbose (twice or thrice for debugging)\n");
  fprintf (stderr, "  -V      : show version\n");
  fprintf (stderr, "  -n      : do nothing (useful with -v)\n");
  fprintf (stderr, "\nSee 'man quotatool' for detailed information\n");
}



/*
 * _output
 * print status messages if we're supposed to
 * FIXME: program name is hard-coded
 */
static inline void _output (int level, const char *format, va_list arglist)
{
  if ( level <= output_level ) {
    fprintf (stderr, "%s: ", PROGNAME);
    vfprintf (stderr, format, arglist);
    fprintf (stderr, "\n");
  }
}

void output_error (const char *format, ...) {
  va_list arglist;
  va_start (arglist, format);
  _output (OUTPUT_ERROR, format, arglist);
  va_end (arglist);
}

void output_info (const char *format, ...) {
  va_list arglist;
  va_start (arglist, format);
  _output (OUTPUT_INFO, format, arglist);
  va_end (arglist);
}

void output_debug (const char *format, ...) {
  va_list arglist;
  va_start (arglist, format);
  _output (OUTPUT_DEBUG, format, arglist);
  va_end (arglist);
}
