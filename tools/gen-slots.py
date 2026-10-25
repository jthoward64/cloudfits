#!/usr/bin/env python3
"""Generate everything that has to agree about the slots, from names.json.

Emits:
  plugin/Cells/.../CloudfitsHoldingCell     one persistent container per slot
  plugin/Globals/CloudfitsSlotState*.yaml   0 empty, 1 filled
  plugin/Globals/CloudfitsCount*.yaml       filled slots per category
  plugin/FormLists/*.yaml                   slot refs, states, counts, slot menus
  plugin/Messages/*.yaml                    category menus and one slot menu per category and mode
  plugin/Quests/CloudfitsQuest              script properties and slot aliases
  mcm/Config/Cloudfits/config.json          one Empty button per slot
  scripts/source/Cloudfits/Names.psc        the same layout for Papyrus

Menu layout, which the script maps back by index:
  category menu  0 Cancel, 1..4 categories, 5 Return equipped (wear only)
  slot menu      0 Back, 1..N the category's slots in order
"""
import json, pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = REPO / "plugin"
MOD = "Cloudfits.esp"
MOD_INDEX = 0x01000000

QUEST = 0x800
CONTAINER = 0x801
HOME_REF = 0x81F
SLOT_LIST = 0x820
STATE_LIST = 0x821
STORE_PICKER = 0x830
WEAR_PICKER = 0x831
STORE_MODE = 0x832
CHECKED_OUT = 0x84F
SLOT_REF0 = 0xA00
SLOT_STATE0 = 0xA40
COUNT0 = 0xA60
STORE_MENU0 = 0xA70
WEAR_MENU0 = 0xA74
STORE_MENUS = 0xA80
WEAR_MENUS = 0xA81
COUNT_LIST = 0xA82

data = json.loads((REPO / "names.json").read_text())
categories = data["categories"]
slots = [s for c in categories for s in c["slots"]]
starts = [sum(len(x["slots"]) for x in categories[:c]) for c in range(len(categories))]
assert len(categories) == 4, "the category menus have four fixed buttons"
assert len(slots) <= SLOT_STATE0 - SLOT_REF0


def fk(i):
    return f"{i:06X}:{MOD}"


def record_path(folder, edid, fid):
    return PLUGIN / folder / f"{edid} - {fid:06X}_{MOD}.yaml"


def clear(folder, *prefixes):
    for p in prefixes:
        for old in (PLUGIN / folder).glob(p + "*"):
            old.unlink()


def scalar(text):
    # plain YAML scalars cannot hold ': ' or ' #'
    return json.dumps(text) if ": " in text or " #" in text else text


def condition(glob, value, op=None):
    out = f"""  - MutagenObjectType: ConditionFloat
"""
    if op:
        out += f"    CompareOperator: {op}\n"
    out += f"""    ComparisonValue: {value}
    Data:
      MutagenObjectType: FunctionConditionData
      Function: GetGlobalValue
      ParameterOneRecord: {fk(glob)}
      ParameterOneNumber: {MOD_INDEX + glob}
"""
    return out


def button(text, conditions=""):
    out = f"""- Text:
    TargetLanguage: English
    Value: {scalar(text)}
"""
    if conditions:
        out += "  Conditions:\n" + conditions
    return out


def message(edid, fid, title, buttons):
    record_path("Messages", edid, fid).write_text(f"""FormKey: {fk(fid)}
EditorID: {edid}
Description:
  TargetLanguage: English
  Value: {scalar(title)}
Name:
  TargetLanguage: English
  Value: Cloudfits
OwnerQuest: {fk(QUEST)}
Flags:
- MessageBox
MenuButtons:
""" + "".join(buttons))


def formlist(edid, fid, items):
    record_path("FormLists", edid, fid).write_text(
        f"FormKey: {fk(fid)}\nEditorID: {edid}\nItems:\n" + "".join(f"- {fk(i)}\n" for i in items))


def glob(edid, fid):
    record_path("Globals", edid, fid).write_text(
        f"MutagenObjectType: GlobalShort\nFormKey: {fk(fid)}\nEditorID: {edid}\nData: 0\n")


