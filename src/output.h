/*
 * Mike Glover
 * mpg4@duluoz.net
 *
 * Johan Ekenberg
 * johan@ekenberg.se
 *
 * output.h
 * talk to the nice people
 */
#ifndef INCLUDE_QUOTATOOL_OUTPUT
#define INCLUDE_QUOTATOOL_OUTPUT 1

#include <config.h>

#include <stdarg.h>

extern int output_level;

void   output_version (void);
void   output_help (void);

void   output_debug (const char *format, ...);
void   output_info (const char *format, ...);
void   output_error (const char *format, ...);

#endif /* INCLUDE_QUOTATOOL_OUTPUT */
