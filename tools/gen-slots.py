#!/usr/bin/env python3
"""Generate everything that has to agree about the slots.

Emits:
  plugin/Cells/.../CloudfitsHoldingCell     one persistent container per slot
  plugin/Globals/CloudfitsSlotState*.yaml   0 unnamed, 1 named and empty, 2 named and filled
  plugin/FormLists/*.yaml                   slot refs and states
  plugin/Messages/*.yaml                    store and wear pickers
  plugin/Quests/CloudfitsQuest              script properties and slot aliases
  mcm/Config/Cloudfits/config.json          a name field and an Empty button per slot
  mcm/Config/Cloudfits/settings.ini         defaults

Picker layout, which the script maps back by index:
  0 Cancel, 1..SLOTS the slots in order, SLOTS+1 Return equipped (wear only)
Slot buttons read "Slot N" in the plugin; the script relabels them with the names from MCM.
"""
import json, pathlib

REPO = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = REPO / "plugin"
MOD = "Cloudfits.esp"
MOD_INDEX = 0x01000000
SLOTS = 25

QUEST = 0x800
CONTAINER = 0x801
HOME_STATIC = 0x803
HOME_REF = 0x81F
SLOT_LIST = 0x820
STATE_LIST = 0x821
STORE_PICKER = 0x830
WEAR_PICKER = 0x831
STORE_MODE = 0x832
CHECKED_OUT = 0x84F
SLOT_REF0 = 0xA00
SLOT_STATE0 = 0xA40


def fk(i):
    return f"{i:06X}:{MOD}"


def record_path(folder, edid, fid):
    return PLUGIN / folder / f"{edid} - {fid:06X}_{MOD}.yaml"


def clear(folder, *prefixes):
    for p in prefixes:
        for old in (PLUGIN / folder).glob(p + "*"):
            old.unlink()


def condition(glob, value):
    return f"""  - MutagenObjectType: ConditionFloat
    ComparisonValue: {value}
    Data:
      MutagenObjectType: FunctionConditionData
      Function: GetGlobalValue
      ParameterOneRecord: {fk(glob)}
      ParameterOneNumber: {MOD_INDEX + glob}
"""


def button(text, conditions=""):
    out = f"""- Text:
    TargetLanguage: English
    Value: {text}
"""
    if conditions:
        out += "  Conditions:\n" + conditions
    return out


def message(edid, fid, title, buttons):
    record_path("Messages", edid, fid).write_text(f"""FormKey: {fk(fid)}
EditorID: {edid}
Description:
  TargetLanguage: English
  Value: {title}
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
clear("Globals", "CloudfitsSlotState")
for i in range(SLOTS):
    glob(f"CloudfitsSlotState{i + 1:02d}", SLOT_STATE0 + i)

# ---------------------------------------------------------------- formlists
formlist("CloudfitsSlotList", SLOT_LIST, [SLOT_REF0 + i for i in range(SLOTS)])
formlist("CloudfitsSlotStates", STATE_LIST, [SLOT_STATE0 + i for i in range(SLOTS)])

# ---------------------------------------------------------------- pickers
message("CloudfitsMsgStorePicker", STORE_PICKER, "Store into", [button("Cancel")] + [
    button(f"Slot {i + 1}", condition(SLOT_STATE0 + i, 1)) for i in range(SLOTS)])
message("CloudfitsMsgWearPicker", WEAR_PICKER, "Wear", [button("Cancel")] + [
    button(f"Slot {i + 1}", condition(SLOT_STATE0 + i, 2)) for i in range(SLOTS)]
    + [button("Return equipped", condition(CHECKED_OUT, 1))])

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


ct += "".join(placed(SLOT_REF0 + i, f"CloudfitsSlotRef{i + 1:02d}", CONTAINER, 64 * i) for i in range(SLOTS))
ct += placed(HOME_REF, "CloudfitsHomeRef", HOME_STATIC, -128)
cell.write_text(ct)

# ---------------------------------------------------------------- quest
props = {
    "CheckedOutFlag": CHECKED_OUT,
    "HomeMarker": HOME_REF,
    "SlotList": SLOT_LIST,
    "StateList": STATE_LIST,
    "StoreModePrompt": STORE_MODE,
    "StorePicker": STORE_PICKER,
    "WearPicker": WEAR_PICKER,
}
aliases = []
for i in range(SLOTS):
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
rows = [
    {"text": "Slot names", "type": "section"},
    {"text": "A slot appears in the menus once it has a name. A slot holding an outfit keeps its name until it is emptied.",
     "type": "text", "help": ""},
]
for i in range(SLOTS):
    rows.append({
        "id": f"sName{i + 1:02d}:Names",
        "text": f"Slot {i + 1}",
        "type": "textinput",
        "valueOptions": {"sourceType": "ModSettingString"},
        "help": f"Name shown for slot {i + 1}. Leave empty to keep the slot out of the menus.",
    })
rows += [
    {"type": "spacer", "numLines": 1},
    {"text": "Empty a slot into your inventory", "type": "section"},
    {"text": "Sends everything a slot holds to you, freeing it. Nothing is equipped.", "type": "text", "help": ""},
]
for i in range(SLOTS):
    rows.append({
        "text": f"Empty slot {i + 1}",
        "type": "button",
        "help": f"Moves the contents of slot {i + 1} into your inventory.",
        "action": {
            "type": "CallFunction",
            "form": f"{MOD}|{QUEST:X}",
            "scriptName": "Cloudfits:Manager",
            "function": "EmptySlot",
            "params": [f"{{i}}{i}"],
        },
    })
cfg["pages"][1]["pageDisplayName"] = "Slots"
cfg["pages"][1]["content"] = rows
cfg_path.write_text(json.dumps(cfg, indent=2) + "\n")

# written whole, so repeated runs cannot accumulate stale keys
(REPO / "mcm/Config/Cloudfits/settings.ini").write_text("\n".join(
    ["[Cloudfits]", "bLogging = 0", "", "[Slots]"] + [f"bSkip{s} = 1" for s in (53, 59, 60, 61)]
    + ["", "[Names]"] + [f"sName{i + 1:02d} = " for i in range(SLOTS)]) + "\n")

print(f"{SLOTS} slots")