# ---------------------------------------------------------------- globals
clear("Globals", "CloudfitsSlotState", "CloudfitsSlotLabel", "CloudfitsCount")
for i in range(len(slots)):
    glob(f"CloudfitsSlotState{i + 1:02d}", SLOT_STATE0 + i)
for c, cat in enumerate(categories):
    glob(f"CloudfitsCount{cat['name']}", COUNT0 + c)

# ---------------------------------------------------------------- formlists
clear("FormLists", "CloudfitsSlotLabels", "CloudfitsStoreMenus", "CloudfitsWearMenus", "CloudfitsCategoryCounts")
formlist("CloudfitsSlotList", SLOT_LIST, [SLOT_REF0 + i for i in range(len(slots))])
formlist("CloudfitsSlotStates", STATE_LIST, [SLOT_STATE0 + i for i in range(len(slots))])
formlist("CloudfitsCategoryCounts", COUNT_LIST, [COUNT0 + c for c in range(len(categories))])
formlist("CloudfitsStoreMenus", STORE_MENUS, [STORE_MENU0 + c for c in range(len(categories))])
formlist("CloudfitsWearMenus", WEAR_MENUS, [WEAR_MENU0 + c for c in range(len(categories))])

# ---------------------------------------------------------------- menus
clear("Messages", "CloudfitsMsgStorePicker", "CloudfitsMsgWearPicker",
      *(f"CloudfitsMsg{m}{c['name']} " for m in ("Store", "Wear") for c in categories))
# a store menu hides a full category, a wear menu an empty one
message("CloudfitsMsgStorePicker", STORE_PICKER, "Store into", [button("Cancel")] + [
    button(cat["name"], condition(COUNT0 + c, len(cat["slots"]), "LessThan"))
    for c, cat in enumerate(categories)])
message("CloudfitsMsgWearPicker", WEAR_PICKER, "Wear from", [button("Cancel")] + [
    button(cat["name"], condition(COUNT0 + c, 0, "GreaterThan"))
    for c, cat in enumerate(categories)] + [button("Return equipped", condition(CHECKED_OUT, 1))])
for c, cat in enumerate(categories):
    for stem, fid0, title, wanted in (("Store", STORE_MENU0, "store into", 0), ("Wear", WEAR_MENU0, "wear from", 1)):
        message(f"CloudfitsMsg{stem}{cat['name']}", fid0 + c, f"{cat['name']}: slot to {title}", [button("Back")] + [
            button(name, condition(SLOT_STATE0 + starts[c] + j, wanted))
            for j, name in enumerate(cat["slots"])])

# ---------------------------------------------------------------- holding cell
cell = next(PLUGIN.glob("Cells/1/0/CloudfitsHoldingCell*/RecordData.yaml"))
ct = cell.read_text()
ct = ct[:ct.index("Persistent:\n")] + "Persistent:\n"


def placed(fid, edid, base, x):
    out = f"""- MutagenObjectType: PlacedObject
  FormKey: {fk(fid)}
  MajorRecordFlagsRaw: 1024
  EditorID: {edid}
  Fallout4MajorRecordFlags:
  - 0x400
  Base: {fk(base)}
"""
    if x:
        out += f"  Position: {x}, 0, 0\n"
    return out


ct += "".join(placed(SLOT_REF0 + i, f"CloudfitsSlotRef{i + 1:02d}", CONTAINER, 64 * i) for i in range(len(slots)))
ct += placed(HOME_REF, "CloudfitsHomeRef", 0x803, -128)
cell.write_text(ct)

# ---------------------------------------------------------------- quest
props = {
    "CheckedOutFlag": CHECKED_OUT,
    "CategoryCounts": COUNT_LIST,
    "HomeMarker": HOME_REF,
    "SlotList": SLOT_LIST,
    "StateList": STATE_LIST,
    "StoreModePrompt": STORE_MODE,
    "StorePicker": STORE_PICKER,
    "WearPicker": WEAR_PICKER,
    "StoreMenus": STORE_MENUS,
    "WearMenus": WEAR_MENUS,
}
aliases = []
for i in range(len(slots)):
    alias = "- MutagenObjectType: QuestReferenceAlias\n"
    if i:
        alias += f"  ID: {i}\n"
    alias += f"""  Name: Slot{i + 1:02d}
  Flags:
  - Optional
  - AllowReuseInQuest
  - AllowDisabled
  - StoresText
  - UsesStoredText
  - ClearNamesWhenRemoved
  ForcedReference: {fk(SLOT_REF0 + i)}
  VoiceTypes: Null
"""
    aliases.append(alias)
