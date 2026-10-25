Scriptname Cloudfits:Manager extends Quest
{Named outfit slots in four categories, driven by two hotkeys.}

FormList Property SlotList Auto Const Mandatory
FormList Property StateList Auto Const Mandatory
FormList Property CategoryCounts Auto Const Mandatory
ObjectReference Property HomeMarker Auto Const Mandatory
GlobalVariable Property CheckedOutFlag Auto Const Mandatory
Message Property StorePicker Auto Const Mandatory
Message Property WearPicker Auto Const Mandatory
; one slot menu per category, in Cloudfits:Names order
FormList Property StoreMenus Auto Const Mandatory
FormList Property WearMenus Auto Const Mandatory
Message Property StoreModePrompt Auto Const Mandatory

; formIDs taken out of CheckedOutSlot; empty whenever CheckedOutSlot is -1
int[] CheckedOutIDs
int CheckedOutSlot = -1
bool[] Occupied
int[] LastSlotState
int[] LastCountState
; container pulled out of the holding cell, for the trade window or for item work
ObjectReference BorrowedContainer
int BorrowedSlot = -1
bool Busy = false
float BusySince = 0.0
bool Logging = false
bool GoeReady = false
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
		LastSlotState = new int[1]
		LastSlotState.Clear()
		While Occupied.Length < slotCount
			Occupied.Add(false)
			LastSlotState.Add(0)
		EndWhile
	EndIf
	If LastCountState == None
		LastCountState = new int[4]
	EndIf
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
	GoeReady = GardenOfEden.GetVersionRelease() > 0
	RefreshSettings()
	If !GoeReady
		Debug.Notification("Cloudfits needs Garden of Eden Papyrus Script Extender.")
	EndIf
	Log("bind: goe=" + GoeReady + " logging=" + Logging + " slots=" + SlotList.GetSize())
EndFunction

Function OnMCMSettingChange(string asModName, string asId)
	If asModName == "Cloudfits"
		RefreshSettings()
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
	If GoeReady
		return true
	EndIf
	GoeReady = GardenOfEden.GetVersionRelease() > 0
	If !GoeReady
		Debug.Notification("Cloudfits needs Garden of Eden Papyrus Script Extender.")
	EndIf
	return GoeReady
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
	If !GoeReady
		Debug.Notification("Cloudfits: Garden of Eden Papyrus Script Extender is missing.")
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
	If aiSlot < 0 || aiSlot >= SlotList.GetSize() || !Ready()
		Return
	EndIf
	RefreshSettings()
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
	Actor player = Game.GetPlayer()
	Log("--- diag ---")
	int i = 0
	While i < SlotList.GetSize()
		ObjectReference slotRef = SlotRef(i)
		Log("slot " + i + " vanillaCount=" + slotRef.GetItemCount(None) + " cached=" + Occupied[i] \
			+ " goeCount=" + GardenOfEden.GetInventoryItemCount(slotRef) \
			+ " label='" + SlotName(i) + "'")
		i += 1
	EndWhile
	Log("checkedOutSlot=" + CheckedOutSlot + " tracked=" + CheckedOutIDs.Length)
	LogWornVerdicts(player, 0, "diag")
EndFunction

;/ ------------------------------------------------------------------- storing /;

