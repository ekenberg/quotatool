#
# Makefile fragment for src/darwin
#

thisdir    :=   darwin

svdir      :=   $(dir)
dir        :=   $(dir)/darwin

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
