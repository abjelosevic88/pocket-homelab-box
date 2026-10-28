#!/usr/bin/env bash
# End-to-end check of the installer: builds the ISO, installs it onto a blank virtual disk over the
# serial console, boots that disk and checks every app's /healthz on host ports +10000.
#   scripts/install-test.sh            full run (wipes .installtest/)
#   BOOT_ONLY=1 scripts/install-test.sh   boot the last installed disk again
#   TPM=0 scripts/install-test.sh         a PC without a TPM: plain disk (default: a software TPM, encrypted)
set -euo pipefail
cd "$(dirname "$0")/.."
iso=$(nix build --no-link --print-out-paths .#iso)/iso/pocket-box-installer.iso
ovmf=$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#OVMF.fd)
qemu=$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#qemu_kvm)
SWTPM=$(nix build --no-link --print-out-paths --inputs-from . "nixpkgs#swtpm^out")/bin/swtpm
export SWTPM
exec python3 -I scripts/install-test.py "$iso" "$ovmf" "$qemu" "$PWD/.installtest"
