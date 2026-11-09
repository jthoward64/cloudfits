; SPDX-FileCopyrightText: 2026 Tag Howard <tag@jthoward.dev>
;
; SPDX-License-Identifier: GPL-3.0-only

Scriptname Cloudfits:Manager extends Quest
{Outfit slots named in MCM, driven by two hotkeys.}

FormList Property SlotList Auto Const Mandatory
FormList Property StateList Auto Const Mandatory
ObjectReference Property HomeMarker Auto Const Mandatory
GlobalVariable Property CheckedOutFlag Auto Const Mandatory
Message Property StorePicker Auto Const Mandatory
Message Property WearPicker Auto Const Mandatory
Message Property StoreModePrompt Auto Const Mandatory

; formIDs taken out of CheckedOutSlot; empty whenever CheckedOutSlot is -1
int[] CheckedOutIDs
int CheckedOutSlot = -1
bool[] Occupied
int[] LastSlotState
; names last read from MCM, "" for a slot that is off
string[] SlotNames
; container pulled out of the holding cell, for the trade window or for item work
ObjectReference BorrowedContainer
int BorrowedSlot = -1
bool Busy = false
float BusySince = 0.0
bool Logging = false
bool PluginReady = false
; body slots the player chose to leave alone
int[] SkipSlots

; writes Logs/Script/User/Cloudfits.0.log once Papyrus logging is on in Fallout4Custom.ini
string Property LogName = "Cloudfits" AutoReadOnly Hidden
; long enough for another mod's unequip handler to re-equip what it owns
float Property SettleWait = 1.5 AutoReadOnly Hidden

Event OnQuestInit()
	ResetTracking()
	Bind()
EndEvent

Event Actor.OnPlayerLoadGame(Actor akSender)
	Bind()
EndEvent

Function Bind()
	Actor player = Game.GetPlayer()
	If CheckedOutIDs == None
		ResetTracking()
	EndIf
	; a save made by an older build can carry these at a different slot count
	int slotCount = SlotList.GetSize()
	If Occupied == None || Occupied.Length != slotCount
		Occupied = new bool[1]
		Occupied.Clear()
		While Occupied.Length < slotCount
			Occupied.Add(false)
		EndWhile
	EndIf
	If SlotNames == None || SlotNames.Length != slotCount
		SlotNames = new string[1]
		SlotNames.Clear()
		While SlotNames.Length < slotCount
			SlotNames.Add("")
		EndWhile
	EndIf
	; -1 forces every state global to be written once, whatever an older build left in them
	LastSlotState = new int[1]
	LastSlotState.Clear()
	While LastSlotState.Length < slotCount
		LastSlotState.Add(-1)
	EndWhile
	CacheOccupancy()
	If CheckedOutFlag
		CheckedOutFlag.SetValueInt((CheckedOutSlot >= 0) as int)
	EndIf
	Busy = false
	BorrowedContainer = None
	BorrowedSlot = -1
	StowContainers()
	RegisterForExternalEvent("OnMCMSettingChange|Cloudfits", "OnMCMSettingChange")
	RegisterForRemoteEvent(player, "OnPlayerLoadGame")
	RegisterForRemoteEvent(player, "OnItemUnequipped")
	RegisterForMenuOpenCloseEvent("ContainerMenu")
	RegisterForMenuOpenCloseEvent("ExamineMenu")
	Debug.OpenUserLog(LogName)
	PluginReady = Cloudfits:Plugin.Version() > 0
	RefreshSettings()
	If PluginReady
		; button labels live on the message forms, which the game rebuilds from the plugin at startup
		RefreshNames(true)
	Else
		Debug.Notification("Cloudfits needs Cloudfits.dll and the Runtime Database in F4SE/Plugins.")
	EndIf
	Log("bind: plugin=" + PluginReady + " logging=" + Logging + " slots=" + slotCount)
EndFunction

Function OnMCMSettingChange(string asModName, string asId)
	If asModName == "Cloudfits"
		RefreshSettings()
		If PluginReady
			RefreshNames(false)
		EndIf
	EndIf
EndFunction

Function CacheOccupancy()
	int i = 0
	While i < SlotList.GetSize()
		Occupied[i] = SlotRef(i).GetItemCount(None) > 0
		i += 1
	EndWhile