Function StoreFlow()
	Actor player = Game.GetPlayer()
	If player.IsInPowerArmor()
		Debug.Notification("Cloudfits: not while you are in power armor.")
		Return
	EndIf
	int slot = PickSlot(StorePicker, StoreMenus)
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
	ObjectReference slotRef = SlotRef(aiSlot)
	int pipBoyID = 0
	LogWornVerdicts(akPlayer, pipBoyID, "store.before")
	int[] candidates = new int[1]
	candidates.Clear()
	int[] worn = GardenOfEden.GetEquippedItemIndexes(akPlayer)
	int[] apparel = GardenOfEden3.GetItemIndexesByFormType(akPlayer, "ARMO")
	int[] tally = new int[9]
	int i = 0
	While i < worn.Length
		int reason = SkipReason(akPlayer, worn[i], apparel, pipBoyID)
		tally[reason] = tally[reason] + 1
		If reason == 0
			candidates.Add(worn[i])
		EndIf
		i += 1
	EndWhile
	Log("store: worn=" + worn.Length + " armo=" + apparel.Length + " ok=" + tally[0] \
		+ " locked=" + tally[1] + " quest=" + tally[2] + " notarmo=" + tally[3] \
		+ " protslot=" + tally[4] + " noslots=" + tally[5] + " noname=" + tally[6] \
		+ " refid=" + tally[7] + " pipboy=" + tally[8])
	If candidates.Length == 0
		Say("Cloudfits: " + worn.Length + " worn, none storable (locked " + tally[1] \
			+ ", quest " + tally[2] + ", not apparel " + tally[3] + ", slot " + tally[4] \
			+ ", slotless " + tally[5] + ", unnamed " + tally[6] + ", in use " + tally[7] + ")")
	EndIf
	int stored = MoveAway(akPlayer, slotRef, candidates)
	If stored == 0
		Debug.Notification("Cloudfits: nothing to store.")
	Else
		Debug.Notification("Cloudfits: stored " + stored + " in " + SlotName(aiSlot) + ".")
	EndIf
	int left = ProtectedWornCount(akPlayer)
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
; Moving an unequipped stack is also the tame operation: pulling an equipped one out through
; GOEPSE is what crashed the engine.
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

int Function MoveAway(Actor akPlayer, ObjectReference akTarget, int[] aiIndexes)
	If !akTarget || !akPlayer
		Log("move: no destination, refusing to touch anything")
		return 0
	EndIf
	int[] handles = new int[1]
	handles.Clear()
	int[] formIDs = new int[1]
	formIDs.Clear()
	int i = 0
	While i < aiIndexes.Length
		int itemID = GardenOfEden.GetNthItemFormID(akPlayer, aiIndexes[i])
		Form item = Game.GetForm(itemID)
		If item
			handles.Add(GardenOfEden3.GetNthItemHandle(akPlayer, aiIndexes[i]))
			formIDs.Add(itemID)
			akPlayer.UnequipItem(item, false, true)
		Else
			Log("store: fid=" + itemID + " did not resolve to a form")
			Debug.Notification("Cloudfits: could not identify one worn piece.")
		EndIf
		i += 1
	EndWhile
	If handles.Length == 0
		return 0
	EndIf
	Settle()
	int moved = 0
	int kept = 0
	i = 0
	While i < handles.Length
		int index = -1
		GardenOfEden3:InventoryItemHandle found = GardenOfEden3.GetItemByHandle(handles[i])
		If found.owner == akPlayer as ObjectReference && found.itemindex >= 0
			index = found.itemindex
		Else
			; the stack merged into an identical one, so either copy is the same item
			index = UnequippedIndex(akPlayer, formIDs[i])
		EndIf
		If index < 0
			Log("store: fid=" + formIDs[i] + " gone after unequip")
		ElseIf GardenOfEden.GetNthItemIsEquipped(akPlayer, index) > 0
			kept += 1
			Log("store: fid=" + formIDs[i] + " put back on by its owner, leaving it")
		ElseIf GardenOfEden.TransferNthItem(akPlayer, index, akTarget, 1)
			moved += 1
			Log("store: fid=" + formIDs[i] + " moved from idx=" + index)
		Else
			Log("store: fid=" + formIDs[i] + " transfer refused at idx=" + index)
			Debug.Notification("Cloudfits: the game refused to move one piece.")
		EndIf
		i += 1
	EndWhile
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
	int slot = PickSlot(WearPicker, WearMenus)
	If slot < 0
		Return
	EndIf
	If slot == -2
		; "Return equipped": put the checked-out outfit back and wear nothing new
		ReturnCheckedOut(player, -1)
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
	int[] candidates = new int[1]
	candidates.Clear()
	int[] worn = GardenOfEden.GetEquippedItemIndexes(akPlayer)
	int i = 0
	While i < worn.Length
		int itemID = GardenOfEden.GetNthItemFormID(akPlayer, worn[i])
		If CheckedOutIDs.Find(itemID) >= 0 && Releasable(akPlayer, worn[i])
			candidates.Add(worn[i])
		EndIf
		i += 1
	EndWhile
	int returned = MoveAway(akPlayer, SlotRef(home), candidates)
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
	int[] before = ApparelHandles(akPlayer)
	int[] beforeCounts = ApparelCounts(akPlayer)
	; vanilla: answers for an unloaded reference and lets other mods see the items arrive
	slotRef.RemoveAllItems(akPlayer, false)
	MarkSlot(aiSlot)
	int[] arrived = NewApparelHandles(akPlayer, before, beforeCounts)
	int[] taken = new int[1]
	taken.Clear()
	int i = 0
	While i < arrived.Length
		; resolve each stack by handle, because equipping shifts the indexes around it
		GardenOfEden3:InventoryItemHandle found = GardenOfEden3.GetItemByHandle(arrived[i])
		If found.owner == akPlayer as ObjectReference && found.itemindex >= 0
			int itemID = GardenOfEden.GetNthItemFormID(akPlayer, found.itemindex)
			bool equipped = GardenOfEden.EquipNthItem(akPlayer, found.itemindex, false, false)
			Log("take: fid=" + itemID + " idx=" + found.itemindex + " equip=" + equipped)
			If taken.Find(itemID) < 0
				taken.Add(itemID)
			EndIf
		EndIf
		i += 1
	EndWhile
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

