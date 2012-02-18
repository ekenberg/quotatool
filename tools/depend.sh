#!/bin/sh
#
# depend.sh
# Generated automatically from depend.sh.in by configure.

set -e
gcc -MM $* | sed 's#\($*\)\.o[ :]*#\1.o $@ : #g'