EndFunction

; a container only goes home when the trade window closes, so anything left parked next to the
; player (quit with the window open, say) gets sent back on load
Function StowContainers()
	int i = 0
	While i < SlotList.GetSize()
		ObjectReference slotRef = SlotRef(i)
		If slotRef && slotRef.GetParentCell() != HomeMarker.GetParentCell()
			slotRef.MoveTo(HomeMarker)
			Log("stow: slot=" + i + " was left out, sent home")
		EndIf
		i += 1
	EndWhile
EndFunction

Function MarkSlotByRef(ObjectReference akRef)
	int i = 0
	While i < SlotList.GetSize()
		If SlotRef(i) == akRef
			MarkSlot(i)
			Return
		EndIf
		i += 1
	EndWhile
EndFunction

; one count, after we changed a slot ourselves
Function MarkSlot(int aiSlot)
	If aiSlot >= 0 && aiSlot < SlotList.GetSize()
		Occupied[aiSlot] = SlotRef(aiSlot).GetItemCount(None) > 0
	EndIf
EndFunction

Function RefreshSettings()
	If MCM.GetModSettingBool("Cloudfits", "bLogging:Cloudfits")
		Logging = true
	EndIf
	; Slot numbers classify nothing reliably here: 60 holds the Pip-Boy but also power armour
	; frames, 61 holds scene props, 59 holds creature skins and real wearables alike. So which
	; slots to protect is the player's call, defaulting to all four.
	int[] slots = new int[1]
	slots.Clear()
	If MCM.GetModSettingBool("Cloudfits", "bSkip53:Slots")
		slots.Add(53)
	EndIf
	If MCM.GetModSettingBool("Cloudfits", "bSkip59:Slots")
		slots.Add(59)
	EndIf
	If MCM.GetModSettingBool("Cloudfits", "bSkip60:Slots")
		slots.Add(60)
	EndIf
	If MCM.GetModSettingBool("Cloudfits", "bSkip61:Slots")
		slots.Add(61)
	EndIf
	SkipSlots = slots
EndFunction

; Read the names from MCM and relabel the picker buttons of every slot whose name changed, or of
; every named slot with abAll. A slot that holds an outfit cannot lose its name: MCM gets the old
; one back.
Function RefreshNames(bool abAll)
	int i = 0
	While i < SlotList.GetSize()
		string settingKey = NameKey(i)
		string name = MCM.GetModSettingString("Cloudfits", settingKey)
		If name == "" && SlotNames[i] != "" && Occupied[i]
			MCM.SetModSettingString("Cloudfits", settingKey, SlotNames[i])
			Debug.Notification("Cloudfits: empty " + SlotNames[i] + " before clearing its name.")
			name = SlotNames[i]
		EndIf
		If name != SlotNames[i] || (abAll && name != "")
			SlotNames[i] = name
			; an unnamed slot's buttons are hidden, so only named ones need a label
			If name != ""
				Cloudfits:Plugin.SetButtonText(StorePicker, i + 1, name)
				Cloudfits:Plugin.SetButtonText(WearPicker, i + 1, name)
			EndIf
			Log("name: slot=" + i + " '" + name + "'")
		EndIf
		i += 1
	EndWhile
EndFunction

string Function NameKey(int aiSlot)
	string settingKey = "sName"
	If aiSlot < 9
		settingKey += "0"
	EndIf
	return settingKey + ((aiSlot + 1) as string) + ":Names"
EndFunction

;/ --------------------------------------------------------------- entry points /;

; bound through MCM's keybind manager
Function StoreOutfit()
	If Utility.IsInMenuMode() || !Ready() || !Claim()
		Return
	EndIf
	StoreFlow()
	Busy = false
EndFunction

Function WearOutfit()
	If Utility.IsInMenuMode() || !Ready() || !Claim()
		Return
	EndIf
	WearFlow()
	Busy = false
EndFunction

bool Function Claim()
	If Busy && (Utility.GetCurrentRealTime() - BusySince) < 30.0
		Return false
	EndIf
	Busy = true
	BusySince = Utility.GetCurrentRealTime()
	return true
EndFunction

