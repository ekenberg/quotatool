#
# Mike Glover
# mpg4@duluoz.net
#
# Makefile for quotatool
#
#


#
# BEGIN setting variables
#


# local configuration options
include ./local.mk


# keep track of our current location
dir        :=   $(srcdir)


# these get built by the included dir.mk's
dirs       :=   .
srcs       :=
libs       :=
inc        :=
auto       :=   $(wildcard $(dir)/*.in)
objs        =   $(srcs:.c=.o)


# look for a dir.mk in these subdirectories
subdirs    :=   src


#
# END   setting variables
# BEGIN including subfiles
#

# include the fragment from each directory
-include $(foreach sdir,$(subdirs),$(dir)/$(sdir)/dir.mk)



#
# END including subfiles
# BEGIN rules
#

# clear out the suffix list and rewrite
.SUFFIXES:
.SUFFIXES: .c .o
.INTERMEDIATE: .d
.PHONY: all clean distclean dist install uninstall


# compile the program (and the objects)
all: $(prog)
$(prog): $(objs)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(prog) $(objs) $(libs)



men   :=   $(wildcard $(srcdir)/man/*)
install: $(prog)
	$(NORMAL_INSTALL)
	$(INSTALL_PROGRAM) $(srcdir)/$(prog) $(DESTDIR)$(sbindir)/$(prog)
	$(foreach man,$(men),$(INSTALL_DATA) $(man) $(DESTDIR)$(mandir)/man$(subst .,,$(suffix $(man)))/$(notdir $(man)))

uninstall:
	$(NORMAL_UNINSTALL)
	rm -f $(bindir)/$(prog)
	rm -f $(foreach man,$(notdir $(men)), $(mandir)/$(man))


distdir    :=   $(package)-$(version)
dist: distclean
	mkdir ./.$(distdir)
	cp -fR $(srcdir)/* ./.$(distdir) || true
	rm -rf ./.$(distdir)/*johan*
	rm -rf ./.$(distdir)/FILESYSTEMS
	mv ./.$(distdir) ./$(distdir)
	tar -zcvf ./$(distdir).tar.gz $(distdir)
	rm -rf ./$(distdir)


cfixes     :=   ~ .o
clean:
	rm -f $(foreach sfix,$(cfixes),$(addsuffix /*$(sfix),$(dirs)))
	rm -f $(addsuffix /core,$(dirs))
	rm -f $(prog)
	rm -f $(foreach sfix,$(cfixes),$(addsuffix /*$(sfix),$(DESTDIR)$(srcdir)/man))
	rm -f $(foreach sfix,$(cfixes),$(addsuffix /*$(sfix),$(DESTDIR)$(srcdir)/tools))


dcfixes    :=   .d
distclean: clean
	rm -f $(foreach sfix,$(dcfixes),$(addsuffix /*$(sfix),$(dirs)))
	rm -f $(filter-out %/configure,$(auto:.in=))
	rm -f $(srcdir)/config.*
	rm -rf ./$(distdir) ./*.tar.gz


# include object dependencies
-include $(objs:.o=.d)


#
# END   rules
# BEGIN pattern rules
#



# create dependencies automatically from .c files
%.d: %.c
	$(srcdir)/tools/depend.sh $(CPPFLAGS) $< > $@


# create shared library from a collection of object
%.so:
	$(CC) -shared -Xlinker -x -o $@ $^ $(libs)