quest = next(PLUGIN.glob("Quests/CloudfitsQuest*/RecordData.yaml"))
quest.write_text(f"""FormKey: {fk(QUEST)}
EditorID: CloudfitsQuest
VirtualMachineAdapter:
  Scripts:
  - Name: Cloudfits:Manager
    Properties:
""" + "".join(f"""    - MutagenObjectType: ScriptObjectProperty
      Name: {name}
      Object: {fk(fid)}
""" for name, fid in props.items()) + """  Versioning:
  - Break0
  ExtraBindDataVersion: 0
  Script:
    Name: ''
Name:
  TargetLanguage: English
  Value: Cloudfits
Data:
  Flags:
  - StartGameEnabled
  - StartsEnabled
  Priority: 80
UnusedConditions: []
Aliases:
""" + "".join(aliases))

# ---------------------------------------------------------------- MCM
cfg_path = REPO / "mcm/Config/Cloudfits/config.json"
cfg = json.loads(cfg_path.read_text())
main = cfg["pages"][0]
main["pageDisplayName"] = "Hotkeys"
content = [c for c in main["content"] if not c.get("id", "").startswith("iName")]
# the names section and the spacer after it
for i, c in enumerate(content):
    if c.get("text") == "Slot names":
        del content[i:i + 2]
        break
main["content"] = content

rows = [
    {"text": "Empty a slot into your inventory", "type": "section"},
    {"text": "Sends everything a slot holds to you, freeing it. Nothing is equipped.", "type": "text", "help": ""},
]
for c, cat in enumerate(categories):
    rows.append({"type": "spacer", "numLines": 1})
    rows.append({"text": cat["name"], "type": "section"})
    for j, name in enumerate(cat["slots"]):
        rows.append({
            "text": f"Empty {name}",
            "type": "button",
            "help": f"Moves the contents of {name} into your inventory.",
            "action": {
                "type": "CallFunction",
                "form": f"{MOD}|{QUEST:X}",
                "scriptName": "Cloudfits:Manager",
                "function": "EmptySlot",
                "params": [f"{{i}}{starts[c] + j}"],
            },
        })
cfg["pages"][1]["content"] = rows
cfg_path.write_text(json.dumps(cfg, indent=2) + "\n")

# written whole, so repeated runs cannot accumulate stale keys
(REPO / "mcm/Config/Cloudfits/settings.ini").write_text("\n".join(
    ["[Cloudfits]", "bLogging = 0", "", "[Slots]"] + [f"bSkip{s} = 1" for s in (53, 59, 60, 61)]) + "\n")

# ---------------------------------------------------------------- Papyrus side
def psc_array(kind, name, values, fmt):
    out = [f"{kind}[] Function {name}() global", f"\t{kind}[] v = new {kind}[{len(values)}]"]
    out += [f"\tv[{i}] = {fmt(x)}" for i, x in enumerate(values)]
    out += ["\treturn v", "EndFunction", ""]
    return "\n".join(out)


psc = ["Scriptname Cloudfits:Names Hidden",
       "{Generated by tools/gen-slots.py from names.json. Do not edit by hand.}", ""]
psc.append(psc_array("string", "Slots", slots, lambda s: f'"{s}"'))
psc.append(psc_array("int", "CategoryStart", starts, str))
psc.append(psc_array("int", "CategorySize", [len(c["slots"]) for c in categories], str))
(REPO / "scripts/source/Cloudfits/Names.psc").write_text("\n".join(psc))

print(f"{len(slots)} slots in {len(categories)} categories: "
      + ", ".join(f"{c['name']} {len(c['slots'])}" for c in categories))
