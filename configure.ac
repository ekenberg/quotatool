dnl Process this file with autoconf to produce a configure script.

AC_INIT
AC_CONFIG_SRCDIR([src/main.c])
AC_CONFIG_AUX_DIR(tools)


dnl Main program/version info settings:
dnl ---------------------------------------------------------------------------
MAJOR_VERSION=1
MINOR_VERSION=6
PATCHLEVEL=2
COPYRIGHT_NOTICE="Copyright (c) 1999-2013 Mike Glover / Johan Ekenberg"
WWW_URL="https://github.com/ekenberg/quotatool | http://quotatool.ekenberg.se"

dnl ---------------------------------------------------------------------------

dnl Set program, version info
PROGNAME=quotatool
AC_SUBST(PROGNAME)
AC_DEFINE_UNQUOTED(PROGNAME, "$PROGNAME", [Name of the current program])

AC_SUBST(MAJOR_VERSION)
AC_DEFINE_UNQUOTED(MAJOR_VERSION, $MAJOR_VERSION, [Major version number])

AC_SUBST(MINOR_VERSION)
AC_DEFINE_UNQUOTED(MINOR_VERSION, $MINOR_VERSION, [Minor version number])

AC_SUBST(PATCHLEVEL)
AC_DEFINE_UNQUOTED(PATCHLEVEL, "$PATCHLEVEL", [Patch level version number])

AC_DEFINE_UNQUOTED(COPYRIGHT_NOTICE, "$COPYRIGHT_NOTICE", [Copyright notice])

AC_DEFINE_UNQUOTED(WWW_URL, "$WWW_URL", [Upstream homepage])

dnl get the system type (for the makefile)

AC_CANONICAL_HOST
case [$host] in
  *linux*)
	PLATFORM=linux
	AC_DEFINE(PLATFORM_LINUX, 1, [Is this a Linux platform?])
	;;
  *solaris*)
	PLATFORM=solaris
	AC_DEFINE(PLATFORM_SOLARIS, 1, [Is this a Solaris platform?])
	;;
  *aix*)
	PLATFORM=aix
	AC_DEFINE(PLATFORM_AIX, 1, [Is this an AIX platform?])
	;;
  *freebsd*|*openbsd*|*netbsd*)
	PLATFORM=bsd
	AC_DEFINE(PLATFORM_BSD, 1, [Is this a *BSD platform?])
	;;
  *apple-darwin*)
        PLATFORM=darwin
        AC_DEFINE(PLATFORM_DARWIN, 1, [Is this an OSX platform?])
        ;;
  *)
	PLATFORM=unknown
	AC_DEFINE(PLATFORM_UNKNOWN, 1, [Is this an unknown platform?])
	;;
esac
AC_SUBST(PLATFORM)
AC_DEFINE_UNQUOTED(PLATFORM, $PLATFORM, [Name of the current platform])

dnl Check for programs.

AC_PROG_CC
AC_PROG_INSTALL

dnl Check for absolutely required header files.

AC_HEADER_STDC
AC_CHECK_HEADERS(unistd.h fcntl.h limits.h, ,\
                 AC_MSG_ERROR([Missing required headers]))

dnl Check for pick-one header files (required)

AC_CHECK_HEADERS(mntent.h sys/mnttab.h sys/mntctl.h fstab.h, FOUND_MNT=1;break)
test [$FOUND_MNT] || AC_MSG_ERROR([Can't find getmntent() or getfsent()])

AC_CHECK_HEADERS(linux/types.h sys/types.h, FOUND_TYPES=1;break)
test [$FOUND_TYPES] || AC_MSG_ERROR([Can't find system types])

dnl Check for quota header files except for linux (we ship our own)
if test "$PLATFORM" != "linux"; then
  if test "$PLATFORM" == "darwin"; then
    AC_CHECK_HEADERS(sys/quota.h, FOUND_QUOTA=1;break)
    test [$FOUND_QUOTA] || AC_MSG_ERROR([Can't find quota defs])
  else
    AC_CHECK_HEADERS(sys/fs/ufs_quota.h jfs/quota.h ufs/ufs/quota1.h ufs/ufs/quota.h, FOUND_QUOTA=1;break)
    test [$FOUND_QUOTA] || AC_MSG_ERROR([Can't find quota defs])
  fi
fi

dnl Check for pick-one header files (optional)

AC_CHECK_HEADERS(std.h linux/fs.h, FOUND_BSIZE=1)
test [$FOUND_BSIZE] || AC_MSG_WARN([Using hard-coded default BLOCK_SIZE])

AC_CHECK_HEADERS(inttypes.h)
dnl Check for typedefs, structures, and compiler characteristics.

AC_C_CONST
AC_TYPE_UID_T
AC_C_INLINE
AC_CHECK_TYPE(u_int64_t, HAVE_U_INT64_T=1, HAVE_U_INT64_T=0)
AC_DEFINE_UNQUOTED(HAVE_U_INT64_T, $HAVE_U_INT64_T, [Can we use uint64_t?])

dnl Check for library functions.

AC_FUNC_VPRINTF
AC_CHECK_FUNCS(strdup strerror strtol strtod strchr)
test [x$PLATFORM] = [xlinux] &&  AC_DEFINE(HAVE_GNU_GETOPT, 1, [Can we use GNU getopt?])

dnl check for strlcpy and strlcat (mostly BSD)
AC_CHECK_FUNCS(strlcpy strlcat)

dnl Check the commandline

AC_ARG_WITH(gnu-getopt,  \
  [--with-gnu-getopt       getopt() is GNU getopt],\
            test [x$withval] != [xno] || AC_DEFINE(HAVE_GNU_GETOPT, 1, [Can we use GNU getopt?]))

dnl Create output files

AC_CONFIG_HEADER(src/config.h)
AC_CONFIG_FILES([local.mk])
AC_OUTPUT
