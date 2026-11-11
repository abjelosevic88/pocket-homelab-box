"""pocket-pick-apps: turns what someone types in pocket-install into the box's app list.

  pocket-pick-apps "office, media, notes"  → the apps, one per line (the base apps included)
  pocket-pick-apps --menu                  → the bundles, for the question

Words are bundle ids (bundles.json), app slugs or "all". Unknown words fail with a message, so a typo
never silently drops an app. Prints nothing for "all" (every app the release has: no list is kept).
"""
import json
import sys

CONFIG = json.load(open(sys.argv[1]))
BUNDLES = {b["id"]: b for b in CONFIG["bundles"]["bundles"]}
BASE = CONFIG["bundles"]["base"]
APPS = CONFIG["apps"]  # slug -> title

if sys.argv[2:] == ["--menu"]:
    for b in CONFIG["bundles"]["bundles"]:
        print(f"  {b['id']:<11} {b['name']} ({len(b['apps'])} apps)")
    sys.exit(0)

words = [w.strip().lower() for w in " ".join(sys.argv[2:]).replace(",", " ").split() if w.strip()]
if "all" in words:
    sys.exit(0)
picked, unknown = list(BASE), []
for w in words:
    if w in BUNDLES:
        picked += BUNDLES[w]["apps"]
    elif w in APPS:
        picked.append(w)
    elif w.startswith("pocket-") and w[7:] in APPS:
        picked.append(w[7:])
    else:
        unknown.append(w)
if unknown:
    msg = "Not a bundle or app: " + ", ".join(unknown) + ". Bundles: " + ", ".join(BUNDLES) + ". Apps: pockethomelab.com/apps"
    print(msg, file=sys.stderr)
    sys.exit(2)
seen = []
for a in picked:
    if a not in seen and a != "core":
        seen.append(a)
print("\n".join(seen))
