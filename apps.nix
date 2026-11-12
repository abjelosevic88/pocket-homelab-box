# The Pocket apps that ship on the box.
#
# Every entry builds one Go binary with its React UI embedded (see lib/mkPocketApp.nix) and runs as
# one systemd service (see modules/box.nix). `input` names the flake input that pins the source,
# `version` is what the app's version pill shows. Optional per app:
#   runtime       pkgs -> tools put on the app's PATH
#   wrap          pkgs -> extra makeWrapper arguments ($out is the app's own store path)
#   postInstall   shell run after the build, in the source tree
#   npmFlags      extra npm flags for the UI build (e.g. --legacy-peer-deps)
#   environment   extra variables on the box
#   root          run as root instead of a dynamic user
#   capabilities  ambient capabilities
#   media         "ro" or "rw": access to /srv/media
#
# After `nix flake update <input>` bump `version`, set the changed hash to `lib.fakeHash`, run
# `nix build .#<slug>` and paste the hash from the error.
{ lib }:

let
  # Tesseract languages for Pocket Documents and Pocket Translate.
  ocrLanguages = [ "eng" "deu" "fra" "ita" "spa" "nld" "por" "hrv" "srp" "srp_latn" "slv" "pol" "ces" "hun" "ron" "osd" ];
in
{
  core = {
    title = "Pocket Core";
    pname = "pocket-core";
    input = "pocket-core";
    version = "0.37.11";
    port = 8179;
    vendorHash = "sha256-AmQl4eumT1+KUEk3jsBDJpAV1h2efmwUL+gcfg4IrIE=";
    npmDepsHash = "sha256-B6hwAJzFxJG6iSPCb/vrsQrF8lzORM95hK7vslmlGm0=";
  };

  ai = {
    title = "Pocket AI";
    pname = "pocket-ai";
    input = "pocket-ai";
    version = "0.94.1";
    port = 8195;
    vendorHash = "sha256-st3Jp8Qh9ZGI32Tsg1EVT0bZBu6tDtYHnLhAhvI/aMM=";
    npmDepsHash = "sha256-Ec6TFzNOyDaPrpcaUpLi5OMusbth/qK3LLDEE+V92jw=";
    # Front-end for coding agents. Codex ships on the box; Claude Code is unfree, so add it yourself.
    # bubblewrap: everyone but the owner runs in a jail in their own folder (modules/ai-sandbox.nix).
    runtime = pkgs: with pkgs; [ git codex bash coreutils findutils gnugrep gnused bubblewrap ];
    environment = { ROOTS = "/var/lib/pocket-ai/projects"; };
  };

  alerts = {
    title = "Pocket Alerts";
    pname = "pocket-alerts";
    input = "pocket-alerts";
    version = "0.2.1";
    port = 8217;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-AzYQcVW6vaXzAYwgmfjaUJjjslwFHpUjiPxeDlc1J2Y=";
  };

  audiobooks = {
    title = "Pocket Audiobooks";
    pname = "pocket-audiobooks";
    input = "pocket-audiobooks";
    version = "1.6.1";
    port = 8202;
    vendorHash = "sha256-AxiIlCSMUVHGBYsnEKp35DyUBbrjOmt/EgEY6K05IEU=";
    npmDepsHash = "sha256-4ZkfBQ/FoyLt13Z1DSzSE3gi5L1wzC/rKh755CrJSag=";
    runtime = pkgs: [ pkgs.ffmpeg-headless ];
    media = "rw";
  };

  backups = {
    title = "Pocket Backups";
    pname = "pocket-backups";
    input = "pocket-backups";
    version = "0.3.1";
    port = 8203;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-DI6E1+kxNnZUlzVq9GoiiE762aaX6wvXztJ7BZXAU/U=";
    # Backs up the whole box, so it runs as root and can read everything.
    runtime = pkgs: with pkgs; [ restic rclone openssh util-linux gnutar ];
    environment = { DEV_DISK_DIR = "/dev/disk"; };
    root = true;
  };

  blog = {
    title = "Pocket Blog";
    pname = "pocket-blog";
    input = "pocket-blog";
    version = "0.1.2";
    port = 8246;
    vendorHash = "sha256-a4N9rP1jppK7EvBgNk5Ag/9jzdYIA+i3uVMvHppSNqc=";
    npmDepsHash = "sha256-NtSPzI1S++tsQnKUYTC1snpfLQyio8U4+7eXe/ObEE0=";
  };

  blueprint = {
    title = "Pocket Blueprint";
    pname = "pocket-blueprint";
    input = "pocket-blueprint";
    version = "0.2.0";
    port = 8222;
    # Reads git history of the repositories it inspects.
    runtime = pkgs: [ pkgs.git ];
    vendorHash = "sha256-VZ+rETACqyxsozLowPmLTj8GUcQqvWQUfxSZZ37uxZc=";
    npmDepsHash = "sha256-xddyerXbIl/9namq/mwAMmc59hu79Bq5/Iw3Rl3YdYI=";
  };

  boards = {
    title = "Pocket Boards";
    pname = "pocket-boards";
    input = "pocket-boards";
    version = "0.1.3";
    port = 8223;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-FGjpcDpJH73C5O7i85sSuLfwvhq6kE7U16vrJiF2XJM=";
  };

  bookshelf = {
    title = "Pocket Bookshelf";
    pname = "pocket-bookshelf";
    input = "pocket-bookshelf";
    version = "0.23.0";
    port = 8171;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-nyncRXsUGd/hCH8BZiwtuZW96JkbPUSIfcqUosMx/sI=";
  };

  calendar = {
    title = "Pocket Calendar";
    pname = "pocket-calendar";
    input = "pocket-calendar";
    version = "0.7.4";
    port = 8190;
    vendorHash = "sha256-1wpEEUBtUVTVyjYHga9x4N0A+uRfz3RcOPIaYhP0ap4=";
    npmDepsHash = "sha256-1z9sg27zun7MmuqajpA5zCRCgh++G/vjIC+cLvU4an4=";
  };

  chat = {
    title = "Pocket Chat";
    pname = "pocket-chat";
    input = "pocket-chat";
    version = "0.2.3";
    port = 8247;
    vendorHash = "sha256-jMiRPKdD3sfPqAj89+Q/hlEnUIYI34GurXx9PCTVejw=";
    npmDepsHash = "sha256-lhQVPTara24AIhlihqRp3RlYgxhsG956+gDqI7QUbx0=";
  };

  clips = {
    title = "Pocket Clips";
    pname = "pocket-clips";
    input = "pocket-clips";
    version = "0.2.4";
    port = 8173;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-aCGqXFSiwCigsz4TbQKMSoyHn1vrk/d/RjCc2lnX2lI=";
  };

  contacts = {
    title = "Pocket Contacts";
    pname = "pocket-contacts";
    input = "pocket-contacts";
    version = "0.6.0";
    port = 8191;
    vendorHash = "sha256-Yyl3Ok8RserzSVw7NC7Sa8MpjKBSk13Ptl3b3BzvPRs=";
    npmDepsHash = "sha256-ftYKsNBA4mWf3tCEYocLfSQ3vnJUH2C5kgtJ/yiLMcw=";
  };

  crm = {
    title = "Pocket CRM";
    pname = "pocket-crm";
    input = "pocket-crm";
    version = "0.1.1";
    port = 8249;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  database = {
    title = "Pocket Database";
    pname = "pocket-database";
    input = "pocket-database";
    version = "0.1.4";
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
    version = "0.46.0";
    port = 8177;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-07TBbsJyyXCVTdl+037o3Uop2Be/yswTrRL/PDF92v8=";
  };

  documents = {
    title = "Pocket Documents";
    pname = "pocket-documents";
    input = "pocket-documents";
    version = "0.8.4";
    port = 8183;
    vendorHash = "sha256-euD5qQVU7yKaEsZNa4YMFJZ/h5Bnl4x08lTq57A6zso=";
    npmDepsHash = "sha256-bAN4gWs7NUhmkC9leL3IqSIHxMIEORJnftivZ+g/8rk=";
    runtime = pkgs: with pkgs; [
      (ocrmypdf.override { tesseract = tesseract.override { enableLanguages = ocrLanguages; }; })
      (tesseract.override { enableLanguages = ocrLanguages; })
      ghostscript qpdf poppler-utils unpaper pngquant jbig2enc zbar
    ];
  };

  draw = {
    title = "Pocket Draw";
    pname = "pocket-draw";
    input = "pocket-draw";
    version = "0.4.1";
    port = 8213;
    # Excalidraw still declares React 18 as its peer.
    npmFlags = [ "--legacy-peer-deps" ];
    vendorHash = "sha256-P/IRX3mquABF7e7rZZg4T4hJ02ezl0BdLODKAhukUlA=";
    npmDepsHash = "sha256-9G2vGGFN7zg0I9pTYH9qdkJHuzZZf9E6B2MitkiWq18=";
  };

  errors = {
    title = "Pocket Errors";
    pname = "pocket-errors";
    input = "pocket-errors";
    version = "0.2.3";
    port = 8256;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-BoNk2rN98hUjXdy1xpEjtiwIYhHBvTUBYt7QpG4WAOQ=";
  };

  family = {
    title = "Pocket Family";
    pname = "pocket-family";
    input = "pocket-family";
    version = "0.1.1";
    port = 8257;
    vendorHash = "sha256-tnrkDLrbQOLM+MgSoYZM/hGJj5KzfQWwDGCWLLg104s=";
    npmDepsHash = "sha256-lhQVPTara24AIhlihqRp3RlYgxhsG956+gDqI7QUbx0=";
  };

  files = {
    title = "Pocket Files";
    pname = "pocket-files";
    input = "pocket-files";
    version = "0.13.1";
    port = 8187;
    vendorHash = "sha256-lw9YgzVdlaLP9qYTAUrWqP85YmbQX5DehOvppMKfk9E=";
    npmDepsHash = "sha256-3X9Vyi6iZSLpDVksIdv2YEZBP4hzRGW53eTY+jQdtvY=";
  };

  fitness = {
    title = "Pocket Fitness";
    pname = "pocket-fitness";
    input = "pocket-fitness";
    version = "0.1.1";
    port = 8240;
    vendorHash = "sha256-pFu6MiQCLMvN6M/3VDWBGDhyGDH7m15lQ+s9SjoMYrs=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  flows = {
    title = "Pocket Flows";
    pname = "pocket-flows";
    input = "pocket-flows";
    version = "0.7.0";
    port = 8212;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  forms = {
    title = "Pocket Forms";
    pname = "pocket-forms";
    input = "pocket-forms";
    version = "0.2.0";
    port = 8248;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-i8h+RPefc0yUf45rVvyQczKMa3dnBWx1gX/NY1ukheU=";
  };

  games = {
    title = "Pocket Games";
    pname = "pocket-games";
    input = "pocket-games";
    version = "0.2.4";
    port = 8226;
    vendorHash = "sha256-osghr94gAaBc0o6pemWSupx9eHVaOjDoX4ZRCQWu8AI=";
    npmDepsHash = "sha256-IAotK8CnIjMw7rGvI+KXq7hp4G+y2m6yOeWKgmqq7b0=";
    # The games live with the rest of the media (RomM's roms/<system> layout works as is).
    environment = { LIBRARY_DIR = "/srv/media/games"; };
    media = "rw";
  };

  garage = {
    title = "Pocket Garage";
    pname = "pocket-garage";
    input = "pocket-garage";
    version = "0.11.6";
    port = 8175;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-m+QgxtEuG6iM2JSUYFspoAiyZGtS/0jm/LCWVGHarlQ=";
  };

  guitar = {
    title = "Pocket Guitar";
    pname = "pocket-guitar";
    input = "pocket-guitar";
    version = "0.6.3";
    port = 8214;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-pcAqsLcDr3KxEQMmbxZFCjtpy6DWYp3zFmuHkFfJRIQ=";
  };

  habits = {
    title = "Pocket Habits";
    pname = "pocket-habits";
    input = "pocket-habits";
    version = "0.4.7";
    port = 8169;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-dPXEr/BzsmcLbICFgR3hHiG1/dOZ5WQmyfEMUviyUCw=";
  };

  health = {
    title = "Pocket Health";
    pname = "pocket-health";
    input = "pocket-health";
    version = "0.5.1";
    port = 8199;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-3PqYDUqWiVuCtIewmMp/Zhx3aK1d+Sn+hkoPgkLY1fA=";
  };

  home = {
    title = "Pocket Home";
    pname = "pocket-home";
    input = "pocket-home";
    version = "0.3.0";
    port = 8229;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-aGAl5wN6reOZxLLL9c2IRCaPLlh40i47pvyAT0/xlG0=";
  };

  horoscope = {
    title = "Pocket Horoscope";
    pname = "pocket-horoscope";
    input = "pocket-horoscope";
    version = "0.3.5";
    port = 8215;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-pWcwa9T3XFEG4G3K/tkjJ7F5pR9jjLgmsmXhWPVJua0=";
  };

  hub = {
    title = "Pocket Hub";
    pname = "pocket-hub";
    input = "pocket-hub";
    version = "0.7.0";
    port = 8185;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-QBq7YjC5hiKoyyXKvTq1sEh3dvqwpoV3i+1WmKIOD4Q=";
  };

  inventory = {
    title = "Pocket Inventory";
    pname = "pocket-inventory";
    input = "pocket-inventory";
    version = "0.5.5";
    port = 8170;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-MqAvJAruVISFR0z9ZqXpBVamIfykdx4cWMwpOeH9xPg=";
  };

  invoicing = {
    title = "Pocket Invoicing";
    pname = "pocket-invoicing";
    input = "pocket-invoicing";
    version = "0.14.0";
    port = 8168;
    vendorHash = "sha256-XDAJARRpTUBRY4PhsJoiz0LRWRm9kO5zMNeiu0BEQCY=";
    npmDepsHash = "sha256-B6jZTFFZUl2SQQpGHEXkm0Fk4L2LlnyS1DZ56XRaU+Y=";
  };

  jobs = {
    title = "Pocket Jobs";
    pname = "pocket-jobs";
    input = "pocket-jobs";
    version = "0.1.0";
    port = 8261;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-Bx7xgEFK6E71G0qtrjVg1FQOcEjPGzefOxlti069n68=";
  };

  kitchen = {
    title = "Pocket Kitchen";
    pname = "pocket-kitchen";
    input = "pocket-kitchen";
    version = "0.6.0";
    port = 8176;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-V/EgsjDw9Ljmn1icnZmpjn/9WeSDzmMN98aBsX8lnig=";
  };

  league = {
    title = "Pocket League";
    pname = "pocket-league";
    input = "pocket-league";
    version = "0.4.6";
    port = 8250;
    vendorHash = "sha256-UsI/e/U1D9b8qcM8HTpS9jwK9kQHHVv3+/PTkhizGdk=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  learn = {
    title = "Pocket Learn";
    pname = "pocket-learn";
    input = "pocket-learn";
    version = "0.2.3";
    port = 8218;
    vendorHash = "sha256-xwT3RlXy0QqPfdjtX7Cw+UY4cAk2Rc3KWz3J7/gIwgQ=";
    npmDepsHash = "sha256-6LtajmSMdYn9OruNzbTL8vNi30G9LTFlShDGYPWK6JY=";
  };

  library = {
    title = "Pocket Library";
    pname = "pocket-library";
    input = "pocket-library";
    version = "0.11.0";
    port = 8204;
    vendorHash = "sha256-lWyJoSwFe/tai0GsxUMyUDVZjxk5zB+fhZFpr8aySE4=";
    npmDepsHash = "sha256-k/2TkoQOojzn2iKlZ+Fw/4fzq3TxAnmZ2HLhPyjH7ns=";
    runtime = pkgs: [ pkgs.poppler-utils ];
    media = "rw";
  };

  lookout = {
    title = "Pocket Lookout";
    pname = "pocket-lookout";
    input = "pocket-lookout";
    version = "0.2.2";
    port = 8224;
    vendorHash = "sha256-I+1cF7f2lxcJRqZiXfwFQvMcFPNXVQVaLIBTDDqNYCc=";
    npmDepsHash = "sha256-0pu2PDc9/2oMTSa6fb4Uv+p4ROlXwGh/KoN1DDB7Jms=";
    # Pages that need JavaScript open in the box's headless Chromium (modules/services.nix).
    environment = { BROWSER_URL = "http://127.0.0.1:9222"; };
  };

  mail = {
    title = "Pocket Mail";
    pname = "pocket-mail";
    input = "pocket-mail";
    version = "0.3.0";
    port = 8208;
    vendorHash = "sha256-kZcQ59gr0qjv7s+vIPRqjGvTRIYceZUvVAzPxEN620s=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  map = {
    title = "Pocket Map";
    pname = "pocket-map";
    input = "pocket-map";
    version = "0.1.0";
    port = 8255;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-U+exrYitvtCMA5ncGMwnU8OHJnfK9M3pvelXlowPRKs=";
  };

  money = {
    title = "Pocket Money";
    pname = "pocket-money";
    input = "pocket-money";
    version = "0.22.8";
    port = 8178;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-awNiiTvNpyDytlZ4g+VNpztQhCgtgElyoNui1QrLMXk=";
  };

  monitoring = {
    title = "Pocket Monitoring";
    pname = "pocket-monitoring";
    input = "pocket-monitoring";
    version = "0.6.3";
    port = 8192;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-driQt07Y6kd8nLbd/gHQ5FHbVj9c+WFaHrlLg7ORgxk=";
    environment = { LOCAL_NAME = "Pocket Box"; };
  };

  movement = {
    title = "Pocket Movement";
    pname = "pocket-movement";
    input = "pocket-movement";
    version = "0.3.5";
    port = 8197;
    vendorHash = "sha256-Lq9WpVSSyiPx5jCT5I0P5gpmIHmkh7qpGjQBxjPnVS4=";
    npmDepsHash = "sha256-1DgCVRSoFk8jcO5i+NgPIs5R1wfGFKaUnKd5BbexmhI=";
  };

  music = {
    title = "Pocket Music";
    pname = "pocket-music";
    input = "pocket-music";
    version = "0.8.2";
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
    version = "0.1.4";
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
    version = "0.11.1";
    port = 8182;
    vendorHash = "sha256-UM7ZCv25k1FfOl04WsQnyY47YZQVIjJIXGAYWcj5RZM=";
    npmDepsHash = "sha256-/5yuEn1YUPoCpoqPQO6hr967U6I7PhjDU4QXEu+IH6Y=";
  };

  nutrition = {
    title = "Pocket Nutrition";
    pname = "pocket-nutrition";
    input = "pocket-nutrition";
    version = "0.1.0";
    port = 8241;
    vendorHash = "sha256-I6een11YjmxnNePc9DMsdbSyQLbhosmiYJ+495CzC3U=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  office = {
    title = "Pocket Office";
    pname = "pocket-office";
    input = "pocket-office";
    version = "0.7.2";
    port = 8186;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-v0tDTefOAPNSPoLor4IbNyZ/ysTJC//4v+PHne1tjoI=";
  };

  parcels = {
    title = "Pocket Parcels";
    pname = "pocket-parcels";
    input = "pocket-parcels";
    version = "0.1.1";
    port = 8233;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-nqlnAqSvsrPUsyzIGXBtsZWodsseTR+Wyidmt+mMyxo=";
  };

  pets = {
    title = "Pocket Pets";
    pname = "pocket-pets";
    input = "pocket-pets";
    version = "0.1.1";
    port = 8232;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-JcBLYNm42iT6skz1Tf8q1RjGJS9T1L2C6AspL5yl+Ig=";
  };

  photos = {
    title = "Pocket Photos";
    pname = "pocket-photos";
    input = "pocket-photos";
    version = "0.6.1";
    port = 8194;
    vendorHash = "sha256-2l4xE/U9dbbUNL9ANgr4iszIt7CPGojCAqV6yrFQOlY=";
    npmDepsHash = "sha256-rM3J3T1WLldCd4Iqw3ZmhtErzFkIob0/CwIu1tC8uJo=";
    runtime = pkgs: [ pkgs.ffmpeg-headless ];
  };

  places = {
    title = "Pocket Places";
    pname = "pocket-places";
    input = "pocket-places";
    version = "0.1.2";
    port = 8236;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-aPVtrKW53x29edajbeKqAbArnjmjnYNoegZwHBxNPzk=";
  };

  podcasts = {
    title = "Pocket Podcasts";
    pname = "pocket-podcasts";
    input = "pocket-podcasts";
    version = "0.4.5";
    port = 8181;
    vendorHash = "sha256-/aYsGz8D+sXJ8LvrJWIKAgMCVIbN/C86I86Scrir7ZA=";
    npmDepsHash = "sha256-nyncRXsUGd/hCH8BZiwtuZW96JkbPUSIfcqUosMx/sI=";
    runtime = pkgs: with pkgs; [ ffmpeg-headless yt-dlp deno ];
  };

  "pr-review" = {
    title = "Pocket PR Review";
    pname = "pocket-pr-review";
    input = "pocket-pr-review";
    version = "0.3.0";
    port = 8220;
    vendorHash = "sha256-ju4olZm6rwdgCxUAkYCetwQxhbVgBc4E64+aN1CZyJE=";
    npmDepsHash = "sha256-gfXmenNLofgIweOhYE3usg4hHnh8OU//Wcilvt8CnWw=";
  };

  projects = {
    title = "Pocket Projects";
    pname = "pocket-projects";
    input = "pocket-projects";
    version = "0.40.4";
    port = 8196;
    vendorHash = "sha256-vgbrGDE4zwZV5EdR6LjQIWtyXGd/CQbjAlEAiSM/3tc=";
    npmDepsHash = "sha256-4BkXWQ/ye82pdmw9IfumQ+jWT3CTXysxOpA6cI8hLRM=";
  };

  radio = {
    title = "Pocket Radio";
    pname = "pocket-radio";
    input = "pocket-radio";
    version = "0.1.2";
    port = 8216;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-AzYQcVW6vaXzAYwgmfjaUJjjslwFHpUjiPxeDlc1J2Y=";
  };

  reader = {
    title = "Pocket Reader";
    pname = "pocket-reader";
    input = "pocket-reader";
    version = "0.1.2";
    port = 8211;
    vendorHash = "sha256-Mv5ArOdAAgT0IgqCnEv8cBcmy5KxC1Xe7QzRfqSQO4k=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  remote = {
    title = "Pocket Remote";
    pname = "pocket-remote";
    input = "pocket-remote";
    version = "0.3.0";
    port = 8259;
    vendorHash = "sha256-+uDc+UC9z7QTsGhfbml1Z/B3VVbeHbjcccm0de8RxRI=";
    npmDepsHash = "sha256-C/eL2qrSr8IunXu5eLF6aYQQZWwjUx0Bxe5oWepwSPM=";
    # VNC, RDP and SSH through guacd on the box (modules/services.nix).
    environment = { GUACD_ADDR = "127.0.0.1:4822"; };
  };

  renewals = {
    title = "Pocket Renewals";
    pname = "pocket-renewals";
    input = "pocket-renewals";
    version = "0.6.0";
    port = 8230;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-guJjvt4I1xxbF73/lHy2qIv3VTS3mrZwhrzKixJoGW4=";
  };

  rentals = {
    title = "Pocket Rentals";
    pname = "pocket-rentals";
    input = "pocket-rentals";
    version = "0.1.1";
    port = 8253;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  requests = {
    title = "Pocket Requests";
    pname = "pocket-requests";
    input = "pocket-requests";
    version = "0.10.1";
    port = 8210;
    # Requests go to the box's Radarr, Sonarr and Lidarr (modules/services.nix), through Pocket Core.
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  review = {
    title = "Pocket Review";
    pname = "pocket-review";
    input = "pocket-review";
    version = "0.7.1";
    port = 8180;
    vendorHash = "sha256-6jrjPbqotB5hfcLTWEGfH5bIki5/jEVxirr/TkXTJfw=";
    npmDepsHash = "sha256-R4VBjT/PtdtzLzOrxaY63Fg3qlIMO2qbjbxWTibAaY8=";
  };

  search = {
    title = "Pocket Search";
    pname = "pocket-search";
    input = "pocket-search";
    version = "0.19.0";
    port = 8225;
    vendorHash = "sha256-gzWT5q/Hy4LInKVGQxBkNQCNaipGA9Jk7MbANyBVKJ0=";
    npmDepsHash = "sha256-P92MslwmlPt8N95dSjIZitFvWpSn8FTaNxltAMAEcEg=";
    # Results come from the box's own SearXNG on loopback (modules/services.nix).
    environment = { SEARXNG_URL = "http://127.0.0.1:8888"; };
  };

  sign = {
    title = "Pocket Sign";
    pname = "pocket-sign";
    input = "pocket-sign";
    version = "0.1.0";
    port = 8234;
    vendorHash = "sha256-8La76XnF19Kl0EF/x9LE0QaOgWzNP0QkmYyZ/eYIUDc=";
    npmDepsHash = "sha256-bXZD7OQBezcE8caXpO9mXDNXbd+3meXFI/xTC4gAdGU=";
  };

  split = {
    title = "Pocket Split";
    pname = "pocket-split";
    input = "pocket-split";
    version = "0.8.0";
    port = 8172;
    vendorHash = "sha256-NAkS3wnN14V7t5vyEAyFrdfxcZROSHOEWZBlkq4h10I=";
    npmDepsHash = "sha256-xPq4EltB1pyx8Lm9g0/PRsVqqwriA6IKNZ7ce4jkD/w=";
  };

  sphere = {
    title = "Pocket Sphere";
    pname = "pocket-sphere";
    input = "pocket-sphere";
    version = "0.5.0";
    port = 8227;
    vendorHash = "sha256-H7gAZUfexe/MnzCPRXoTKc8vPwQGq1egA47mp00j44E=";
    npmDepsHash = "sha256-IAotK8CnIjMw7rGvI+KXq7hp4G+y2m6yOeWKgmqq7b0=";
    # python3 runs the yt-dlp the app keeps (and updates) in its data folder; deno solves YouTube's JS.
    runtime = pkgs: with pkgs; [ ffmpeg-headless python3 deno ];
    # Videos stay in the app's own folder (/var/lib/pocket-sphere/library), not in /srv/media where
    # the other media apps could see them.
  };

  still = {
    title = "Pocket Still";
    pname = "pocket-still";
    input = "pocket-still";
    version = "0.1.4";
    port = 8206;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  subtitles = {
    title = "Pocket Subtitles";
    pname = "pocket-subtitles";
    input = "pocket-subtitles";
    version = "0.6.1";
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

  tables = {
    title = "Pocket Tables";
    pname = "pocket-tables";
    input = "pocket-tables";
    version = "0.2.0";
    port = 8252;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  tasks = {
    title = "Pocket Tasks";
    pname = "pocket-tasks";
    input = "pocket-tasks";
    version = "0.5.2";
    port = 8184;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-Jd1WgUWEe7ZLmRLzrBVrHSvbqFDnZiLSOqVvA7v5/1w=";
  };

  time = {
    title = "Pocket Time";
    pname = "pocket-time";
    input = "pocket-time";
    version = "0.1.4";
    port = 8219;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-IUfV0aYCkbPuBCCnr2zB+KlzfYC7Lobj1q+K8NsFeyk=";
  };

  trails = {
    title = "Pocket Trails";
    pname = "pocket-trails";
    input = "pocket-trails";
    version = "0.1.4";
    port = 8254;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-U+exrYitvtCMA5ncGMwnU8OHJnfK9M3pvelXlowPRKs=";
  };

  translate = {
    title = "Pocket Translate";
    pname = "pocket-translate";
    input = "pocket-translate";
    version = "0.1.3";
    port = 8251;
    vendorHash = "sha256-rjLzlaSTxS9THfICzim5KR0SlXJhyZ5doZn5jVXOhZw=";
    npmDepsHash = "sha256-TWtfA92MZXjLcv0IgvZw7OoUl/i2USWDAdXNoctaJn8=";
    # Reads PDFs and photos. Translates with Pocket AI, and offline once
    # pocket.box.services.libretranslate is on (modules/services.nix).
    runtime = pkgs: with pkgs; [ poppler-utils (tesseract.override { enableLanguages = ocrLanguages; }) ];
  };

  travel = {
    title = "Pocket Travel";
    pname = "pocket-travel";
    input = "pocket-travel";
    version = "0.13.0";
    port = 8174;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-1DgCVRSoFk8jcO5i+NgPIs5R1wfGFKaUnKd5BbexmhI=";
  };

  voice = {
    title = "Pocket Voice";
    pname = "pocket-voice";
    input = "pocket-voice";
    version = "0.7.12";
    port = 8237;
    # ffmpeg reads any recording; whisper.cpp (whisper-cli and parakeet-cli) writes it out on the box.
    # The speech models are downloaded into /var/lib/pocket-voice/models when first chosen.
    runtime = pkgs: with pkgs; [ ffmpeg-headless whisper-cpp ];
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-ErYsF9rIQecEN0sYGq9EZSQ54Fy9MnZwOIFQEatnnTI=";
  };

  wallet = {
    title = "Pocket Wallet";
    pname = "pocket-wallet";
    input = "pocket-wallet";
    version = "0.1.0";
    port = 8238;
    vendorHash = "sha256-0exwAsKNPHyvVJflYAzBWdQWmvCpBqXhqc+7A6ZyH0o=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  wardrobe = {
    title = "Pocket Wardrobe";
    pname = "pocket-wardrobe";
    input = "pocket-wardrobe";
    version = "0.1.3";
    port = 8258;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-7H/p6i4P203zpCs4nK6kihq4uSC7t2HqG2sHAHnUous=";
  };

  watch = {
    title = "Pocket Watch";
    pname = "pocket-watch";
    input = "pocket-watch";
    version = "0.7.0";
    port = 8201;
    vendorHash = "sha256-5t6xTN2Ck2RHfOV4+otOwXkR11Rzj7mhNcig+mLAJmM=";
    npmDepsHash = "sha256-iJULF2fqzlRKJ7Q88yR2fb9L/GH5stsYJx0GYsm/RyI=";
  };

  wealth = {
    title = "Pocket Wealth";
    pname = "pocket-wealth";
    input = "pocket-wealth";
    version = "0.2.0";
    port = 8231;
    vendorHash = "sha256-czmaak0Anph/bKzWuexQBN0XPRuQK7otZx6KZOB77Fw=";
    npmDepsHash = "sha256-l7WPLj+uETSp67Kx1ST3fyywCUkZfq4R0h36fb2wwF0=";
  };

  weather = {
    title = "Pocket Weather";
    pname = "pocket-weather";
    input = "pocket-weather";
    version = "0.3.0";
    port = 8239;
    vendorHash = "sha256-pFu6MiQCLMvN6M/3VDWBGDhyGDH7m15lQ+s9SjoMYrs=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  wishlist = {
    title = "Pocket Wishlist";
    pname = "pocket-wishlist";
    input = "pocket-wishlist";
    version = "0.4.4";
    port = 8198;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-EEYlm98eERnnG8qrW9GRBSLNQKvpXlNdFd76LjLsWrY=";
  };
}