bool Function Ready()
	If PluginReady
		return true
	EndIf
	PluginReady = Cloudfits:Plugin.Version() > 0
	If PluginReady
		RefreshNames(true)
	Else
		Debug.Notification("Cloudfits needs Cloudfits.dll and the Runtime Database in F4SE/Plugins.")
	EndIf
	return PluginReady
EndFunction

; MCM: makes sure everything this mod needs is in place. Doing it twice changes nothing.
Function Install()
	RefreshSettings()
	int fixedUp = 0
	If !IsRunning()
		Start()
		fixedUp += 1
	EndIf
	Bind()
	If !PluginReady
		Return
	EndIf
	If fixedUp > 0
		Debug.Notification("Cloudfits: started and ready.")
	Else
		Debug.Notification("Cloudfits: already set up, nothing to do.")
	EndIf
EndFunction

; MCM: hand everything back and stand down, so the mod can be removed without losing items
Function Uninstall()
	Actor player = Game.GetPlayer()
	int emptied = 0
	int i = 0
	While i < SlotList.GetSize()
		ObjectReference slotRef = SlotRef(i)
		If slotRef && slotRef.GetItemCount(None) > 0
			slotRef.RemoveAllItems(player, false)
			emptied += 1
		EndIf
		MarkSlot(i)
		i += 1
	EndWhile
	ResetTracking()
	ReleaseSlot()
	UnregisterForAllEvents()
	Stop()
	Log("uninstall: emptied=" + emptied)
	Debug.Notification("Cloudfits: emptied " + emptied + " slot(s) into your inventory. Safe to remove.")
EndFunction

; MCM, one button per slot
Function EmptySlot(int aiSlot)
	If aiSlot < 0 || aiSlot >= SlotList.GetSize()
		Return
	EndIf
	Actor player = Game.GetPlayer()
	ObjectReference slotRef = SlotRef(aiSlot)
	If !slotRef || !player
		Log("empty: slot=" + aiSlot + " has no reference, refusing")
		Return
	EndIf
	int held = slotRef.GetItemCount(None)
	; vanilla, so it answers for an unloaded reference and other mods see the items move.
	; Never without a destination: RemoveAllItems(None) destroys the contents.
	slotRef.RemoveAllItems(player, false)
	MarkSlot(aiSlot)
	Log("empty: slot=" + aiSlot + " held=" + held + " left=" + slotRef.GetItemCount(None))
	If aiSlot == CheckedOutSlot
		ResetTracking()
	EndIf
	If held > 0
		Debug.Notification("Cloudfits: emptied " + SlotName(aiSlot) + " into your inventory.")
	Else
		Debug.Notification("Cloudfits: " + SlotName(aiSlot) + " is already empty.")
	EndIf
EndFunction

; console: cqf CloudfitsQuest LogOn
Function LogOn()
	Logging = true
	bool opened = Debug.OpenUserLog(LogName)
	Log("logon: userlog=" + opened)
EndFunction

Function LogOff()
	Logging = false
EndFunction

; console: cqf CloudfitsQuest Diag
Function Diag()
	RefreshSettings()
	Log("--- diag --- plugin=" + Cloudfits:Plugin.Version())
	int i = 0
	While i < SlotList.GetSize()
		Log("slot " + i + " count=" + SlotRef(i).GetItemCount(None) + " cached=" + Occupied[i] \
			+ " name='" + SlotNames[i] + "'")
		i += 1
	EndWhile
	Log("checkedOutSlot=" + CheckedOutSlot + " tracked=" + CheckedOutIDs.Length)
	LogWorn(Game.GetPlayer(), "diag")
EndFunction

;/ ------------------------------------------------------------------- storing /;

Function StoreFlow()
	Actor player = Game.GetPlayer()
	If player.IsInPowerArmor()
		Debug.Notification("Cloudfits: not while you are in power armor.")
		Return
	EndIf
	If CountSlots(false) == 0
		Debug.Notification("Cloudfits: no free named slot. Name one in MCM.")
		Return
	EndIf
	int slot = PickSlot(StorePicker)
	If slot < 0
		Return
	EndIf
	If SlotHolds(slot)
		Debug.Notification("Cloudfits: " + SlotName(slot) + " already holds an outfit.")
		Return
	EndIf
	int mode = StoreModePrompt.Show()
	Log("store: slot=" + slot + " mode=" + mode)
	If mode == 1
		StoreWorn(player, slot)
	ElseIf mode == 2
		OpenSlot(player, slot)
	EndIf
