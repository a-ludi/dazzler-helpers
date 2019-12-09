BINARIES=BAM2DB DBln GenBank2DAM damapper.slurm daligner.slurm
SOURCE=source
BUILD=build
BUILDBIN=$(BUILD)/bin

prefix=/usr/local
exec_prefix=$(prefix)
bindir=$(exec_prefix)/bin

INSTALL=install
INSTALL_PROGRAM=$(INSTALL)


.PHONY: all
all: $(addprefix $(BUILDBIN)/, $(BINARIES))


$(BUILDBIN)/%: $(SOURCE)/%.sh | $(BUILDBIN)
	ln -s $(realpath $<) $@


.PHONY: all
install:
	if [[ "-$$(echo $(BUILDBIN)/*)" =~ \*$$ ]]; then \
	    echo 'no targets have bin created; run `make` first'; \
	else \
	    $(INSTALL_PROGRAM) -t $(bindir) $(BUILDBIN)/*; \
	fi


$(BUILD) $(BUILDBIN):
	mkdir -p $@


.PHONY: clean
clean:
	rm -rf $(BUILD)
