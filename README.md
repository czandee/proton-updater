# Proton Updater

Script to update the Proton desktop apps on a Debian-based system (e.g. Linux Mint).

Supported packages:

* Proton Mail
* Proton Pass
* Proton Pass CLI (standalone binary)

## Usage

Call the script with the appropriate subcommand:

* `update-proton pass` to update the Proton Pass desktop app
* `update-proton mail` to update the Proton Mail desktop app
* `update-proton cli` to update the Proton Pass CLI binary

Use `update-proton -h` for the full list of options.

## Install / Uninstall using the installer script

```bash
# install latest version
curl -sSL https://raw.githubusercontent.com/czandee/proton-updater/main/install.sh | bash

# install a specific version
curl -sSL https://raw.githubusercontent.com/czandee/proton-updater/main/install.sh | bash -s -- v1.0.2

# uninstall
curl -sSL https://raw.githubusercontent.com/czandee/proton-updater/main/install.sh | bash -s -- --uninstall
```

## Install / Uninstall using the makefile

Clone the repository or download and unzip a release archive, then run `make install` or
`make uninstall`:

```bash
# replace x.y.z with the correct version
unzip proton-updater-x.y.z
cd proton-updater-x.y.z
make install  # or 'make uninstall' to remove
```

Installs executable copies (without the `.sh` extension) to `~/.local/bin`. Run `make uninstall`
in the same directory to remove them.
