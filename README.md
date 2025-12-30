# Proton Updater

Script to update the Proton desktop apps on a debian based system (e.g. Linux Mint)

* Proton Mail
* Proton Pass

## Usage

On a shell terminal, call the script with the appropriate action subcommand.

* `update-proton pass` for the Proton Pass App
* `update-proton mail` for the Proton Mail App

Use `update-proton --help` or `update-proton -h` to show the usage page.

## Install

Unzip the release zip file and run `make install`.

```bash
# replace x.y.z with the correct version
unzip proton-updater-x.y.z
cd proton-updater-x.y.z
make install
```

This will install executable copies without the .sh extension in your `~/.local/bin` directory.

## Uninstall / Remove

To remove, just issue the `make uninstall` command. This will remove the copies in ~/.local/bin.
