# makefile for the update-proton script
# The installation process will link or copy (depending on the MODE)
# the script without the .sh extension into a globally accessible bin
# directory and make the script executable.

# configuration
SRC_DIR  := $(CURDIR)
BIN_DIR  := $(HOME)/.local/bin
# mode can be symlink or copy
MODE ?= copy

# sources: list of scripts to process in this folder
SOURCES  := $(wildcard *.sh)

# binaries: strip path and extension
TARGETS  := $(patsubst %.sh, $(BIN_DIR)/%, $(notdir $(SOURCES)))

.PHONY: all install uninstall check-path

all: install check-path

install: $(BIN_DIR) $(TARGETS)
	@echo "Installation complete: Binaries in $(BIN_DIR)"

# ensure target directories exist
$(BIN_DIR):
	mkdir -p $@

# rule for binaries (executable, no extension)
# note: $< source, $@ target
$(BIN_DIR)/%: $(SRC_DIR)/%.sh
	@if [ "$(MODE)" = "symlink" ]; then \
		ln -sf $< $@; \
		echo "Linked: $(notdir $<) -> $@"; \
	elif [ "$(MODE)" = "copy" ]; then \
		cp $< $@; \
		echo "Copied: $(notdir $<) -> $@"; \
	else \
		echo "Error: Unknown MODE='$(MODE)'."; exit 1; \
	fi
	@chmod +x $@

# rule to check if the BIN_DIR is in the system path
check-path:
	@case ":$(PATH):" in \
		*":$(BIN_DIR):"*) ;; \
		*) echo "WARNING: $(BIN_DIR) is not in your PATH. Add 'export PATH=\"\$$HOME/.local/bin:\$$PATH\"' to your .bashrc";; \
	esac

# rule to uninstall, in case of symlinks the executable flag on the source
# file is removed again
uninstall:
	@for target in $(TARGETS); do \
		if [ -L "$$target" ]; then \
			SRC_FILE=$$(readlink -f "$$target"); \
			chmod -x "$$SRC_FILE" 2>/dev/null || true; \
			echo "chmod -x on: $$SRC_FILE"; \
		fi; \
		rm -f "$$target"; \
	done
	@echo "Uninstallation from $(BIN_DIR) complete."

# clean as a synonym for uninstall
clean: uninstall

# tests for ci/cd pipeline
check:
	update-proton -h