int[] Function ApparelHandles(ObjectReference akRef)
	int[] handles = new int[1]
	handles.Clear()
	int[] apparel = GardenOfEden3.GetItemIndexesByFormType(akRef, "ARMO")
	int i = 0
	While i < apparel.Length
		handles.Add(GardenOfEden3.GetNthItemHandle(akRef, apparel[i]))
		i += 1
	EndWhile
	return handles
EndFunction

int[] Function ApparelCounts(ObjectReference akRef)
	int[] counts = new int[1]
	counts.Clear()
	int[] apparel = GardenOfEden3.GetItemIndexesByFormType(akRef, "ARMO")
	int i = 0
	While i < apparel.Length
		counts.Add(GardenOfEden.GetNthItemCount(akRef, apparel[i]))
		i += 1
	EndWhile
	return counts
EndFunction

; A piece that arrived is either a stack we have not seen before, or an existing stack that grew
; because the arrival was indistinguishable from something already carried. Either way that stack
; is the one to wear.
int[] Function NewApparelHandles(ObjectReference akRef, int[] aiKnown, int[] aiCounts)
	int[] fresh = new int[1]
	fresh.Clear()
	int[] apparel = GardenOfEden3.GetItemIndexesByFormType(akRef, "ARMO")
	int i = 0
	While i < apparel.Length
		int handle = GardenOfEden3.GetNthItemHandle(akRef, apparel[i])
		int was = aiKnown.Find(handle)
		bool arrived = was < 0
		If !arrived && was < aiCounts.Length
			arrived = GardenOfEden.GetNthItemCount(akRef, apparel[i]) > aiCounts[was]
		EndIf
		If arrived && GardenOfEden.GetNthItemIsEquipped(akRef, apparel[i]) <= 0
			fresh.Add(handle)
		EndIf
		i += 1
	EndWhile
	Log("arrived: apparel=" + apparel.Length + " known=" + aiKnown.Length + " new=" + fresh.Length)
	return fresh
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
	int[] worn = GardenOfEden.GetEquippedItemIndexes(akPlayer)
	int i = 0
	While i < worn.Length
		If CheckedOutIDs.Find(GardenOfEden.GetNthItemFormID(akPlayer, worn[i])) >= 0
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

; GOEPSE's per-index calls came back empty for a reference sitting in the unloaded holding cell,
; so bring the container to the player for item work and send it home afterwards
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
; Show() counts hidden buttons and returns garbage for any index past 127, so no menu may grow beyond that.
int Function PickSlot(Message akCategories, FormList akMenus)
	RefreshStates()
	int[] starts = Cloudfits:Names.CategoryStart()
	While true
		int category = akCategories.Show()
		If category <= 0
			Log("picker: cancelled")
			return -1
		ElseIf category > starts.Length
			Log("picker: return equipped")
			return -2
		EndIf
		int button = (akMenus.GetAt(category - 1) as Message).Show()
		If button > 0
			int slot = starts[category - 1] + button - 1
			Log("picker: category=" + category + " button=" + button + " -> slot=" + slot)
			return slot
		EndIf
	EndWhile
	return -1
