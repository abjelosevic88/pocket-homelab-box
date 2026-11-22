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
    version = "0.43.2";
    port = 8179;
    vendorHash = "sha256-huJmNurz4us0yapuZk5Tc37zUx1yysMDAxd0aytrTuY=";
    npmDepsHash = "sha256-B6hwAJzFxJG6iSPCb/vrsQrF8lzORM95hK7vslmlGm0=";
  };

  ai = {
    title = "Pocket AI";
    pname = "pocket-ai";
    input = "pocket-ai";
    version = "0.107.0";
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
    version = "0.4.0";
    port = 8217;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-AzYQcVW6vaXzAYwgmfjaUJjjslwFHpUjiPxeDlc1J2Y=";
  };

  audiobooks = {
    title = "Pocket Audiobooks";
    pname = "pocket-audiobooks";
    input = "pocket-audiobooks";
    version = "1.7.0";
    port = 8202;
    vendorHash = "sha256-VamRHu2o62pOgrpseLN7W+48mlXLFCqHfYQmh6BpeKo=";
    npmDepsHash = "sha256-4ZkfBQ/FoyLt13Z1DSzSE3gi5L1wzC/rKh755CrJSag=";
    runtime = pkgs: [ pkgs.ffmpeg-headless ];
    media = "rw";
  };

  backups = {
    title = "Pocket Backups";
    pname = "pocket-backups";
    input = "pocket-backups";
    version = "0.3.2";
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
    version = "0.2.0";
    port = 8246;
    vendorHash = "sha256-LyIIfI8xv5T1AV9TTiXLVrcaWHVKbDfDsoqt6TJbZoE=";
    npmDepsHash = "sha256-NtSPzI1S++tsQnKUYTC1snpfLQyio8U4+7eXe/ObEE0=";
  };

  blueprint = {
    title = "Pocket Blueprint";
    pname = "pocket-blueprint";
    input = "pocket-blueprint";
    version = "0.3.0";
    port = 8222;
    # Reads git history of the repositories it inspects.
    runtime = pkgs: [ pkgs.git ];
    vendorHash = "sha256-trJ8Nr0Besm4Vz16Za0GBXszIysR3pcDBpulIcCPTxk=";
    npmDepsHash = "sha256-xddyerXbIl/9namq/mwAMmc59hu79Bq5/Iw3Rl3YdYI=";
  };

  boards = {
    title = "Pocket Boards";
    pname = "pocket-boards";
    input = "pocket-boards";
    version = "0.2.0";
    port = 8223;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-FGjpcDpJH73C5O7i85sSuLfwvhq6kE7U16vrJiF2XJM=";
  };

  booking = {
    title = "Pocket Booking";
    pname = "pocket-booking";
    input = "pocket-booking";
    version = "0.2.0";
    port = 8279;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-8GxXcpHhlCNl1Y0ouwb3zI3Tw7X5ZcpwbyxJNDTQvmA=";
  };

  bookshelf = {
    title = "Pocket Bookshelf";
    pname = "pocket-bookshelf";
    input = "pocket-bookshelf";
    version = "0.24.0";
    port = 8171;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-nyncRXsUGd/hCH8BZiwtuZW96JkbPUSIfcqUosMx/sI=";
  };

  calendar = {
    title = "Pocket Calendar";
    pname = "pocket-calendar";
    input = "pocket-calendar";
    version = "0.8.0";
    port = 8190;
    vendorHash = "sha256-XlbEq9c+hhFRoVRKBXJ74VcboE8lWkJ/9TwfbFVbNTc=";
    npmDepsHash = "sha256-1z9sg27zun7MmuqajpA5zCRCgh++G/vjIC+cLvU4an4=";
  };

  cameras = {
    title = "Pocket Cameras";
    pname = "pocket-cameras";
    input = "pocket-cameras";
    version = "0.2.0";
    port = 8280;
    vendorHash = "sha256-0fyLca2/G8OfjBOPNWqBG4fy8fHUxB93lazdBPH9wJg=";
    npmDepsHash = "sha256-YiVzc33Fr9TubK5g78mYoYjANIpx41R7P2G0JAQG4Qk=";
    # Live view, motion and recordings: ffmpeg/ffprobe from PATH (FFMPEG/FFPROBE override).
    runtime = pkgs: with pkgs; [ ffmpeg-headless ];
  };

  capsule = {
    title = "Pocket Capsule";
    pname = "pocket-capsule";
    input = "pocket-capsule";
    version = "0.2.0";
    port = 8268;
    vendorHash = "sha256-qDUkGrgKh+0x4Hu+OSHt2FlrOqTSwIK5/C72S0420wY=";
    npmDepsHash = "sha256-YiVzc33Fr9TubK5g78mYoYjANIpx41R7P2G0JAQG4Qk=";
  };

  chat = {
    title = "Pocket Chat";
    pname = "pocket-chat";
    input = "pocket-chat";
    version = "0.3.0";
    port = 8247;
    vendorHash = "sha256-rjOplqg+0PqcqH/3AMEZtooXEcLxFVgbHlwah1zJJII=";
    npmDepsHash = "sha256-lhQVPTara24AIhlihqRp3RlYgxhsG956+gDqI7QUbx0=";
  };

  clips = {
    title = "Pocket Clips";
    pname = "pocket-clips";
    input = "pocket-clips";
    version = "0.3.0";
    port = 8173;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-aCGqXFSiwCigsz4TbQKMSoyHn1vrk/d/RjCc2lnX2lI=";
  };

  contacts = {
    title = "Pocket Contacts";
    pname = "pocket-contacts";
    input = "pocket-contacts";
    version = "0.8.0";
    port = 8191;
    vendorHash = "sha256-m4QC5UPosNB8kYpf6jFpO5jNbrvD2WHisuIa3ksdyqY=";
    npmDepsHash = "sha256-ftYKsNBA4mWf3tCEYocLfSQ3vnJUH2C5kgtJ/yiLMcw=";
  };

  crm = {
    title = "Pocket CRM";
    pname = "pocket-crm";
    input = "pocket-crm";
    version = "0.3.0";
    port = 8249;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  database = {
    title = "Pocket Database";
    pname = "pocket-database";
    input = "pocket-database";
    version = "0.2.0";
    port = 8209;
    vendorHash = "sha256-xvKfjGim1bUt40h1g2PHjQ0fD3ZFvaXtwQ2wBrfhxb8=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
    # Opens the SQLite databases of every app on the box, so it runs as root.
    environment = { SCAN_PATHS = "/var/lib"; };
    root = true;
  };

  day = {
    title = "Pocket Day";
    pname = "pocket-day";
    input = "pocket-day";
    version = "0.50.0";
    port = 8177;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-07TBbsJyyXCVTdl+037o3Uop2Be/yswTrRL/PDF92v8=";
  };

  documents = {
    title = "Pocket Documents";
    pname = "pocket-documents";
    input = "pocket-documents";
    version = "0.9.0";
    port = 8183;
    vendorHash = "sha256-tqIOR1TrpNYSl+aZRIZniTPAa7QJEmSMxyr84Q9PkLw=";
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
    version = "0.5.0";
    port = 8213;
    # Excalidraw still declares React 18 as its peer.
    npmFlags = [ "--legacy-peer-deps" ];
    vendorHash = "sha256-sniqCJinTjIAtf0sXzOYsq1dLvWXeUo7as1jz7m7yUs=";
    npmDepsHash = "sha256-9G2vGGFN7zg0I9pTYH9qdkJHuzZZf9E6B2MitkiWq18=";
  };

  errors = {
    title = "Pocket Errors";
    pname = "pocket-errors";
    input = "pocket-errors";
    version = "0.3.0";
    port = 8256;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-BoNk2rN98hUjXdy1xpEjtiwIYhHBvTUBYt7QpG4WAOQ=";
  };

  family = {
    title = "Pocket Family";
    pname = "pocket-family";
    input = "pocket-family";
    version = "0.2.0";
    port = 8257;
    vendorHash = "sha256-TBr2j5zfADFFRAuYcLxDa9qV0YvjMFDDumONp0LCKK0=";
    npmDepsHash = "sha256-lhQVPTara24AIhlihqRp3RlYgxhsG956+gDqI7QUbx0=";
  };

  files = {
    title = "Pocket Files";
    pname = "pocket-files";
    input = "pocket-files";
    version = "0.14.0";
    port = 8187;
    vendorHash = "sha256-iQV6MCJ64HwtjeZXt5Qt9h4/8nI1xkV6TSuew48F0iI=";
    npmDepsHash = "sha256-3X9Vyi6iZSLpDVksIdv2YEZBP4hzRGW53eTY+jQdtvY=";
  };

  fitness = {
    title = "Pocket Fitness";
    pname = "pocket-fitness";
    input = "pocket-fitness";
    version = "0.2.0";
    port = 8240;
    vendorHash = "sha256-79zuzyNQu11Jm9VW1SZyolTiLG3gcq4d5Zv4GXvza94=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  flows = {
    title = "Pocket Flows";
    pname = "pocket-flows";
    input = "pocket-flows";
    version = "0.9.0";
    port = 8212;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  forms = {
    title = "Pocket Forms";
    pname = "pocket-forms";
    input = "pocket-forms";
    version = "0.3.0";
    port = 8248;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-i8h+RPefc0yUf45rVvyQczKMa3dnBWx1gX/NY1ukheU=";
  };

  forum = {
    title = "Pocket Forum";
    pname = "pocket-forum";
    input = "pocket-forum";
    version = "0.2.0";
    port = 8267;
    vendorHash = "sha256-BbSNnGJTl9kFNeGdvhnljMgPqbCSL+YF50uyjswVK7o=";
    npmDepsHash = "sha256-YiVzc33Fr9TubK5g78mYoYjANIpx41R7P2G0JAQG4Qk=";
  };

  gamebuilder = {
    title = "Pocket Game Builder";
    pname = "pocket-gamebuilder";
    input = "pocket-gamebuilder";
    version = "0.2.0";
    port = 8275;
    vendorHash = "sha256-qDUkGrgKh+0x4Hu+OSHt2FlrOqTSwIK5/C72S0420wY=";
    npmDepsHash = "sha256-YiVzc33Fr9TubK5g78mYoYjANIpx41R7P2G0JAQG4Qk=";
  };

  games = {
    title = "Pocket Games";
    pname = "pocket-games";
    input = "pocket-games";
    version = "0.3.0";
    port = 8226;
    vendorHash = "sha256-7F5d1lnbhgDndwiCzz6B0XOSKdSyZpUgstjKD5uQVHg=";
    npmDepsHash = "sha256-IAotK8CnIjMw7rGvI+KXq7hp4G+y2m6yOeWKgmqq7b0=";
    # The games live with the rest of the media (RomM's roms/<system> layout works as is).
    environment = { LIBRARY_DIR = "/srv/media/games"; };
    media = "rw";
  };

  garage = {
    title = "Pocket Garage";
    pname = "pocket-garage";
    input = "pocket-garage";
    version = "0.12.0";
    port = 8175;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-m+QgxtEuG6iM2JSUYFspoAiyZGtS/0jm/LCWVGHarlQ=";
  };

  guitar = {
    title = "Pocket Guitar";
    pname = "pocket-guitar";
    input = "pocket-guitar";
    version = "0.7.0";
    port = 8214;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-pcAqsLcDr3KxEQMmbxZFCjtpy6DWYp3zFmuHkFfJRIQ=";
  };

  habits = {
    title = "Pocket Habits";
    pname = "pocket-habits";
    input = "pocket-habits";
    version = "0.5.0";
    port = 8169;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-dPXEr/BzsmcLbICFgR3hHiG1/dOZ5WQmyfEMUviyUCw=";
  };

  health = {
    title = "Pocket Health";
    pname = "pocket-health";
    input = "pocket-health";
    version = "0.7.0";
    port = 8199;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-3PqYDUqWiVuCtIewmMp/Zhx3aK1d+Sn+hkoPgkLY1fA=";
  };

  home = {
    title = "Pocket Home";
    pname = "pocket-home";
    input = "pocket-home";
    version = "0.4.0";
    port = 8229;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-aGAl5wN6reOZxLLL9c2IRCaPLlh40i47pvyAT0/xlG0=";
  };

  horoscope = {
    title = "Pocket Horoscope";
    pname = "pocket-horoscope";
    input = "pocket-horoscope";
    version = "0.4.0";
    port = 8215;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-pWcwa9T3XFEG4G3K/tkjJ7F5pR9jjLgmsmXhWPVJua0=";
  };

  hub = {
    title = "Pocket Hub";
    pname = "pocket-hub";
    input = "pocket-hub";
    version = "0.7.1";
    port = 8185;
    vendorHash = "sha256-orX8b2RbbV3XoLZ4WAfqSgQF/AYRinb4n6V4okSMbCk=";
    npmDepsHash = "sha256-QBq7YjC5hiKoyyXKvTq1sEh3dvqwpoV3i+1WmKIOD4Q=";
  };

  inventory = {
    title = "Pocket Inventory";
    pname = "pocket-inventory";
    input = "pocket-inventory";
    version = "0.6.0";
    port = 8170;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-MqAvJAruVISFR0z9ZqXpBVamIfykdx4cWMwpOeH9xPg=";
  };

  invoicing = {
    title = "Pocket Invoicing";
    pname = "pocket-invoicing";
    input = "pocket-invoicing";
    version = "0.16.0";
    port = 8168;
    vendorHash = "sha256-MHCtaKd1/n6JdpMlAo25cAZibobAx6/bq1RnCoeWnQA=";
    npmDepsHash = "sha256-B6jZTFFZUl2SQQpGHEXkm0Fk4L2LlnyS1DZ56XRaU+Y=";
  };

  jam = {
    title = "Pocket Jam";
    pname = "pocket-jam";
    input = "pocket-jam";
    version = "0.8.0";
    port = 8278;
    vendorHash = "sha256-qDUkGrgKh+0x4Hu+OSHt2FlrOqTSwIK5/C72S0420wY=";
    npmDepsHash = "sha256-YiVzc33Fr9TubK5g78mYoYjANIpx41R7P2G0JAQG4Qk=";
  };

  jobs = {
    title = "Pocket Jobs";
    pname = "pocket-jobs";
    input = "pocket-jobs";
    version = "0.2.0";
    port = 8261;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-Bx7xgEFK6E71G0qtrjVg1FQOcEjPGzefOxlti069n68=";
  };

  karaoke = {
    title = "Pocket Karaoke";
    pname = "pocket-karaoke";
    input = "pocket-karaoke";
    version = "0.2.0";
    port = 8273;
    vendorHash = "sha256-qDUkGrgKh+0x4Hu+OSHt2FlrOqTSwIK5/C72S0420wY=";
    npmDepsHash = "sha256-YiVzc33Fr9TubK5g78mYoYjANIpx41R7P2G0JAQG4Qk=";
    # Song files: ffmpeg/ffprobe. YouTube copies: yt-dlp (the app keeps its own newer copy in its data
    # folder when it can) with deno for YouTube's signature puzzles, the same as Pocket Podcasts.
    runtime = pkgs: with pkgs; [ ffmpeg-headless yt-dlp deno python3 ];
  };

  kitchen = {
    title = "Pocket Kitchen";
    pname = "pocket-kitchen";
    input = "pocket-kitchen";
    version = "0.7.0";
    port = 8176;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-V/EgsjDw9Ljmn1icnZmpjn/9WeSDzmMN98aBsX8lnig=";
  };

  league = {
    title = "Pocket League";
    pname = "pocket-league";
    input = "pocket-league";
    version = "0.5.0";
    port = 8250;
    vendorHash = "sha256-aHXuUCCcXOQcfAewepUwtWvbzSaXcA/mbOKIqm/4Fvo=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  learn = {
    title = "Pocket Learn";
    pname = "pocket-learn";
    input = "pocket-learn";
    version = "0.3.0";
    port = 8218;
    vendorHash = "sha256-0Tw0DFLdCjVAXj+c8eDNhWnQHFbxkcsqK0+2C6HlnuU=";
    npmDepsHash = "sha256-6LtajmSMdYn9OruNzbTL8vNi30G9LTFlShDGYPWK6JY=";
  };

  library = {
    title = "Pocket Library";
    pname = "pocket-library";
    input = "pocket-library";
    version = "0.12.0";
    port = 8204;
    vendorHash = "sha256-gPCZ3PPdK+yotznoFSqSIfuHQwFuUsNs44i3hWEWNXY=";
    npmDepsHash = "sha256-k/2TkoQOojzn2iKlZ+Fw/4fzq3TxAnmZ2HLhPyjH7ns=";
    runtime = pkgs: [ pkgs.poppler-utils ];
    media = "rw";
  };

  lookout = {
    title = "Pocket Lookout";
    pname = "pocket-lookout";
    input = "pocket-lookout";
    version = "0.3.0";
    port = 8224;
    vendorHash = "sha256-G/1yoAnZt0AXEfGtANWCSoZPeFeK5QQswpzcEsnrTAY=";
    npmDepsHash = "sha256-0pu2PDc9/2oMTSa6fb4Uv+p4ROlXwGh/KoN1DDB7Jms=";
    # Pages that need JavaScript open in the box's headless Chromium (modules/services.nix).
    environment = { BROWSER_URL = "http://127.0.0.1:9222"; };
  };

  mail = {
    title = "Pocket Mail";
    pname = "pocket-mail";
    input = "pocket-mail";
    version = "0.4.0";
    port = 8208;
    vendorHash = "sha256-3vVxCNDa8WuY97g6bk5VnqeqGtote731CTfn0Yfz0W0=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  map = {
    title = "Pocket Map";
    pname = "pocket-map";
    input = "pocket-map";
    version = "0.2.0";
    port = 8255;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-U+exrYitvtCMA5ncGMwnU8OHJnfK9M3pvelXlowPRKs=";
  };

  math = {
    title = "Pocket Math";
    pname = "pocket-math";
    input = "pocket-math";
    version = "0.2.0";
    port = 8272;
    vendorHash = "sha256-qDUkGrgKh+0x4Hu+OSHt2FlrOqTSwIK5/C72S0420wY=";
    npmDepsHash = "sha256-spe3aru2VBZt5ZUzv7QtqMpOGwsMV+tDfU51Tm8FvXw=";
  };

  money = {
    title = "Pocket Money";
    pname = "pocket-money";
    input = "pocket-money";
    version = "0.23.0";
    port = 8178;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
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
    version = "0.4.0";
    port = 8197;
    vendorHash = "sha256-V8UZg/17HFFnTq3qfQOZGk+Hut9t5MhoZg/1XNLuf7Y=";
    npmDepsHash = "sha256-1DgCVRSoFk8jcO5i+NgPIs5R1wfGFKaUnKd5BbexmhI=";
  };

  music = {
    title = "Pocket Music";
    pname = "pocket-music";
    input = "pocket-music";
    version = "0.9.0";
    port = 8200;
    vendorHash = "sha256-Gg8x6vIp9HKXVTFbdc6XAwIeTqszh0cp+tv3ckQEYqs=";
    npmDepsHash = "sha256-ZRQ75xHYUhYmBsS6/mR635qNTdXgdpDMKQiHuzOy3nU=";
    environment = { MUSIC_DIR = "/srv/media/music"; };
    media = "rw";
  };

  network = {
    title = "Pocket Network";
    pname = "pocket-network";
    input = "pocket-network";
    version = "0.2.0";
    port = 8207;
    vendorHash = "sha256-ySGSompB/GwXIfZTYng18zbmY/MY56A55wmPeGZoYcQ=";
    npmDepsHash = "sha256-aglaIpqKG+jRJO7F8YXnk4bBl/lU7WJx1xRZviIVR1s=";
    # Pings and ARP scans the LAN.
    capabilities = [ "CAP_NET_RAW" ];
  };

  notes = {
    title = "Pocket Notes";
    pname = "pocket-notes";
    input = "pocket-notes";
    version = "0.15.0";
    port = 8182;
    vendorHash = "sha256-Sr+mCQ69vyaxtSyILgmsf2v9mmNuTaZEmFb6HkikZTI=";
    npmDepsHash = "sha256-/5yuEn1YUPoCpoqPQO6hr967U6I7PhjDU4QXEu+IH6Y=";
  };

  nutrition = {
    title = "Pocket Nutrition";
    pname = "pocket-nutrition";
    input = "pocket-nutrition";
    version = "0.2.0";
    port = 8241;
    vendorHash = "sha256-Gcy8QPVYe09/Z6lccld5HUpIhURcgULcwtEQEh/Uh88=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  office = {
    title = "Pocket Office";
    pname = "pocket-office";
    input = "pocket-office";
    version = "0.8.2";
    port = 8186;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-v0tDTefOAPNSPoLor4IbNyZ/ysTJC//4v+PHne1tjoI=";
  };

  parcels = {
    title = "Pocket Parcels";
    pname = "pocket-parcels";
    input = "pocket-parcels";
    version = "0.2.0";
    port = 8233;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-nqlnAqSvsrPUsyzIGXBtsZWodsseTR+Wyidmt+mMyxo=";
  };

  pets = {
    title = "Pocket Pets";
    pname = "pocket-pets";
    input = "pocket-pets";
    version = "0.2.0";
    port = 8232;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-JcBLYNm42iT6skz1Tf8q1RjGJS9T1L2C6AspL5yl+Ig=";
  };

  photolab = {
    title = "Pocket Photo Lab";
    pname = "pocket-photolab";
    input = "pocket-photolab";
    version = "0.3.0";
    port = 8262;
    vendorHash = "sha256-2TM41AOImtuxbOaWRkv4+wA3m8slP8/Injmaxk+tHLM=";
    npmDepsHash = "sha256-Cujn59FyT0LjYJYgIMGaBxuCTD1TxvTsCIfkvnLzfQE=";
  };

  photos = {
    title = "Pocket Photos";
    pname = "pocket-photos";
    input = "pocket-photos";
    version = "0.6.3";
    port = 8194;
    vendorHash = "sha256-2l4xE/U9dbbUNL9ANgr4iszIt7CPGojCAqV6yrFQOlY=";
    npmDepsHash = "sha256-rM3J3T1WLldCd4Iqw3ZmhtErzFkIob0/CwIu1tC8uJo=";
    runtime = pkgs: [ pkgs.ffmpeg-headless ];
  };

  places = {
    title = "Pocket Places";
    pname = "pocket-places";
    input = "pocket-places";
    version = "0.2.0";
    port = 8236;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-aPVtrKW53x29edajbeKqAbArnjmjnYNoegZwHBxNPzk=";
  };

  podcasts = {
    title = "Pocket Podcasts";
    pname = "pocket-podcasts";
    input = "pocket-podcasts";
    version = "0.5.1";
    port = 8181;
    vendorHash = "sha256-Bd6ly3H0isGvnYtK4ylwBQKHKLI/+Cd5SmWWQLCmGtw=";
    npmDepsHash = "sha256-nyncRXsUGd/hCH8BZiwtuZW96JkbPUSIfcqUosMx/sI=";
    runtime = pkgs: with pkgs; [ ffmpeg-headless yt-dlp deno ];
  };

  "pr-review" = {
    title = "Pocket PR Review";
    pname = "pocket-pr-review";
    input = "pocket-pr-review";
    version = "0.10.0";
    port = 8220;
    vendorHash = "sha256-ZogRbFxPAZ0o1JV7vQA0OoWU+zLtaI9f+3mzmFHNG4k=";
    npmDepsHash = "sha256-gfXmenNLofgIweOhYE3usg4hHnh8OU//Wcilvt8CnWw=";
  };

  projects = {
    title = "Pocket Projects";
    pname = "pocket-projects";
    input = "pocket-projects";
    version = "0.47.0";
    port = 8196;
    vendorHash = "sha256-cTI7//CWb9v4VaVs5ENNYjBoYPDXAv2La7HX2zZb1fk=";
    npmDepsHash = "sha256-4BkXWQ/ye82pdmw9IfumQ+jWT3CTXysxOpA6cI8hLRM=";
  };

  puzzlecraft = {
    title = "Pocket Puzzlecraft";
    pname = "pocket-puzzlecraft";
    input = "pocket-puzzlecraft";
    version = "0.2.0";
    port = 8266;
    vendorHash = "sha256-BbSNnGJTl9kFNeGdvhnljMgPqbCSL+YF50uyjswVK7o=";
    npmDepsHash = "sha256-0knVY/28qshtBpd9W5sY5wfN35yxnUOsm83ozeEVP+A=";
  };

  quest = {
    title = "Pocket Quest";
    pname = "pocket-quest";
    input = "pocket-quest";
    version = "0.2.0";
    port = 8264;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-SvhcbM3vzeTCSM2j7viJ3ICpwG4TXReWatrkjVNu914=";
  };

  radio = {
    title = "Pocket Radio";
    pname = "pocket-radio";
    input = "pocket-radio";
    version = "0.2.0";
    port = 8216;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-AzYQcVW6vaXzAYwgmfjaUJjjslwFHpUjiPxeDlc1J2Y=";
  };

  reader = {
    title = "Pocket Reader";
    pname = "pocket-reader";
    input = "pocket-reader";
    version = "0.2.0";
    port = 8211;
    vendorHash = "sha256-hAnn7tSEoS6hosnrInC5O62eHPMpEw1ommtiW/qT8u8=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  remote = {
    title = "Pocket Remote";
    pname = "pocket-remote";
    input = "pocket-remote";
    version = "0.4.1";
    port = 8259;
    vendorHash = "sha256-k61cVgVj4YbfUtjqfx1nLUQQryK7yRIsDocVUJocfjo=";
    npmDepsHash = "sha256-C/eL2qrSr8IunXu5eLF6aYQQZWwjUx0Bxe5oWepwSPM=";
    # VNC, RDP and SSH through guacd on the box (modules/services.nix).
    environment = { GUACD_ADDR = "127.0.0.1:4822"; };
  };

  renewals = {
    title = "Pocket Renewals";
    pname = "pocket-renewals";
    input = "pocket-renewals";
    version = "0.8.0";
    port = 8230;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-guJjvt4I1xxbF73/lHy2qIv3VTS3mrZwhrzKixJoGW4=";
  };

  rentals = {
    title = "Pocket Rentals";
    pname = "pocket-rentals";
    input = "pocket-rentals";
    version = "0.2.0";
    port = 8253;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  requests = {
    title = "Pocket Requests";
    pname = "pocket-requests";
    input = "pocket-requests";
    version = "0.11.0";
    port = 8210;
    # Requests go to the box's Radarr, Sonarr and Lidarr (modules/services.nix), through Pocket Core.
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-EF7X8qk+fReog1pzFKCgFN56Ud0bDVmN8DlH0Z73gso=";
  };

  review = {
    title = "Pocket Review";
    pname = "pocket-review";
    input = "pocket-review";
    version = "0.8.0";
    port = 8180;
    vendorHash = "sha256-CVo9GVS291C2Y1lgcuAmK59rfsB6/Nyscq3guF6CHys=";
    npmDepsHash = "sha256-R4VBjT/PtdtzLzOrxaY63Fg3qlIMO2qbjbxWTibAaY8=";
  };

  rooms = {
    title = "Pocket Rooms";
    pname = "pocket-rooms";
    input = "pocket-rooms";
    version = "0.2.0";
    port = 8265;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-xMmUcBhHsft6OF3AZ8LbUqzEvG96AsW2rXWJlG9TCyQ=";
  };

  search = {
    title = "Pocket Search";
    pname = "pocket-search";
    input = "pocket-search";
    version = "0.23.0";
    port = 8225;
    vendorHash = "sha256-s+R8e0B4S5BS+JWrqXoJkw/xQooGeyPmjXuK2xMVdNQ=";
    npmDepsHash = "sha256-P92MslwmlPt8N95dSjIZitFvWpSn8FTaNxltAMAEcEg=";
    # Results come from the box's own SearXNG on loopback (modules/services.nix).
    environment = { SEARXNG_URL = "http://127.0.0.1:8888"; };
  };

  sign = {
    title = "Pocket Sign";
    pname = "pocket-sign";
    input = "pocket-sign";
    version = "0.2.0";
    port = 8234;
    vendorHash = "sha256-FqJUGk0gkGPwgS1Gsj6dPyjT9kNbH0mP4WcoOLENVac=";
    npmDepsHash = "sha256-bXZD7OQBezcE8caXpO9mXDNXbd+3meXFI/xTC4gAdGU=";
  };

  sky = {
    title = "Pocket Sky";
    pname = "pocket-sky";
    input = "pocket-sky";
    version = "0.7.0";
    port = 8277;
    vendorHash = "sha256-cSnQPUaiBbY5pm6JP8ikENgrTXErANkhLwDjdj12AtA=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  slides = {
    title = "Pocket Slides";
    pname = "pocket-slides";
    input = "pocket-slides";
    version = "0.2.0";
    port = 8269;
    vendorHash = "sha256-qDUkGrgKh+0x4Hu+OSHt2FlrOqTSwIK5/C72S0420wY=";
    npmDepsHash = "sha256-YiVzc33Fr9TubK5g78mYoYjANIpx41R7P2G0JAQG4Qk=";
  };

  split = {
    title = "Pocket Split";
    pname = "pocket-split";
    input = "pocket-split";
    version = "0.9.0";
    port = 8172;
    vendorHash = "sha256-TgrJUw1DRMDUa4/y3BEJzmlL6vWpUFaOKyGLdFIhyKU=";
    npmDepsHash = "sha256-xPq4EltB1pyx8Lm9g0/PRsVqqwriA6IKNZ7ce4jkD/w=";
  };

  sphere = {
    title = "Pocket Sphere";
    pname = "pocket-sphere";
    input = "pocket-sphere";
    version = "0.6.0";
    port = 8227;
    vendorHash = "sha256-npCI3AfbvMmwhkjnHI5YsWPb7GFaulxynSQq1EXv6i8=";
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
    version = "0.2.0";
    port = 8206;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
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
    version = "0.3.0";
    port = 8252;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-zOJtN1I9lfQlX8+5f8iFk0EvzJlwMU495u2bTj+A390=";
  };

  tasks = {
    title = "Pocket Tasks";
    pname = "pocket-tasks";
    input = "pocket-tasks";
    version = "0.6.0";
    port = 8184;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-Jd1WgUWEe7ZLmRLzrBVrHSvbqFDnZiLSOqVvA7v5/1w=";
  };

  time = {
    title = "Pocket Time";
    pname = "pocket-time";
    input = "pocket-time";
    version = "0.2.0";
    port = 8219;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-IUfV0aYCkbPuBCCnr2zB+KlzfYC7Lobj1q+K8NsFeyk=";
  };

  trails = {
    title = "Pocket Trails";
    pname = "pocket-trails";
    input = "pocket-trails";
    version = "0.2.0";
    port = 8254;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-U+exrYitvtCMA5ncGMwnU8OHJnfK9M3pvelXlowPRKs=";
  };

  translate = {
    title = "Pocket Translate";
    pname = "pocket-translate";
    input = "pocket-translate";
    version = "0.2.1";
    port = 8251;
    vendorHash = "sha256-OvyQUG6geIFDHAw5H/T9OP5uB18KgRmnhqgSurV0M+s=";
    npmDepsHash = "sha256-TWtfA92MZXjLcv0IgvZw7OoUl/i2USWDAdXNoctaJn8=";
    # Reads PDFs and photos. Translates with Pocket AI, and offline once
    # pocket.box.services.libretranslate is on (modules/services.nix).
    runtime = pkgs: with pkgs; [ poppler-utils (tesseract.override { enableLanguages = ocrLanguages; }) ];
  };

  travel = {
    title = "Pocket Travel";
    pname = "pocket-travel";
    input = "pocket-travel";
    version = "0.14.0";
    port = 8174;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-1DgCVRSoFk8jcO5i+NgPIs5R1wfGFKaUnKd5BbexmhI=";
  };

  vault = {
    title = "Pocket Vault";
    pname = "pocket-vault";
    input = "pocket-vault";
    version = "0.2.0";
    port = 8271;
    vendorHash = "sha256-HY3CeI+RSP45Zl0lBKf+pATaIvfG4hBUVoDgPzzFTCE=";
    npmDepsHash = "sha256-RzTTNkDnnN9vHEF/RuJVepAZdXgIx2M9uM8WHC5Xhcw=";
  };

  voice = {
    title = "Pocket Voice";
    pname = "pocket-voice";
    input = "pocket-voice";
    version = "0.9.0";
    port = 8237;
    # ffmpeg reads any recording; whisper.cpp (whisper-cli and parakeet-cli) writes it out on the box.
    # The speech models are downloaded into /var/lib/pocket-voice/models when first chosen.
    runtime = pkgs: with pkgs; [ ffmpeg-headless whisper-cpp ];
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-ErYsF9rIQecEN0sYGq9EZSQ54Fy9MnZwOIFQEatnnTI=";
  };

  wallet = {
    title = "Pocket Wallet";
    pname = "pocket-wallet";
    input = "pocket-wallet";
    version = "0.2.0";
    port = 8238;
    vendorHash = "sha256-6Jxh4TatcSdtzgi0VVQHMdE+55nvzsp1fqyf/1mAWNU=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  wardrobe = {
    title = "Pocket Wardrobe";
    pname = "pocket-wardrobe";
    input = "pocket-wardrobe";
    version = "0.2.0";
    port = 8258;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-7H/p6i4P203zpCs4nK6kihq4uSC7t2HqG2sHAHnUous=";
  };

  watch = {
    title = "Pocket Watch";
    pname = "pocket-watch";
    input = "pocket-watch";
    version = "0.8.0";
    port = 8201;
    vendorHash = "sha256-21w7G9dPhQvr6lTmEQ5c5t85o/yZ+k+XkKd+m3LhUqw=";
    npmDepsHash = "sha256-iJULF2fqzlRKJ7Q88yR2fb9L/GH5stsYJx0GYsm/RyI=";
  };

  wealth = {
    title = "Pocket Wealth";
    pname = "pocket-wealth";
    input = "pocket-wealth";
    version = "0.3.0";
    port = 8231;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-l7WPLj+uETSp67Kx1ST3fyywCUkZfq4R0h36fb2wwF0=";
  };

  weather = {
    title = "Pocket Weather";
    pname = "pocket-weather";
    input = "pocket-weather";
    version = "0.4.0";
    port = 8239;
    vendorHash = "sha256-79zuzyNQu11Jm9VW1SZyolTiLG3gcq4d5Zv4GXvza94=";
    npmDepsHash = "sha256-gdJGeC2/yKxASHODiVBa2hQOHTSXunt83FfF52OcnEo=";
  };

  whiteboard = {
    title = "Pocket Whiteboard";
    pname = "pocket-whiteboard";
    input = "pocket-whiteboard";
    version = "0.5.0";
    port = 8270;
    vendorHash = "sha256-qDUkGrgKh+0x4Hu+OSHt2FlrOqTSwIK5/C72S0420wY=";
    npmDepsHash = "sha256-/bMFz5bpQ0rHmO8lVKO7SZTuKKtLRkEBSsI/53rvHt4=";
  };

  wishlist = {
    title = "Pocket Wishlist";
    pname = "pocket-wishlist";
    input = "pocket-wishlist";
    version = "0.5.0";
    port = 8198;
    vendorHash = "sha256-skH0r3sYQvgWNURv9LU98ktk3gQ+hO009MxrawpGVoc=";
    npmDepsHash = "sha256-EEYlm98eERnnG8qrW9GRBSLNQKvpXlNdFd76LjLsWrY=";
  };
}
