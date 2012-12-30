#
# Makefile fragment for src
#

svdir      :=   $(dir)
dir        :=   $(dir)/src

dirs       +=   $(dir) 
srcs       +=   $(wildcard $(dir)/*.c)
inc        +=   -I$(dir)
auto       +=   $(wildcard $(dir)/*.in)
libs       +=   

subdirs    :=   linux solaris aix freebsd

ifneq ($(strip $(subdirs)),)
-include $(foreach sdir,$(subdirs),$(dir)/$(sdir)/dir.mk)
endif

dir        :=   $(svdir)



