# alass, the subtitle aligner Pocket Subtitles falls back to (not in nixpkgs).
{ lib, rustPlatform, fetchCrate, makeWrapper, ffmpeg-headless }:

rustPlatform.buildRustPackage rec {
  pname = "alass-cli";
  version = "2.0.0";
  src = fetchCrate { inherit pname version; hash = "sha256-4RDRKcFVdR+LctPmPxve15IRIl48+KG3ZkU+xfpRLfc="; };
  # The crate ships a version 1 Cargo.lock, which nixpkgs can no longer vendor. alass-Cargo.lock is the
  # same lock in version 3 format: identical packages and versions, checksums moved inline.
  cargoLock.lockFile = ./alass-Cargo.lock;
  postPatch = "cp ${./alass-Cargo.lock} Cargo.lock";
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    wrapProgram $out/bin/alass-cli --set-default ALASS_FFMPEG_PATH ${ffmpeg-headless}/bin/ffmpeg --set-default ALASS_FFPROBE_PATH ${ffmpeg-headless}/bin/ffprobe
  '';
  doCheck = false;
  meta = {
    description = "Automatic language-agnostic subtitle synchronization";
    homepage = "https://github.com/kaegi/alass";
    license = lib.licenses.gpl3Only;
    mainProgram = "alass-cli";
  };
}
