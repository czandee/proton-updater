# makefile for the update-proton script
# The installation process will link or copy (depending on the MODE)
# the script without the .sh extension into a globally accessible bin
# directory and make the script executable.

# configuration
SRC_DIR  := $(CURDIR)
PREFIX   ?= $(HOME)/.local
BIN_DIR  := $(PREFIX)/bin
# mode can be symlink or copy
MODE ?= copy

# validate MODE to prevent shell injection and ensure correct usage
ifeq ($(filter $(MODE),symlink copy),)
$(error Invalid MODE '$(MODE)'. Must be 'symlink' or 'copy')
endif

# sources: list of scripts to process in this folder
SOURCES  := $(filter-out install.sh, $(wildcard *.sh))

# binaries: strip path and extension
TARGETS  := $(patsubst %.sh, $(BIN_DIR)/%, $(notdir $(SOURCES)))

.PHONY: all install uninstall check-path clean check

all: install check-path

install: $(BIN_DIR) $(TARGETS)
	@echo "Installation complete: Binaries in $(BIN_DIR)"

# ensure target directory exists
$(BIN_DIR):
	mkdir -p "$@" || { echo "Error: Failed to create $(BIN_DIR)"; exit 1; }

# rule for binaries (executable, no extension)
# note: $< source, $@ target
$(BIN_DIR)/%: $(SRC_DIR)/%.sh | $(BIN_DIR)
	@set -e; \
	if [ "$(MODE)" = "symlink" ]; then \
		ln -snf "$(abspath $<)" "$@"; \
		echo "Linked: $(notdir $<) -> $@"; \
	else \
		install -m 755 "$<" "$@"; \
		echo "Installed: $(notdir $<) -> $@"; \
	fi

# rule to check if the BIN_DIR is in the system path
check-path:
	@case ":$(PATH):" in \
		*":$(BIN_DIR):"*) ;; \
		*) echo "WARNING: $(BIN_DIR) is not in your PATH. Add 'export PATH="$(BIN_DIR):$$PATH"' to your .bashrc";; \
	esac

# rule to uninstall
uninstall:
	@rm -f $(TARGETS)
	@echo "Uninstallation from $(BIN_DIR) complete."

# rule for cleanup
clean:
	@echo "Cleanup complete."

# tests for ci/cd pipeline
check:
	./update-proton.sh -h
