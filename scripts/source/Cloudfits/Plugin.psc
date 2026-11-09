; SPDX-FileCopyrightText: 2026 Tag Howard <tag@jthoward.dev>
;
; SPDX-License-Identifier: GPL-3.0-only

Scriptname Cloudfits:Plugin Native Hidden
{Functions implemented by Cloudfits.dll.}

; 0 when Cloudfits.dll is not loaded
int Function Version() global native

; worn pieces that may be stored, remembering each piece's stack for MoveUnequipped
Form[] Function StorableWorn(Actor akActor, int[] aiSkipSlots) global native

; moves each piece StorableWorn picked that is no longer worn; returns how many moved
int Function MoveUnequipped(Actor akActor, Form[] akItems, ObjectReference akTarget) global native

; moves everything from akSource to akActor and wears the apparel; returns the formIDs worn
int[] Function TakeAndEquip(ObjectReference akSource, Actor akActor) global native

; one line per worn item and why it is or is not storable
string[] Function DescribeWorn(Actor akActor, int[] aiSkipSlots) global native

; worn apparel that is equip-locked or a quest item
int Function ProtectedWornCount(Actor akActor) global native

bool Function SetButtonText(Message akMessage, int aiButton, string asText) global native
