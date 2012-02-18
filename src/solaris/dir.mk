#
# Makefile fragment for src/solaris
#

thisdir    :=   solaris

svdir      :=   $(dir)
dir        :=   $(dir)/$(thisdir)

dirs       +=   $(dir) 
auto       +=   $(wildcard $(dir)/*.in)

ifeq "$(build_platform)" "$(thisdir)"
srcs       +=   $(wildcard $(dir)/*.c)
inc        +=   -I$(dir)
libs       +=   
subdirs    :=   

ifneq ($(strip $(subdirs)),)
-include $(foreach sdir,$(subdirs),$(dir)/$(sdir)/dir.mk)
endif

endif

dir        :=   $(svdir)
