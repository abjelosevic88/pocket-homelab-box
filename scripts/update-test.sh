#!/usr/bin/env bash
# Updates with rollback on the box scripts/install-test.sh installed (run that first): a good
# release must install, a broken one must be rolled back, and then skipped.
set -euo pipefail
cd "$(dirname "$0")/.."
ovmf=$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#OVMF.fd)
qemu=$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#qemu_kvm)
SWTPM=$(nix build --no-link --print-out-paths --inputs-from . "nixpkgs#swtpm^out")/bin/swtpm
export SWTPM
exec python3 -I scripts/update-test.py "$ovmf" "$qemu" "$PWD/.installtest"