EndFunction

; Slot globals: 0 empty, 1 filled. Count globals: filled slots in that category. The menus
; condition their buttons on these, so only the right entries appear.
Function RefreshStates()
	int[] starts = Cloudfits:Names.CategoryStart()
	int[] sizes = Cloudfits:Names.CategorySize()
	int c = 0
	While c < starts.Length
		int filled = 0
		int i = starts[c]
		While i < starts[c] + sizes[c]
			int wanted = Occupied[i] as int
			filled += wanted
			If LastSlotState[i] != wanted
				SetGlobal(StateList, i, wanted)
				LastSlotState[i] = wanted
			EndIf
			i += 1
		EndWhile
		If LastCountState[c] != filled
			SetGlobal(CategoryCounts, c, filled)
			LastCountState[c] = filled
		EndIf
		c += 1
	EndWhile
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
	return Cloudfits:Names.Slots()[aiSlot]
EndFunction

bool Function Storable(Actor akPlayer, int aiIndex, int[] aiApparel, int aiPipBoyID)
	return SkipReason(akPlayer, aiIndex, aiApparel, aiPipBoyID) == 0
EndFunction

; 0 storable, otherwise why not. Reported in a notification, because the only diagnostics that
; survive here are the ones that do not depend on Papyrus logging being switched on.
int Function SkipReason(Actor akPlayer, int aiIndex, int[] aiApparel, int aiPipBoyID)
	; first, as the only check that costs no native call
	If aiApparel.Find(aiIndex) < 0
		return 3
	EndIf
	If GardenOfEden.GetNthItemIsEquipStateLocked(akPlayer, aiIndex) != 0
		return 1
	EndIf
	If GardenOfEden2.GetNthItemIsQuestItem(akPlayer, aiIndex) != 0
		return 2
	EndIf
	If SkipSlots != None
		int s = 0
		While s < SkipSlots.Length
			If GardenOfEden3.GetNthItemHasBipedSlot(akPlayer, aiIndex, SkipSlots[s]) == 1
				return 4
			EndIf
			s += 1
		EndWhile
	EndIf
	; apparel that covers no body slot is not clothing: it is a mod's bookkeeping item
	If GardenOfEden3.GetNthItemBipedSlotsValue(akPlayer, aiIndex) == 0
		return 5
	EndIf
	; a worn item with no name is a hidden rendering item
	If GardenOfEden.GetNthItemName(akPlayer, aiIndex) == ""
		return 6
	EndIf
	; An item still carrying a RefID is a persistent reference a script put there and keeps hold of
	If HasRefID(akPlayer, aiIndex)
		return 7
	EndIf
	int itemID = GardenOfEden.GetNthItemFormID(akPlayer, aiIndex)
	If itemID == 0 || itemID == aiPipBoyID
		return 8
	EndIf
	return 0
EndFunction

; anything the game or another mod has a claim on. A non-zero answer includes GOEPSE's -1 error
; value, which is the safe way round to read it.
bool Function HasRefID(ObjectReference akRef, int aiIndex)
	string refID = GardenOfEden2.GetNthItemRefID(akRef, aiIndex, false)
	return refID != "" && refID != "00000000" && refID != "0"
EndFunction

bool Function Releasable(Actor akPlayer, int aiIndex)
	If GardenOfEden.GetNthItemIsEquipStateLocked(akPlayer, aiIndex) != 0
		return false
	EndIf
	If GardenOfEden2.GetNthItemIsQuestItem(akPlayer, aiIndex) != 0
		return false
	EndIf
	return true
EndFunction

