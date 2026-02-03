# Proton Updater

Script to update the Proton desktop apps on a debian based system (e.g. Linux Mint)

* Proton Mail
* Proton Pass

## Usage

On a shell terminal, call the script with the appropriate action subcommand.

* `update-proton pass` for the Proton Pass App
* `update-proton mail` for the Proton Mail App

Use `update-proton --help` or `update-proton -h` to show the usage page.

## Install/Uninstall using the installer script

```bash
# install latest version
curl -sSL https://raw.githubusercontent.com/czandee/proton-updater/main/install.sh | bash

# install specific version, e.g. if you need an older version
curl -sSL https://raw.githubusercontent.com/czandee/proton-updater/main/install.sh | bash -s -- v1.0.2

# uninstall current version
url -sSL https://raw.githubusercontent.com/czandee/proton-updater/main/install.sh | bash -s -- --uninstall
```

## Install/Uninstall using the makefile

Either clone the repository or download and unzip the release zip file and run `make install` or `make uninstall`.

```bash
# replace x.y.z with the correct version
unzip proton-updater-x.y.z
cd proton-updater-x.y.z
make install  # or 'make uninstall' to remove
```

This will install executable copies without the .sh extension in your `~/.local/bin` directory. To remove the copies in ~/.local/bin, run `make uninstall` in the proton-updater-x.y.z directory.
