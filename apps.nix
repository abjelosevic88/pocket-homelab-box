# The Pocket apps that ship on the box.
#
# Every entry builds one Go binary with its React UI embedded (see lib/mkPocketApp.nix) and runs as
# one systemd service (see modules/box.nix). `input` names the flake input that pins the source,
# `version` is what the app's version pill shows. Optional per app:
#   runtime       pkgs -> tools put on the app's PATH
#   wrap          pkgs -> extra makeWrapper arguments ($out is the app's own store path)
#   postInstall   shell run after the build, in the source tree
#   environment   extra variables on the box
#   root          run as root instead of a dynamic user
#   capabilities  ambient capabilities
#   media         "ro" or "rw": access to /srv/media
#
# After `nix flake update <input>` bump `version`, set the changed hash to `lib.fakeHash`, run
# `nix build .#<slug>` and paste the hash from the error.
{ lib }:

let
  # Tesseract languages for Pocket Documents.
  ocrLanguages = [ "eng" "deu" "fra" "ita" "spa" "nld" "por" "hrv" "srp" "srp_latn" "slv" "pol" "ces" "hun" "ron" "osd" ];
in
{
  core = {
    title = "Pocket Core";
    pname = "pocket-core";
    input = "pocket-core";
    version = "0.22.0";
    port = 8179;
    vendorHash = "sha256-/QD+e39BeO06DdNx166/FcRLQeA9j8EJSwpkEl/Tbdc=";
    npmDepsHash = "sha256-B6hwAJzFxJG6iSPCb/vrsQrF8lzORM95hK7vslmlGm0=";
  };

  ai = {
    title = "Pocket AI";
    pname = "pocket-ai";
    input = "pocket-ai";
    version = "0.22.8";
    port = 8195;
    vendorHash = "sha256-6g5wONZ4vrl1eyPakgacCtrfbtdvf7aBBSlLl/gezbs=";
    npmDepsHash = "sha256-PUK9D/bqTUPuylyudwfL7i50c+R7aiqW2TO95/oeTmk=";
    # Front-end for coding agents. Codex ships on the box; Claude Code is unfree, so add it yourself.
    # bubblewrap: everyone but the owner runs in a jail in their own folder (modules/ai-sandbox.nix).
    runtime = pkgs: with pkgs; [ git codex bash coreutils findutils gnugrep gnused bubblewrap ];
    environment = { ROOTS = "/var/lib/pocket-ai/projects"; };
  };

  audiobooks = {
    title = "Pocket Audiobooks";
    pname = "pocket-audiobooks";
    input = "pocket-audiobooks";
    version = "1.4.2";
    port = 8202;
    vendorHash = "sha256-AxiIlCSMUVHGBYsnEKp35DyUBbrjOmt/EgEY6K05IEU=";
    npmDepsHash = "sha256-FWB5O5jpbIRRn3J+CfeaWItBczYDU1SjNuKMebO9/jg=";
    runtime = pkgs: [ pkgs.ffmpeg-headless ];
    media = "rw";
  };

  backups = {
    title = "Pocket Backups";
    pname = "pocket-backups";
    input = "pocket-backups";
    version = "0.2.1";
    port = 8203;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-DI6E1+kxNnZUlzVq9GoiiE762aaX6wvXztJ7BZXAU/U=";
    # Backs up the whole box, so it runs as root and can read everything.
    runtime = pkgs: with pkgs; [ restic rclone openssh util-linux gnutar ];
    environment = { DEV_DISK_DIR = "/dev/disk"; };
    root = true;
  };

  bookshelf = {
    title = "Pocket Bookshelf";
    pname = "pocket-bookshelf";
    input = "pocket-bookshelf";
    version = "0.16.5";
    port = 8171;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-nyncRXsUGd/hCH8BZiwtuZW96JkbPUSIfcqUosMx/sI=";
  };

  calendar = {
    title = "Pocket Calendar";
    pname = "pocket-calendar";
    input = "pocket-calendar";
    version = "0.5.2";
    port = 8190;
    vendorHash = "sha256-1wpEEUBtUVTVyjYHga9x4N0A+uRfz3RcOPIaYhP0ap4=";
    npmDepsHash = "sha256-1z9sg27zun7MmuqajpA5zCRCgh++G/vjIC+cLvU4an4=";
  };

  clips = {
    title = "Pocket Clips";
    pname = "pocket-clips";
    input = "pocket-clips";
    version = "0.2.2";
    port = 8173;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-aCGqXFSiwCigsz4TbQKMSoyHn1vrk/d/RjCc2lnX2lI=";
  };

  contacts = {
    title = "Pocket Contacts";
    pname = "pocket-contacts";
    input = "pocket-contacts";
    version = "0.2.1";
    port = 8191;
    vendorHash = "sha256-Yyl3Ok8RserzSVw7NC7Sa8MpjKBSk13Ptl3b3BzvPRs=";
    npmDepsHash = "sha256-ftYKsNBA4mWf3tCEYocLfSQ3vnJUH2C5kgtJ/yiLMcw=";
  };

  database = {
    title = "Pocket Database";
    pname = "pocket-database";
    input = "pocket-database";
    version = "0.1.1";
    port = 8209;
    vendorHash = "sha256-mWx//NdtuLWdoO2T6UPKnDzNWfHEWqjG+cuTSpVWsuQ=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
    # Opens the SQLite databases of every app on the box, so it runs as root.
    environment = { SCAN_PATHS = "/var/lib"; };
    root = true;
  };

  day = {
    title = "Pocket Day";
    pname = "pocket-day";
    input = "pocket-day";
    version = "0.15.1";
    port = 8177;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-07TBbsJyyXCVTdl+037o3Uop2Be/yswTrRL/PDF92v8=";
  };

  documents = {
    title = "Pocket Documents";
    pname = "pocket-documents";
    input = "pocket-documents";
    version = "0.5.3";
    port = 8183;
    vendorHash = "sha256-euD5qQVU7yKaEsZNa4YMFJZ/h5Bnl4x08lTq57A6zso=";
    npmDepsHash = "sha256-bAN4gWs7NUhmkC9leL3IqSIHxMIEORJnftivZ+g/8rk=";
    runtime = pkgs: with pkgs; [
      (ocrmypdf.override { tesseract = tesseract.override { enableLanguages = ocrLanguages; }; })
      (tesseract.override { enableLanguages = ocrLanguages; })
      ghostscript qpdf poppler-utils unpaper pngquant jbig2enc zbar
    ];
  };

  files = {
    title = "Pocket Files";
    pname = "pocket-files";
    input = "pocket-files";
    version = "0.4.3";
    port = 8187;
    vendorHash = "sha256-lXzRylGWMVyqHRwPnELyaj0H0Fi4lT067M+TJCg5UuI=";
    npmDepsHash = "sha256-3X9Vyi6iZSLpDVksIdv2YEZBP4hzRGW53eTY+jQdtvY=";
  };

  garage = {
    title = "Pocket Garage";
    pname = "pocket-garage";
    input = "pocket-garage";
    version = "0.11.1";
    port = 8175;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-m+QgxtEuG6iM2JSUYFspoAiyZGtS/0jm/LCWVGHarlQ=";
  };

  habits = {
    title = "Pocket Habits";
    pname = "pocket-habits";
    input = "pocket-habits";
    version = "0.4.3";
    port = 8169;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-dPXEr/BzsmcLbICFgR3hHiG1/dOZ5WQmyfEMUviyUCw=";
  };

  health = {
    title = "Pocket Health";
    pname = "pocket-health";
    input = "pocket-health";
    version = "0.2.2";
    port = 8199;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-3PqYDUqWiVuCtIewmMp/Zhx3aK1d+Sn+hkoPgkLY1fA=";
  };

  hub = {
    title = "Pocket Hub";
    pname = "pocket-hub";
    input = "pocket-hub";
    version = "0.6.1";
    port = 8185;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-QBq7YjC5hiKoyyXKvTq1sEh3dvqwpoV3i+1WmKIOD4Q=";
  };

  inventory = {
    title = "Pocket Inventory";
    pname = "pocket-inventory";
    input = "pocket-inventory";
    version = "0.5.2";
    port = 8170;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-MqAvJAruVISFR0z9ZqXpBVamIfykdx4cWMwpOeH9xPg=";
  };

  invoicing = {
    title = "Pocket Invoicing";
    pname = "pocket-invoicing";
    input = "pocket-invoicing";
    version = "0.11.1";
    port = 8168;
    vendorHash = "sha256-XDAJARRpTUBRY4PhsJoiz0LRWRm9kO5zMNeiu0BEQCY=";
    npmDepsHash = "sha256-B6jZTFFZUl2SQQpGHEXkm0Fk4L2LlnyS1DZ56XRaU+Y=";
  };

  kitchen = {
    title = "Pocket Kitchen";
    pname = "pocket-kitchen";
    input = "pocket-kitchen";
    version = "0.5.2";
    port = 8176;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-V/EgsjDw9Ljmn1icnZmpjn/9WeSDzmMN98aBsX8lnig=";
  };

  library = {
    title = "Pocket Library";
    pname = "pocket-library";
    input = "pocket-library";
    version = "0.1.1";
    port = 8204;
    vendorHash = "sha256-lWyJoSwFe/tai0GsxUMyUDVZjxk5zB+fhZFpr8aySE4=";
    npmDepsHash = "sha256-k/2TkoQOojzn2iKlZ+Fw/4fzq3TxAnmZ2HLhPyjH7ns=";
    runtime = pkgs: [ pkgs.poppler-utils ];
    media = "rw";
  };

  mail = {
    title = "Pocket Mail";
    pname = "pocket-mail";
    input = "pocket-mail";
    version = "0.1.1";
    port = 8208;
    vendorHash = "sha256-kZcQ59gr0qjv7s+vIPRqjGvTRIYceZUvVAzPxEN620s=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  money = {
    title = "Pocket Money";
    pname = "pocket-money";
    input = "pocket-money";
    version = "0.14.3";
    port = 8178;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-awNiiTvNpyDytlZ4g+VNpztQhCgtgElyoNui1QrLMXk=";
  };

  monitoring = {
    title = "Pocket Monitoring";
    pname = "pocket-monitoring";
    input = "pocket-monitoring";
    version = "0.2.1";
    port = 8192;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-driQt07Y6kd8nLbd/gHQ5FHbVj9c+WFaHrlLg7ORgxk=";
    environment = { LOCAL_NAME = "Pocket Box"; };
  };

  movement = {
    title = "Pocket Movement";
    pname = "pocket-movement";
    input = "pocket-movement";
    version = "0.3.2";
    port = 8197;
    vendorHash = "sha256-Lq9WpVSSyiPx5jCT5I0P5gpmIHmkh7qpGjQBxjPnVS4=";
    npmDepsHash = "sha256-1DgCVRSoFk8jcO5i+NgPIs5R1wfGFKaUnKd5BbexmhI=";
  };

  music = {
    title = "Pocket Music";
    pname = "pocket-music";
    input = "pocket-music";
    version = "0.4.1";
    port = 8200;
    vendorHash = "sha256-3ewpn5k2ClrFX52OAjtwisnof4fzjTOQHapPYBz6OlI=";
    npmDepsHash = "sha256-ZRQ75xHYUhYmBsS6/mR635qNTdXgdpDMKQiHuzOy3nU=";
    environment = { MUSIC_DIR = "/srv/media/music"; };
    media = "rw";
  };

  network = {
    title = "Pocket Network";
    pname = "pocket-network";
    input = "pocket-network";
    version = "0.1.1";
    port = 8207;
    vendorHash = "sha256-gGmR1w6QzMcoPX2jRFLqLDIamJIoE1BZIPdzfGiI+lY=";
    npmDepsHash = "sha256-aglaIpqKG+jRJO7F8YXnk4bBl/lU7WJx1xRZviIVR1s=";
    # Pings and ARP scans the LAN.
    capabilities = [ "CAP_NET_RAW" ];
  };

  notes = {
    title = "Pocket Notes";
    pname = "pocket-notes";
    input = "pocket-notes";
    version = "0.7.4";
    port = 8182;
    vendorHash = "sha256-UM7ZCv25k1FfOl04WsQnyY47YZQVIjJIXGAYWcj5RZM=";
    npmDepsHash = "sha256-/5yuEn1YUPoCpoqPQO6hr967U6I7PhjDU4QXEu+IH6Y=";
  };

  office = {
    title = "Pocket Office";
    pname = "pocket-office";
    input = "pocket-office";
    version = "0.6.3";
    port = 8186;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-v0tDTefOAPNSPoLor4IbNyZ/ysTJC//4v+PHne1tjoI=";
  };

  photos = {
    title = "Pocket Photos";
    pname = "pocket-photos";
    input = "pocket-photos";
    version = "0.4.0";
    port = 8194;
    vendorHash = "sha256-2l4xE/U9dbbUNL9ANgr4iszIt7CPGojCAqV6yrFQOlY=";
    npmDepsHash = "sha256-rM3J3T1WLldCd4Iqw3ZmhtErzFkIob0/CwIu1tC8uJo=";
    runtime = pkgs: [ pkgs.ffmpeg-headless ];
  };

  podcasts = {
    title = "Pocket Podcasts";
    pname = "pocket-podcasts";
    input = "pocket-podcasts";
    version = "0.4.2";
    port = 8181;
    vendorHash = "sha256-/aYsGz8D+sXJ8LvrJWIKAgMCVIbN/C86I86Scrir7ZA=";
    npmDepsHash = "sha256-nyncRXsUGd/hCH8BZiwtuZW96JkbPUSIfcqUosMx/sI=";
    runtime = pkgs: with pkgs; [ ffmpeg-headless yt-dlp deno ];
  };

  projects = {
    title = "Pocket Projects";
    pname = "pocket-projects";
    input = "pocket-projects";
    version = "0.15.0";
    port = 8196;
    vendorHash = "sha256-6g5wONZ4vrl1eyPakgacCtrfbtdvf7aBBSlLl/gezbs=";
    npmDepsHash = "sha256-Jd1WgUWEe7ZLmRLzrBVrHSvbqFDnZiLSOqVvA7v5/1w=";
  };

  review = {
    title = "Pocket Review";
    pname = "pocket-review";
    input = "pocket-review";
    version = "0.4.0";
    port = 8180;
    vendorHash = "sha256-fTd/wIwUt/17EZsOvQ6eur1HaEF4hsrsiav0tsX3a/k=";
    npmDepsHash = "sha256-R4VBjT/PtdtzLzOrxaY63Fg3qlIMO2qbjbxWTibAaY8=";
  };

  split = {
    title = "Pocket Split";
    pname = "pocket-split";
    input = "pocket-split";
    version = "0.7.0";
    port = 8172;
    vendorHash = "sha256-NAkS3wnN14V7t5vyEAyFrdfxcZROSHOEWZBlkq4h10I=";
    npmDepsHash = "sha256-xPq4EltB1pyx8Lm9g0/PRsVqqwriA6IKNZ7ce4jkD/w=";
  };

  still = {
    title = "Pocket Still";
    pname = "pocket-still";
    input = "pocket-still";
    version = "0.1.1";
    port = 8206;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  subtitles = {
    title = "Pocket Subtitles";
    pname = "pocket-subtitles";
    input = "pocket-subtitles";
    version = "0.5.1";
    port = 8150;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-b9OsPqiaKxmcwM8VU5h5HOnJ5YDur7SqL3/afdtrXhk=";
    runtime = pkgs: [ pkgs.ffmpeg-headless ];
    wrap = pkgs: [
      "--set-default ENGINE_SCRIPT $out/share/pocket-subtitles/engine/pocket_sync.py"
      "--set-default ENGINE_PYTHON ${pkgs.python3.withPackages (ps: [ (ps.toPythonModule pkgs.ffsubsync) ps.numpy ps.webrtcvad ])}/bin/python3"
      "--set-default ALASS_BIN ${pkgs.callPackage ./lib/alass.nix { }}/bin/alass-cli"
    ];
    postInstall = "mkdir -p $out/share/pocket-subtitles && cp -r engine $out/share/pocket-subtitles/";
    environment = { MEDIA_DIRS = "/srv/media"; };
    media = "rw";
  };

  tasks = {
    title = "Pocket Tasks";
    pname = "pocket-tasks";
    input = "pocket-tasks";
    version = "0.3.2";
    port = 8184;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-Jd1WgUWEe7ZLmRLzrBVrHSvbqFDnZiLSOqVvA7v5/1w=";
  };

  travel = {
    title = "Pocket Travel";
    pname = "pocket-travel";
    input = "pocket-travel";
    version = "0.10.1";
    port = 8174;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-1DgCVRSoFk8jcO5i+NgPIs5R1wfGFKaUnKd5BbexmhI=";
  };

  watch = {
    title = "Pocket Watch";
    pname = "pocket-watch";
    input = "pocket-watch";
    version = "0.4.1";
    port = 8201;
    vendorHash = "sha256-5t6xTN2Ck2RHfOV4+otOwXkR11Rzj7mhNcig+mLAJmM=";
    npmDepsHash = "sha256-iJULF2fqzlRKJ7Q88yR2fb9L/GH5stsYJx0GYsm/RyI=";
  };

  wishlist = {
    title = "Pocket Wishlist";
    pname = "pocket-wishlist";
    input = "pocket-wishlist";
    version = "0.3.1";
    port = 8198;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-EEYlm98eERnnG8qrW9GRBSLNQKvpXlNdFd76LjLsWrY=";
  };
}