EndFunction

Function StoreWorn(Actor akPlayer, int aiSlot)
	LogWorn(akPlayer, "store.before")
	Form[] items = Cloudfits:Plugin.StorableWorn(akPlayer, SkipSlots)
	If items.Length == 0
		Say("Cloudfits: nothing you are wearing can be stored.")
		Return
	EndIf
	int stored = MoveAway(akPlayer, SlotRef(aiSlot), items)
	If stored == 0
		Debug.Notification("Cloudfits: nothing to store.")
	Else
		Debug.Notification("Cloudfits: stored " + stored + " in " + SlotName(aiSlot) + ".")
	EndIf
	int left = Cloudfits:Plugin.ProtectedWornCount(akPlayer)
	If left > 0
		Debug.Notification("Cloudfits: left " + left + " protected item(s) on.")
	EndIf
	If CheckedOutSlot >= 0 && !AnyCheckedOutWorn(akPlayer)
		ResetTracking()
	EndIf
EndFunction

; Take the pieces off with the game's own unequip, so whichever mod owns an item sees the event it
; listens for, then give those handlers a moment and move only what stayed off. A piece that was
; put back on is one its owner wants kept, so we never take it and nothing has to reclaim it.
; Give the owning mods time to object. Some decide immediately, but others enforce in the item's
; own OnUnequipped, start timers, and can put a message box in front of the player as part of
; deciding, so a fixed short wait races it. Wait out any prompt, then settle again.
Function Settle()
	Utility.WaitMenuMode(SettleWait)
	int guard = 0
	While UI.IsMenuOpen("MessageBoxMenu") && guard < 60
		Utility.WaitMenuMode(0.25)
		guard += 1
	EndWhile
	If guard > 0
		Log("settle: waited out a prompt from another mod")
		Utility.WaitMenuMode(SettleWait)
	EndIf
EndFunction

; akItems must come straight from StorableWorn, which remembers the exact copy of each piece
int Function MoveAway(Actor akPlayer, ObjectReference akTarget, Form[] akItems)
	If !akTarget || !akPlayer
		Log("move: no destination, refusing to touch anything")
		return 0
	EndIf
	int i = 0
	While i < akItems.Length
		akPlayer.UnequipItem(akItems[i], false, true)
		i += 1
	EndWhile
	Settle()
	int moved = Cloudfits:Plugin.MoveUnequipped(akPlayer, akItems, akTarget)
	int kept = 0
	i = 0
	While i < akItems.Length
		If akPlayer.IsEquipped(akItems[i])
			kept += 1
			Log("store: fid=" + akItems[i].GetFormID() + " put back on by its owner, leaving it")
		EndIf
		i += 1
	EndWhile
	Log("move: items=" + akItems.Length + " moved=" + moved + " kept=" + kept)
	If kept > 0
		Debug.Notification("Cloudfits: left " + kept + " item(s) another mod keeps hold of.")
	EndIf
	MarkSlotByRef(akTarget)
	return moved
EndFunction

Function OpenSlot(Actor akPlayer, int aiSlot)
	; the holding cell is never loaded, so the container has to come to the player to open
	BorrowSlot(aiSlot, akPlayer)
	BorrowedContainer.Activate(akPlayer, false)
EndFunction

Event OnMenuOpenCloseEvent(string asMenuName, bool abOpening)
	If abOpening
		Return
	EndIf
	If asMenuName == "ExamineMenu"
		; a workbench may have left a piece off after modifying it, so settle the slot now that
		; the player is back in the world rather than mid-menu
		If CheckedOutSlot >= 0 && !AnyCheckedOutWorn(Game.GetPlayer())
			Log("forget: rule=examine slot=" + CheckedOutSlot)
			ResetTracking()
		EndIf
		Return
	EndIf
	If asMenuName != "ContainerMenu" || !BorrowedContainer
		Return
	EndIf
	; filling the slot you are wearing by hand means you have taken it over: stop tracking, so a
	; later swap cannot post your leftovers in on top of what you just put there
	If BorrowedSlot == CheckedOutSlot || (CheckedOutSlot >= 0 && !AnyCheckedOutWorn(Game.GetPlayer()))
		Log("forget: rule=container borrowed=" + BorrowedSlot + " checkedOut=" + CheckedOutSlot)
		ResetTracking()
	EndIf
	MarkSlot(BorrowedSlot)
	ReleaseSlot()
