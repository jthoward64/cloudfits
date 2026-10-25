# Cloudfits

Twenty-nine named outfit slots for Fallout 4, in four categories (Armor, Clothing, Faction, Utility),
driven by two hotkeys. One stores what you are wearing, the other puts an outfit back on. Retrieving
an outfit remembers where it came from, so wearing a second one returns the first to its own slot.

## Requirements

- Fallout 4 Script Extender (F4SE)
- [Garden of Eden Papyrus Script Extender](https://www.nexusmods.com/fallout4/mods/74160) - supplies
  instance-accurate inventory transfers, so a legendary or modded piece comes back as itself, and
  the flags that say an item is a quest item or equip-locked by another mod
- [Mod Configuration Menu](https://www.nexusmods.com/fallout4/mods/21497) - hotkeys and slot names

`Cloudfits.esp` is esl-flagged and masters only `Fallout4.esm`.

## Layout

| path | what |
|---|---|
| `plugin/` | Spriggit YAML, the source of truth for `Cloudfits.esp` |
| `scripts/source/Cloudfits/` | Papyrus sources |
| `mcm/Config/Cloudfits/` | MCM config |
| `names.json` | the categories and their slots |
| `tools/gen-slots.py` | regenerates every record, the MCM page and `Names.psc` from `names.json` |
| `tools/build.sh` | builds the plugin, compiles scripts, stages an installable tree |

## Building

`tools/build.sh` needs the Spriggit CLI at `~/Projects/.toolchains/spriggit`, the Creation Kit's
Papyrus compiler plus the extracted vanilla sources at `~/Projects/.toolchains/papyrus`, and the
`org.winehq.Wine` flatpak with its mono extension. Override locations with `CLOUDFITS_TOOLCHAINS` and
`FO4_DATA`. Output lands in `build/stage` as a Data-relative tree.

Do not add a terminal menu to `plugin/`: Spriggit 0.41 keeps only a terminal's first menu item and
drops the rest without reporting an error.
