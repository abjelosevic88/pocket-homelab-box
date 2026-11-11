"""pocket-pick-apps: turns what someone picks in pocket-install into the box's app list.

  pocket-pick-apps CONFIG "office, media, notes"   → the apps, one per line (the base apps included)
  pocket-pick-apps CONFIG --lite "all"             → every app listed (Lite carries few, so "all" must be spelled out)
  pocket-pick-apps CONFIG --menu                   → the bundles, for the typed question
  pocket-pick-apps CONFIG --choose OUT [--lite]    → a checklist on the terminal; writes the words to OUT

Words are bundle ids (bundles.json), app slugs, "base" (nothing more) or "all". Unknown words fail with a
message, so a typo never silently drops an app. Prints nothing for "all" (every app the release has: no
list is kept), except with --lite, where it lists every app so the box downloads them all.

The checklist: bundles first (ticking one ticks its apps), then every app. ↑/↓ (PgUp/PgDn, Home/End)
move, Space ticks, + ticks all, - none, a letter jumps to the next app starting with it, Enter is done,
Esc goes back to the typed question (exit 3). The base apps stay ticked. On the full ISO everything
starts ticked.
"""
import json
import sys

CONFIG = json.load(open(sys.argv[1]))
BUNDLES = {b["id"]: b for b in CONFIG["bundles"]["bundles"]}
BASE = CONFIG["bundles"]["base"]
APPS = CONFIG["apps"]  # slug -> title


def menu():
    for b in CONFIG["bundles"]["bundles"]:
        print(f"  {b['id']:<11} {b['name']} ({len(b['apps'])} apps)")


def resolve(argv, lite=False):
    words = [w.strip().lower() for w in " ".join(argv).replace(",", " ").split() if w.strip()]
    if "all" in words:
        if lite:
            print("\n".join(s for s in sorted(APPS) if s != "core"))
        return 0
    words = [w for w in words if w != "base"]
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
        return 2
    seen = []
    for a in picked:
        if a not in seen and a != "core":
            seen.append(a)
    print("\n".join(seen))
    return 0


def short(slug):
    return APPS[slug].removeprefix("Pocket ")


def choose(out, lite):
    import curses
    import os

    os.environ.setdefault("ESCDELAY", "25")  # Esc answers at once, also on a serial console

    apps = sorted(APPS, key=lambda s: short(s).lower())
    rows = [("head", "Bundles: Space ticks all of a bundle's apps")]
    rows += [("bundle", b["id"]) for b in CONFIG["bundles"]["bundles"]]
    rows += [("head", f"Apps ({len(apps)})")]
    rows += [("app", s) for s in apps]
    picked = set(BASE) | (set() if lite else set(APPS))
    pickable = [i for i, r in enumerate(rows) if r[0] != "head"]
    state = {"cur": pickable[0], "top": 0, "note": ""}

    def bundle_mark(bid):
        members = set(BUNDLES[bid]["apps"])
        n = len(members & picked)
        return "x" if n == len(members) else ("-" if n else " ")

    def toggle(i):
        kind, key = rows[i]
        if kind == "bundle":
            members = set(BUNDLES[key]["apps"])
            if members <= picked:
                picked.difference_update(members - set(BASE))
            else:
                picked.update(members)
        elif key in BASE:
            state["note"] = f"{short(key)} is always on the box."
        elif key in picked:
            picked.discard(key)
        else:
            picked.add(key)

    def draw(scr):
        scr.erase()
        h, w = scr.getmaxyx()
        title = "Pocket Box: which apps? (Pocket Core always comes)"
        keys = "Space tick   + all   - none   letter: jump   Enter: install   Esc: type names instead"
        scr.addnstr(0, 0, title, w - 1, curses.A_BOLD)
        scr.addnstr(1, 0, keys, w - 1, curses.A_DIM)
        body = max(h - 5, 3)
        if state["cur"] < state["top"]:
            state["top"] = state["cur"]
        if state["cur"] >= state["top"] + body:
            state["top"] = state["cur"] - body + 1
        for n, i in enumerate(range(state["top"], min(len(rows), state["top"] + body))):
            kind, key = rows[i]
            y = 3 + n
            if kind == "head":
                scr.addnstr(y, 0, key.upper(), w - 1, curses.A_BOLD | curses.color_pair(2))
                continue
            if kind == "bundle":
                b = BUNDLES[key]
                mark = bundle_mark(key)
                text = f"  [{mark}] {b['name']} ({len(b['apps'])}): " + ", ".join(short(s) for s in b["apps"])
            else:
                mark = "x" if key in picked else " "
                text = f"  [{mark}] {short(key)}" + ("  (always)" if key in BASE else "")
            attr = curses.A_REVERSE if i == state["cur"] else 0
            if mark in "x-" and i != state["cur"]:
                attr |= curses.color_pair(1)
            scr.addnstr(y, 0, text.ljust(w - 1), w - 1, attr)
        everything = picked >= set(APPS)
        count = "every app" if everything else f"{len(picked)} apps"
        foot = f"Chosen: Pocket Core and {count}."
        if state["note"]:
            foot += "  " + state["note"]
        scr.addnstr(h - 1, 0, foot, w - 1, curses.A_BOLD)
        scr.refresh()

    def ui(scr):
        curses.curs_set(0)
        if curses.has_colors():
            curses.start_color()
            curses.use_default_colors()
            curses.init_pair(1, curses.COLOR_GREEN, -1)
            curses.init_pair(2, curses.COLOR_CYAN, -1)
        while True:
            draw(scr)
            k = scr.getch()
            state["note"] = ""
            at = pickable.index(state["cur"])
            h = scr.getmaxyx()[0]
            if k == curses.KEY_DOWN:
                state["cur"] = pickable[min(at + 1, len(pickable) - 1)]
            elif k == curses.KEY_UP:
                state["cur"] = pickable[max(at - 1, 0)]
            elif k == curses.KEY_NPAGE:
                state["cur"] = pickable[min(at + h - 6, len(pickable) - 1)]
            elif k == curses.KEY_PPAGE:
                state["cur"] = pickable[max(at - (h - 6), 0)]
            elif k == curses.KEY_HOME:
                state["cur"] = pickable[0]
            elif k == curses.KEY_END:
                state["cur"] = pickable[-1]
            elif k == ord(" "):
                toggle(state["cur"])
            elif k == ord("+"):
                picked.update(APPS)
            elif k == ord("-"):
                picked.intersection_update(BASE)
            elif k in (10, 13, curses.KEY_ENTER):
                return True
            elif k == 27:
                return False
            elif 0 < k < 256 and chr(k).isalpha():
                # Jump to the next app starting with that letter.
                c = chr(k).lower()
                order = pickable[at + 1:] + pickable[:at + 1]
                for i in order:
                    if rows[i][0] == "app" and short(rows[i][1]).lower().startswith(c):
                        state["cur"] = i
                        break

    if not curses.wrapper(ui):
        return 3
    words = ["all"] if picked >= set(APPS) else sorted(picked)
    with open(out, "w") as f:
        f.write(" ".join(words) + "\n")
    return 0


args = sys.argv[2:]
if args == ["--menu"]:
    menu()
    sys.exit(0)
if args[:1] == ["--choose"]:
    sys.exit(choose(args[1], "--lite" in args[2:]))
lite = "--lite" in args
sys.exit(resolve([a for a in args if a != "--lite"], lite))