int Function ProtectedWornCount(Actor akPlayer)
	int n = 0
	int[] worn = GardenOfEden.GetEquippedItemIndexes(akPlayer)
	int[] apparel = GardenOfEden3.GetItemIndexesByFormType(akPlayer, "ARMO")
	int i = 0
	While i < worn.Length
		int itemID = GardenOfEden.GetNthItemFormID(akPlayer, worn[i])
		If apparel.Find(worn[i]) >= 0 && !Releasable(akPlayer, worn[i])
			n += 1
		EndIf
		i += 1
	EndWhile
	return n
EndFunction

int[] Function AllFormIDs(ObjectReference akRef)
	int[] ids = new int[1]
	ids.Clear()
	int count = GardenOfEden.GetInventoryItemCount(akRef)
	int i = 0
	While i < count
		ids.Add(GardenOfEden.GetNthItemFormID(akRef, i))
		i += 1
	EndWhile
	return ids
EndFunction

int Function IndexOfForm(ObjectReference akRef, int aiFormID)
	int count = GardenOfEden.GetInventoryItemCount(akRef)
	int i = 0
	While i < count
		If GardenOfEden.GetNthItemFormID(akRef, i) == aiFormID
			return i
		EndIf
		i += 1
	EndWhile
	return -1
EndFunction

int[] Function HandlesWithForm(ObjectReference akRef, int aiFormID)
	int[] handles = new int[1]
	handles.Clear()
	int count = GardenOfEden.GetInventoryItemCount(akRef)
	int i = 0
	While i < count
		If GardenOfEden.GetNthItemFormID(akRef, i) == aiFormID
			handles.Add(GardenOfEden3.GetNthItemHandle(akRef, i))
		EndIf
		i += 1
	EndWhile
	return handles
EndFunction

; a transfer can insert a stack anywhere, so match on handles rather than index numbers
int Function ArrivedIndex(ObjectReference akRef, int aiFormID, int[] aiKnownHandles)
	int count = GardenOfEden.GetInventoryItemCount(akRef)
	int i = 0
	While i < count
		If GardenOfEden.GetNthItemFormID(akRef, i) == aiFormID
			If aiKnownHandles.Find(GardenOfEden3.GetNthItemHandle(akRef, i)) < 0
				return i
			EndIf
		EndIf
		i += 1
	EndWhile
	return -1
EndFunction

int Function UnequippedIndex(ObjectReference akRef, int aiFormID)
	int count = GardenOfEden.GetInventoryItemCount(akRef)
	int i = 0
	While i < count
		If GardenOfEden.GetNthItemFormID(akRef, i) == aiFormID && GardenOfEden.GetNthItemIsEquipped(akRef, i) <= 0
			return i
		EndIf
		i += 1
	EndWhile
	return -1
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
Function LogWornVerdicts(Actor akPlayer, int aiPipBoyID, string asWhen)
	If !Logging
		Return
	EndIf
	int[] worn = GardenOfEden.GetEquippedItemIndexes(akPlayer)
	int[] apparel = GardenOfEden3.GetItemIndexesByFormType(akPlayer, "ARMO")
	Log(asWhen + ": worn=" + worn.Length + " apparel=" + apparel.Length + " pipboy=" + aiPipBoyID)
	int i = 0
	While i < worn.Length
		int itemID = GardenOfEden.GetNthItemFormID(akPlayer, worn[i])
		Log("  idx=" + worn[i] + " fid=" + itemID \
			+ " edid=" + GardenOfEden2.GetFormEditorID(Game.GetForm(itemID)) \
			+ " armo=" + (apparel.Find(worn[i]) >= 0) \
			+ " locked=" + GardenOfEden.GetNthItemIsEquipStateLocked(akPlayer, worn[i]) \
			+ " quest=" + GardenOfEden2.GetNthItemIsQuestItem(akPlayer, worn[i]) \
			+ " slots=" + GardenOfEden3.GetNthItemBipedSlotsValue(akPlayer, worn[i]) \
			+ " name='" + GardenOfEden.GetNthItemName(akPlayer, worn[i]) + "'" \
			+ " refid=" + GardenOfEden2.GetNthItemRefID(akPlayer, worn[i], false))
		i += 1
	EndWhile
EndFunction