EndEvent

;/ ------------------------------------------------------------------ retrieving /;

Function WearFlow()
	Actor player = Game.GetPlayer()
	If player.IsInPowerArmor()
		Debug.Notification("Cloudfits: not while you are in power armor.")
		Return
	EndIf
	If CountSlots(true) == 0 && CheckedOutSlot < 0
		Debug.Notification("Cloudfits: no stored outfits.")
		Return
	EndIf
	int slot = PickSlot(WearPicker)
	If slot < 0
		If slot == -2
			; "Return equipped": put the checked-out outfit back and wear nothing new
			ReturnCheckedOut(player, -1)
		EndIf
		Return
	EndIf
	If !SlotHolds(slot)
		Debug.Notification("Cloudfits: " + SlotName(slot) + " is empty.")
		Return
	EndIf
	ReturnCheckedOut(player, slot)
	TakeAndWear(player, slot)
EndFunction

Function ReturnCheckedOut(Actor akPlayer, int aiIncomingSlot)
	If CheckedOutSlot < 0 || CheckedOutSlot == aiIncomingSlot
		Return
	EndIf
	int home = CheckedOutSlot
	Form[] worn = Cloudfits:Plugin.StorableWorn(akPlayer, SkipSlots)
	Form[] candidates = new Form[1]
	candidates.Clear()
	int i = 0
	While i < worn.Length
		If CheckedOutIDs.Find(worn[i].GetFormID()) >= 0
			candidates.Add(worn[i])
		EndIf
		i += 1
	EndWhile
	int returned = 0
	If candidates.Length > 0
		returned = MoveAway(akPlayer, SlotRef(home), candidates)
	EndIf
	Log("return: slot=" + home + " returned=" + returned + " tracked=" + CheckedOutIDs.Length)
	If returned > 0
		Debug.Notification("Cloudfits: put " + SlotName(home) + " back.")
	EndIf
	ResetTracking()
EndFunction

Function TakeAndWear(Actor akPlayer, int aiSlot)
	ObjectReference slotRef = SlotRef(aiSlot)
	If !slotRef || !akPlayer
		Debug.Notification("Cloudfits: that slot has no container, nothing taken.")
		Log("take: slot=" + aiSlot + " has no reference, refusing")
		Return
	EndIf
	; the native side reads the container's inventory, which an unloaded reference may not have
	BorrowSlot(aiSlot, akPlayer)
	int[] taken = Cloudfits:Plugin.TakeAndEquip(slotRef, akPlayer)
	ReleaseSlot()
	If slotRef.GetItemCount(None) > 0
		; vanilla answers for any reference, so nothing is ever left behind
		Log("take: slot=" + aiSlot + " still held " + slotRef.GetItemCount(None) + ", handing over unworn")
		slotRef.RemoveAllItems(akPlayer, false)
	EndIf
	MarkSlot(aiSlot)
	If taken.Length == 0
		Debug.Notification("Cloudfits: nothing wearable in " + SlotName(aiSlot) + ".")
		Return
	EndIf
	CheckedOutSlot = aiSlot
	CheckedOutIDs = taken
	If CheckedOutFlag
		CheckedOutFlag.SetValueInt(1)
	EndIf
	Log("wearing: slot=" + aiSlot + " pieces=" + taken.Length)
	Debug.Notification("Cloudfits: wearing " + SlotName(aiSlot) + ".")
EndFunction

;/ --------------------------------------------------------------- bookkeeping /;

Event Actor.OnItemUnequipped(Actor akSender, Form akBaseObject, ObjectReference akReference)
	; a bench or trade window taking a piece off is not the player undressing: menus settle on close
	If Utility.IsInMenuMode()
		Return
	EndIf
	If CheckedOutSlot >= 0 && akBaseObject && CheckedOutIDs.Find(akBaseObject.GetFormID()) >= 0 && !AnyCheckedOutWorn(akSender)
		Log("forget: rule=unequip slot=" + CheckedOutSlot)
		Debug.Notification("Cloudfits: " + SlotName(CheckedOutSlot) + " is free again.")
		ResetTracking()
	EndIf
