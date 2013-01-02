/*
 * quotatool.h
 * system-wide definitions
 */

#ifndef INCLUDE_QUOTATOOL
#define INCLUDE_QUOTATOOL 1

#include <config.h>

/* error codes */
#define ERR_PARSE 1
#define ERR_ARG   2
#define ERR_SYS   3
#define ERR_MEM   4

#if HAVE_U_INT64_T == 0
typedef unsigned long long int u_int64_t;
#endif

/* check for BSD variants */
#define ANY_BSD (__FreeBSD__ || __FreeBSD_kernel__ || __OpenBSD__ || __NetBSD__)

#endif /* INCLUDE_QUOTATOOL */
