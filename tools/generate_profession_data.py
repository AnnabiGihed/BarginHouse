#!/usr/bin/env python3
"""
Build BargainHouse's ProfessionData.lua.

This is the whole pipeline that produced the file shipped with the addon. You
only need it to regenerate the data: for another server, another patch, or to
improve the handful of estimated thresholds.

    pip install dbcraft
    python3 generate_profession_data.py --dbc <folder> --world <world.sql[.gz]> \
        [--atlasloot <AtlasLoot_Crafting/crafting.lua>] [-o ProfessionData.lua]

Where each number comes from:

  SkillLineAbility.dbc  which profession a recipe belongs to, and where it turns
                        green and grey
  Spell.dbc             reagents, their quantities, what the craft produces
  world database        the skill you need to learn it, which the client files
                        do not carry: npc_trainer / npc_trainer_template,
                        item_template (recipes taught by an item),
                        skill_discovery_template, quest_template
  AtlasLoot (optional)  where each recipe comes from, by spell id

Anything still without a learn requirement is estimated from the gap between
orange and green measured on the recipes where both are known, and marked c=0
so the addon can show it as approximate and correct it in game.

Getting the .dbc files: extract DBFilesClient/SkillLineAbility.dbc and Spell.dbc
from your client's MPQ archives with any MPQ tool. A WotLK world database dump
(AzerothCore, TrinityCore or CMaNGOS) supplies the rest.
"""

import argparse
import collections
import gzip
import os
import re
import statistics
import sys

try:
    from dbcraft import DbcFile
except ImportError:
    sys.exit("dbcraft is needed:  pip install dbcraft")

PROFESSIONS = {171: "Alchemy", 164: "Blacksmithing", 333: "Enchanting", 202: "Engineering",
               773: "Inscription", 755: "Jewelcrafting", 165: "Leatherworking", 197: "Tailoring",
               186: "Mining", 185: "Cooking", 129: "First Aid"}
CREATE_ITEM_EFFECTS = (24, 157)

# Recipes a trainer teaches with no skill requirement at all: available the
# moment you pick the profession up. The world database records no requirement
# for them, which is correct, so they are listed here rather than estimated.
STARTER_SPELLS = {2393, 3397, 3915, 7751, 7752, 12044, 15935, 21143, 33276, 33277, 37836, 43779, 62050, 65454, 66038}


def open_maybe_gz(path):
    return gzip.open(path, "rt", encoding="utf-8", errors="replace") if path.endswith(".gz") \
        else open(path, "r", encoding="utf-8", errors="replace")


def split_row(raw):
    """split one SQL VALUES row, respecting quotes"""
    vals, cur, quoted, esc = [], "", False, False
    for ch in raw:
        if esc:
            cur += ch; esc = False; continue
        if ch == "\\":
            cur += ch; esc = True; continue
        if ch == "'":
            quoted = not quoted; cur += ch; continue
        if ch == "," and not quoted:
            vals.append(cur.strip()); cur = ""; continue
        cur += ch
    vals.append(cur.strip())
    return vals