EndEvent

bool Function AnyCheckedOutWorn(Actor akPlayer)
	int i = 0
	While i < CheckedOutIDs.Length
		Form item = Game.GetForm(CheckedOutIDs[i])
		If item && akPlayer.IsEquipped(item)
			return true
		EndIf
		i += 1
	EndWhile
	return false
EndFunction

Function ResetTracking()
	CheckedOutSlot = -1
	If CheckedOutFlag
		CheckedOutFlag.SetValueInt(0)
	EndIf
	CheckedOutIDs = new int[1]
	CheckedOutIDs.Clear()
EndFunction

;/ ---------------------------------------------------------------- containers /;

Function BorrowSlot(int aiSlot, Actor akPlayer)
	BorrowedContainer = SlotRef(aiSlot)
	BorrowedSlot = aiSlot
	BorrowedContainer.MoveTo(akPlayer)
EndFunction

Function ReleaseSlot()
	If BorrowedContainer
		BorrowedContainer.MoveTo(HomeMarker)
		BorrowedContainer = None
	EndIf
	BorrowedSlot = -1
EndFunction

;/ ------------------------------------------------------------------- helpers /;

; -1 cancelled, -2 the "Return equipped" button, otherwise a slot index.
; Show() counts hidden buttons and returns garbage for any index past 127.
int Function PickSlot(Message akPicker)
	RefreshStates()
	int button = akPicker.Show()
	int slot = -2
	If button <= 0
		slot = -1
	ElseIf button <= SlotList.GetSize()
		slot = button - 1
	EndIf
	Log("picker: button=" + button + " -> slot=" + slot)
	return slot
EndFunction

; Slot globals: 0 unnamed, 1 named and empty, 2 named and filled. The pickers condition their
; buttons on these, so only the right entries appear.
Function RefreshStates()
	int i = 0
	While i < SlotList.GetSize()
		int wanted = 0
		If SlotNames[i] != ""
			wanted = 1 + (Occupied[i] as int)
		EndIf
		If LastSlotState[i] != wanted
			SetGlobal(StateList, i, wanted)
			LastSlotState[i] = wanted
		EndIf
		i += 1
	EndWhile
EndFunction

; named slots that are filled (abFilled) or empty
int Function CountSlots(bool abFilled)
	int n = 0
	int i = 0
	While i < SlotList.GetSize()
		If SlotNames[i] != "" && Occupied[i] == abFilled
			n += 1
		EndIf
		i += 1
	EndWhile
	return n
EndFunction

Function SetGlobal(FormList akList, int aiIndex, int aiValue)
	GlobalVariable gv = akList.GetAt(aiIndex) as GlobalVariable
	If gv
		gv.SetValueInt(aiValue)
	EndIf
EndFunction

ObjectReference Function SlotRef(int aiSlot)
	return SlotList.GetAt(aiSlot) as ObjectReference
EndFunction

; vanilla, because it answers for an unloaded reference
bool Function SlotHolds(int aiSlot)
	return Occupied[aiSlot]
EndFunction

string Function SlotName(int aiSlot)
	If SlotNames[aiSlot] != ""
		return SlotNames[aiSlot]
	EndIf
	return "Slot " + ((aiSlot + 1) as string)
EndFunction

; notifications are easy to miss, and some HUD setups hide them, so with diagnostics on this also
; puts the text in a message box
Function Say(string asText)
	Debug.Notification(asText)
	If Logging
		Debug.MessageBox(asText)
	EndIf
EndFunction

Function Log(string asText)
	If Logging
		; the main log flushes live; the user log appears to buffer until the game exits
		Debug.Trace("Cloudfits: " + asText)
		Debug.TraceUser(LogName, asText)
	EndIf
EndFunction

; one line per worn piece and why it is or is not storable
Function LogWorn(Actor akPlayer, string asWhen)
	If !Logging
		Return
	EndIf
	string[] lines = Cloudfits:Plugin.DescribeWorn(akPlayer, SkipSlots)
	Log(asWhen + ": worn=" + lines.Length)
	int i = 0
	While i < lines.Length
		Log("  " + lines[i])
		i += 1
	EndWhile
EndFunction
