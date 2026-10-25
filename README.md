# Cloudfits

Up to twenty-five outfit slots for Fallout 4, named in MCM and driven by two hotkeys. One stores what
you are wearing, the other puts an outfit back on. Retrieving an outfit remembers where it came from,
so wearing a second one returns the first to its own slot.

A slot appears in the menus once it has a name. A slot holding an outfit keeps its name until it is
emptied.

## Requirements

- Fallout 4 Script Extender (F4SE)
- [Mod Configuration Menu](https://www.nexusmods.com/fallout4/mods/21497) - hotkeys and slot names
- The CommonLibF4RD Runtime Database, `F4SE/Plugins/f4rd-runtime.bin`, which `Cloudfits.dll` uses to
  find the game's functions on each runtime

`Cloudfits.dll` ships with the mod. It moves and equips the exact copy of each piece through the
game's own inventory functions, so a legendary or modded piece comes back as itself. It is built
against CommonLibF4RD for 1.10.163, 1.10.984 and 1.11.x, and so far tested only on 1.10.163.

`Cloudfits.esp` is esl-flagged and masters only `Fallout4.esm`.

## Layout

| path | what |
|---|---|
| `plugin/` | Spriggit YAML, the source of truth for `Cloudfits.esp` |
| `scripts/source/Cloudfits/` | Papyrus sources; `Plugin.psc` declares what `Cloudfits.dll` provides |
| `native/` | `Cloudfits.dll`, built against CommonLibF4RD |
| `native/patches/` | fixes applied to the CommonLibF4RD submodule at configure time |
| `mcm/Config/Cloudfits/` | MCM config |
| `tools/gen-slots.py` | regenerates the slot records, the pickers and the MCM page |

## Building

Clone with `--recursive`, or run `git submodule update --init`, for CommonLibF4RD.

The VS Code task **Build All** builds the plugin, compiles the scripts and stages the mod into
`build/stage` through the Dot ESP extension, after **Build Native** has built `Cloudfits.dll`.
**Package Cloudfits** zips the staged tree.

**Build Native** runs `cmake --workflow --preset release` in `native/`. It cross-builds on Linux with
clang-cl and lld-link against an xwin splat, and expects under `~/Projects/.toolchains`:

- `vcpkg/`, a bootstrapped vcpkg checkout
- `fo4-mcp-msvc/clang-cl-win64.cmake`, the toolchain file pointing at the splat

`native/triplets/` holds the vcpkg triplet for that toolchain. Configuring applies
`native/patches/` to the submodule, which leaves it showing as modified.

Do not add a terminal menu to `plugin/`: Spriggit 0.41 keeps only a terminal's first menu item and
drops the rest without reporting an error.

A message box returns garbage for any button index past 127, hidden buttons included, so neither
picker may grow beyond that.