def read_world(path):
    """the learn requirements the client files don't carry"""
    trainer, taught, discovery, quest = {}, {}, {}, {}
    columns, current = {}, None

    with open_maybe_gz(path) as f:
        for line in f:
            m = re.match(r"(?i)create table [`\"]?(\w+)", line)
            if m:
                current = m.group(1); columns[current] = []; continue
            if current:
                col = re.match(r"\s+`(\w+)`", line)
                if col:
                    columns[current].append(col.group(1)); continue
                if line.startswith(")"):
                    current = None

            m = re.match(r"(?i)insert\s+into\s+[`\"]?(\w+)", line)
            if not m:
                continue
            table = m.group(1)

            if table in ("npc_trainer", "npc_trainer_template"):
                for body in re.finditer(r"\(([^()]*)\)", line):
                    v = [x.strip() for x in body.group(1).split(",")]
                    if len(v) < 5:
                        continue
                    try:
                        spell, rank = int(v[1]), int(v[4])
                    except ValueError:
                        continue
                    if spell > 0 and rank > 0:
                        trainer[spell] = min(rank, trainer.get(spell, 1 << 30))

            elif table == "item_template":
                cols = columns.get("item_template", [])
                idx = {n: cols.index(n) for n in ("entry", "name", "RequiredSkillRank") if n in cols}
                pairs = [(cols.index("spellid_%d" % i), cols.index("spelltrigger_%d" % i))
                         for i in range(1, 6)
                         if "spellid_%d" % i in cols and "spelltrigger_%d" % i in cols]
                if len(idx) < 3 or not pairs:
                    continue
                for body in re.finditer(r"\(((?:[^()']|'(?:[^'\\]|\\.)*')*)\)", line):
                    v = split_row(body.group(1))
                    if len(v) <= max(max(p) for p in pairs):
                        continue
                    try:
                        entry, rank = int(v[idx["entry"]]), int(v[idx["RequiredSkillRank"]])
                        name = v[idx["name"]].strip("'").replace("\\'", "'")
                    except ValueError:
                        continue
                    if rank <= 0:
                        continue
                    for sp_i, tr_i in pairs:
                        try:
                            spell, trigger = int(v[sp_i]), int(v[tr_i])
                        except ValueError:
                            continue
                        if spell > 0 and trigger == 6:          # the "learn" trigger
                            prev = taught.get(spell)
                            if not prev or rank < prev[1]:
                                taught[spell] = (entry, rank, name)

            elif table == "skill_discovery_template":
                for body in re.finditer(r"\(([^()]*)\)", line):
                    v = [x.strip() for x in body.group(1).split(",")]
                    try:
                        spell, rank = int(v[0]), int(v[2])
                    except (ValueError, IndexError):
                        continue
                    if spell > 0 and rank > 0:
                        discovery[spell] = min(rank, discovery.get(spell, 1 << 30))

            elif table == "quest_template":
                cols = columns.get("quest_template", [])
                if "RequiredSkillValue" not in cols:
                    continue
                need = cols.index("RequiredSkillValue")
                rewards = [cols.index(n) for n in ("RewSpell", "RewSpellCast") if n in cols]
                if not rewards:
                    continue
                for body in re.finditer(r"\(((?:[^()']|'(?:[^'\\]|\\.)*')*)\)", line):
                    v = split_row(body.group(1))
                    if len(v) <= max([need] + rewards):
                        continue
                    try:
                        rank = int(v[need])
                    except ValueError:
                        continue
                    if rank <= 0:
                        continue
                    for r in rewards:
                        try:
                            spell = int(v[r])
                        except ValueError:
                            continue
                        if spell > 0:
                            quest[spell] = min(rank, quest.get(spell, 1 << 30))

    print("  world database: %d trainer, %d item-taught, %d discovery, %d quest requirements"
          % (len(trainer), len(taught), len(discovery), len(quest)))
    return trainer, taught, discovery, quest


def read_atlasloot(path):
    """where each recipe comes from, keyed by spell id"""
    if not path or not os.path.exists(path):
        return {}
    text = open(path, encoding="utf-8", errors="replace").read()
    out = {}
    for m in re.finditer(r'\{\s*\d+,\s*"s(\d+)",\s*"(\d*)",\s*"([^"]*)",\s*"=ds="(.*?)\}', text):
        words = [a or b for a, b in re.findall(r'AL\["([^"]+)"\]|Babble\w+\["([^"]+)"\]', m.group(4))]
        if words:
            out[int(m.group(1))] = ", ".join(words)
    print("  AtlasLoot: sources for %d recipes" % len(out))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dbc", required=True, help="folder with SkillLineAbility.dbc and Spell.dbc")
    ap.add_argument("--world", help="world database dump (.sql or .sql.gz) for the skill requirements")
    ap.add_argument("--atlasloot", help="AtlasLoot_Crafting/crafting.lua, for recipe sources")
    ap.add_argument("--starters", help="extra file of spell ids known to be available at skill 1")
    ap.add_argument("--locale", default="en_us")
    ap.add_argument("-o", "--out", default="ProfessionData.lua")
    args = ap.parse_args()

    def find(name):
        for entry in os.listdir(args.dbc):
            if entry.lower() == name.lower():
                return os.path.join(args.dbc, entry)
        sys.exit("%s not found in %s" % (name, args.dbc))

    print("reading the client files")
    sla = DbcFile.read(find("SkillLineAbility.dbc"))
    spells = {s.id: s for s in DbcFile.read(find("Spell.dbc")).records}
    print("  %d skill line abilities, %d spells" % (len(sla.records), len(spells)))

    trainer, taught, discovery, quest = {}, {}, {}, {}
    if args.world:
        print("reading the world database (this takes a minute)")
        trainer, taught, discovery, quest = read_world(args.world)
    atlas = read_atlasloot(args.atlasloot)

    starters = set(STARTER_SPELLS)
    if args.starters and os.path.exists(args.starters):
        starters |= {int(x) for x in re.findall(r"\d+", open(args.starters).read())}

    crafts = []
    for a in sla.records:
        prof = PROFESSIONS.get(a.skill_line)
        if not prof:
            continue
        sp = spells.get(a.spell)
        if not sp:
            continue
        reagents = [(getattr(sp, "reagent_%d" % i), getattr(sp, "reagent_count_%d" % i)) for i in range(8)]
        reagents = [(i, c) for i, c in reagents if i and i > 0 and c and c > 0]
        if not reagents:
            continue                     # gathering abilities and the like
        crafts.append((prof, a, sp, reagents))

    def learn_skill(spell, a):
        return max(a.min_skill_line_rank, trainer.get(spell, 0), taught.get(spell, (0, 0, ""))[1],
                   discovery.get(spell, 0), quest.get(spell, 0))

    # how far below green the orange point usually sits, measured where both are known
    gaps, ratios = collections.defaultdict(list), []
    for prof, a, sp, _ in crafts:
        o = learn_skill(a.spell, a)
        g, x = a.trivial_skill_line_rank_low, a.trivial_skill_line_rank_high
        if o > 1 and g > o:
            gaps[prof].append(g - o)
            if x > g:
                ratios.append((g - o) / (x - g))
    median_gap = {p: statistics.median(v) for p, v in gaps.items()}
    median_ratio = statistics.median(ratios) if ratios else 0.62

    out = collections.defaultdict(list)
    where_from = collections.Counter()
    for prof, a, sp, reagents in crafts:
        made_item, made = 0, 1
        for i in range(3):
            if getattr(sp, "effect_%d" % i) in CREATE_ITEM_EFFECTS:
                made_item = getattr(sp, "effect_item_type_%d" % i) or 0
                made = max(1, (getattr(sp, "effect_base_points_%d" % i) or 0) +
                           (getattr(sp, "effect_die_sides_%d" % i) or 1))
                break

        green, grey = a.trivial_skill_line_rank_low, a.trivial_skill_line_rank_high
        orange = learn_skill(a.spell, a)
        confirmed = 1
        if orange > 1:
            where_from["trainer" if a.spell in trainer else
                       "recipe item" if a.spell in taught else
                       "discovery" if a.spell in discovery else
                       "quest" if a.spell in quest else "client"] += 1
        elif green <= 1 or a.spell in starters:
            orange, confirmed = 1, 1
            where_from["available from the start"] += 1
        else:
            by_gap = green - median_gap.get(prof, 15)
            by_ratio = green - median_ratio * (grey - green) if grey > green else by_gap
            orange = max(1, round((by_gap + by_ratio) / 2))
            confirmed = 0
            where_from["estimated"] += 1

        # the bands must stay in order: some recipes are learned above their green
        green = max(green, orange)
        grey = max(grey, green)
        yellow = min(max(orange + (green - orange) // 2, orange), green)

        source = ("trainer" if a.spell in trainer else None) or atlas.get(a.spell) or \
                 ("discovery" if a.spell in discovery else "quest" if a.spell in quest else
                  "item" if a.spell in taught else "unknown")
        out[prof].append(dict(s=a.spell, n=getattr(sp.name_lang, args.locale, "") or "",
                              i=made_item, m=made, o=orange, y=yellow, g=green, x=grey,
                              ri=taught.get(a.spell, (0,))[0], c=confirmed, src=source, r=reagents))

    def esc(t):
        return t.replace("\\", "\\\\").replace('"', '\\"')

    lines = ["-- Profession data for BargainHouse (WoW 3.3.5a).",
             "-- Generated by tools/generate_profession_data.py - do not edit by hand.",
             "--   thresholds and reagents: client SkillLineAbility.dbc and Spell.dbc",
             "--   skill requirements:      trainers, recipe items, discovery and quests",
             "--   recipe sources:          AtlasLoot, when installed",
             "--",
             "-- Held as text and unpacked only for the profession you are planning, so a",
             "-- client that never opens the Level up tab pays almost nothing for it.",
             "-- Fields per line, tab separated:",
             "--   spell  name  item made  count  orange  yellow  green  grey  recipe item",
             "--   confirmed(1/0)  where it comes from  reagents as id:count,id:count",
             "local ADDON, ns = ...", "",
             "ns.ProfessionData = {"]
    total = confirmed_total = 0
    for prof in sorted(out):
        recipes = sorted(out[prof], key=lambda r: (r["o"], r["n"]))
        total += len(recipes)
        confirmed_total += sum(1 for r in recipes if r["c"])
        lines.append('  ["%s"] = [==[' % prof)
        for r in recipes:
            lines.append("\t".join([str(r["s"]), r["n"].replace("\t", " "), str(r["i"]), str(r["m"]),
                                    str(r["o"]), str(r["y"]), str(r["g"]), str(r["x"]), str(r["ri"]),
                                    str(r["c"]), r["src"].replace("\t", " "),
                                    ",".join("%d:%d" % (i, c) for i, c in r["r"])]))
        lines.append("]==],")
    lines.append("}")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print("\nwrote %s  (%.0f KB)" % (args.out, os.path.getsize(args.out) / 1024))
    print("  %d recipes, %d with a confirmed skill requirement (%.1f%%)"
          % (total, confirmed_total, 100.0 * confirmed_total / total))
    for k, v in where_from.most_common():
        print("    %-26s %d" % (k, v))
    for prof in sorted(out):
        print("  %-16s %4d" % (prof, len(out[prof])))


if __name__ == "__main__":
    main()
