// SPDX-FileCopyrightText: 2026 Tag Howard <tag@jthoward.dev>
//
// SPDX-License-Identifier: GPL-3.0-only

#include "Natives.h"

namespace Natives
{
	namespace
	{
		constexpr auto SCRIPT = "Cloudfits:Plugin";
		constexpr std::int32_t API_VERSION = 1;

		enum class Verdict : std::uint32_t
		{
			kStorable,
			kLocked,
			kQuest,
			kNotApparel,
			kProtectedSlot,
			kNoSlots,
			kNoName,
			kPersistentRef
		};

		constexpr std::array VERDICT_NAMES{
			"storable"sv,
			"locked"sv,
			"quest"sv,
			"not apparel"sv,
			"protected slot"sv,
			"no slots"sv,
			"no name"sv,
			"persistent ref"sv
		};

		using Stack = RE::BGSInventoryItem::Stack;

		// extra list of each piece StorableWorn picked, used only as an identity to compare against
		std::unordered_map<const RE::TESBoundObject*, const RE::ExtraDataList*> g_picked;

		[[nodiscard]] std::uint32_t SlotMask(const std::vector<std::int32_t>& a_slots) noexcept
		{
			std::uint32_t mask = 0;
			for (const auto slot : a_slots) {
				if (slot >= 30 && slot < 62) {
					mask |= 1u << (slot - 30);
				}
			}
			return mask;
		}

		// the engine calls made per stack take this lock themselves, and a read lock nests
		template <class F>
		void ForEachStack(RE::TESObjectREFR* a_ref, F&& a_func)
		{
			const auto list = a_ref ? a_ref->inventoryList : nullptr;
			if (!list) {
				return;
			}
			RE::BSAutoReadLock lock{ list->rwLock };
			for (auto& item : list->data) {
				std::uint32_t index = 0;
				for (auto stack = item.stackData.get(); stack; stack = stack->nextStack.get(), ++index) {
					a_func(item, *stack, index);
				}
			}
		}

		[[nodiscard]] Verdict Judge(RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index, std::uint32_t a_skipMask)
		{
			const auto armor = a_item.object ? a_item.object->As<RE::TESObjectARMO>() : nullptr;
			if (!armor) {
				return Verdict::kNotApparel;
			}
			if (a_stack.flags.all(Stack::Flag::kEquipStateLocked)) {
				return Verdict::kLocked;
			}
			if (a_item.IsQuestObject(static_cast<std::int32_t>(a_index))) {
				return Verdict::kQuest;
			}
			const auto slots = armor->BGSBipedObjectForm::GetFilledSlots().underlying();
			if (slots & a_skipMask) {
				return Verdict::kProtectedSlot;
			}
			// apparel covering no body slot is another mod's bookkeeping item
			if (slots == 0) {
				return Verdict::kNoSlots;
			}
			// a worn item with no name is a hidden rendering item
			const auto name = a_item.GetDisplayFullName(a_index);
			if (!name || !*name) {
				return Verdict::kNoName;
			}
			// a persistent reference a script added and keeps hold of; moving it tears down its state
			if (a_stack.extra && a_stack.extra->GetByType(RE::EXTRA_DATA_TYPE::kReferenceHandle)) {
				return Verdict::kPersistentRef;
			}
			return Verdict::kStorable;
		}

		// The stack to move: the picked one if it is still there and unequipped, none if it is worn
		// again, otherwise (it merged into an identical stack) the only unequipped stack left.
		[[nodiscard]] std::optional<std::uint32_t> UnequippedStack(RE::TESObjectREFR* a_ref, const RE::TESBoundObject* a_object, const RE::ExtraDataList* a_picked)
		{
			std::optional<std::uint32_t> picked;
			std::optional<std::uint32_t> last;
			bool pickedWorn = false;
			std::uint32_t unequipped = 0;
			ForEachStack(a_ref, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index) {
				if (a_item.object != a_object) {
					return;
				}
				const bool isPicked = a_picked && a_stack.extra.get() == a_picked;
				if (a_stack.IsEquipped()) {
					pickedWorn = pickedWorn || isPicked;
					return;
				}
				++unequipped;
				last = a_index;
				if (isPicked) {
					picked = a_index;
				}
			});
			if (picked) {
				return picked;
			}
			if (!pickedWorn && unequipped == 1) {
				return last;
			}
			return std::nullopt;
		}

		void MoveStack(RE::TESObjectREFR* a_from, RE::TESBoundObject* a_object, std::uint32_t a_index, std::int32_t a_count, RE::TESObjectREFR* a_to)
		{
			RE::TESObjectREFR::RemoveItemData data{ a_object, a_count };
			data.stackData.push_back(a_index);
			data.reason = RE::ITEM_REMOVE_REASON::kStoreContainer;
			data.a_otherContainer = a_to;
			a_from->RemoveItem(data);
		}

		std::int32_t Version(std::monostate)
		{
			return API_VERSION;
		}

		std::vector<RE::TESForm*> StorableWorn(std::monostate, RE::Actor* a_actor, std::vector<std::int32_t> a_skipSlots)
		{
			std::vector<RE::TESForm*> result;
			g_picked.clear();
			const auto skipMask = SlotMask(a_skipSlots);
			ForEachStack(a_actor, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index) {
				if (!a_stack.IsEquipped() || Judge(a_item, a_stack, a_index, skipMask) != Verdict::kStorable) {
					return;
				}
				if (g_picked.emplace(a_item.object, a_stack.extra.get()).second) {
					result.push_back(a_item.object);
				}
			});
			return result;
		}

		std::int32_t MoveUnequipped(std::monostate, RE::Actor* a_actor, std::vector<RE::TESForm*> a_items, RE::TESObjectREFR* a_target)
		{
			if (!a_actor || !a_target) {
				return 0;
			}
			std::int32_t moved = 0;
			for (const auto form : a_items) {
				const auto object = form ? form->As<RE::TESBoundObject>() : nullptr;
				if (!object) {
					continue;
				}
				const auto picked = g_picked.find(object);
				const auto index = UnequippedStack(a_actor, object, picked != g_picked.end() ? picked->second : nullptr);
				if (!index) {
					logger::info("move: {:08X} still worn or ambiguous, left", object->GetFormID());
					continue;
				}
				MoveStack(a_actor, object, *index, 1, a_target);
				logger::info("move: {:08X} stack {} stored", object->GetFormID(), *index);
				++moved;
			}
			g_picked.clear();
			return moved;
		}

		std::vector<std::int32_t> TakeAndEquip(std::monostate, RE::TESObjectREFR* a_source, RE::Actor* a_actor)
		{
			struct Entry
			{
				RE::TESBoundObject* object;
				std::uint32_t index;
				std::int32_t count;
			};

			std::vector<std::int32_t> equipped;
			if (!a_source || !a_actor) {
				return equipped;
			}

			std::vector<Entry> entries;
			ForEachStack(a_source, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index) {
				entries.push_back({ a_item.object, a_index, static_cast<std::int32_t>(a_stack.GetCount()) });
			});
			// removing a stack renumbers the later stacks of the same object
			std::ranges::sort(entries, [](const Entry& a_lhs, const Entry& a_rhs) {
				return a_lhs.object != a_rhs.object ? a_lhs.object < a_rhs.object : a_lhs.index > a_rhs.index;
			});

			const auto manager = RE::ActorEquipManager::GetSingleton();
			// the lists the actor holds for this object, read fresh either side of its own move
			std::vector<const RE::ExtraDataList*> held;
			for (const auto& entry : entries) {
				held.clear();
				ForEachStack(a_actor, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t) {
					if (a_item.object == entry.object) {
						held.push_back(a_stack.extra.get());
					}
				});

				MoveStack(a_source, entry.object, entry.index, entry.count, a_actor);

				if (!manager || !entry.object->As<RE::TESObjectARMO>()) {
					continue;
				}
				// the stack the move landed in, or any unworn one once it merged into a held stack
				std::optional<std::uint32_t> arrived;
				std::optional<std::uint32_t> unworn;
				ForEachStack(a_actor, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index) {
					if (a_item.object != entry.object || a_stack.IsEquipped()) {
						return;
					}
					if (!unworn) {
						unworn = a_index;
					}
					if (!arrived && std::ranges::find(held, a_stack.extra.get()) == held.end()) {
						arrived = a_index;
					}
				});
				const auto index = arrived ? arrived : unworn;
				if (!index) {
					logger::info("take: {:08X} not found unequipped after the move", entry.object->GetFormID());
					continue;
				}
				RE::TBO_InstanceData* instance = nullptr;
				ForEachStack(a_actor, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index) {
					if (a_item.object == entry.object && a_index == *index && a_stack.extra) {
						if (const auto extra = a_stack.extra->GetByType<RE::ExtraInstanceData>()) {
							instance = extra->data.get();
						}
					}
				});
				const RE::BGSObjectInstance object{ entry.object, instance };
				const auto ok = manager->EquipObject(a_actor, object, *index, 1, nullptr, true, false, false, false, false);
				logger::info("take: {:08X} stack {} equip={}", entry.object->GetFormID(), *index, ok);
				const auto formID = static_cast<std::int32_t>(entry.object->GetFormID());
				if (ok && std::ranges::find(equipped, formID) == equipped.end()) {
					equipped.push_back(formID);
				}
			}
			return equipped;
		}

		std::vector<std::string> DescribeWorn(std::monostate, RE::Actor* a_actor, std::vector<std::int32_t> a_skipSlots)
		{
			std::vector<std::string> lines;
			const auto skipMask = SlotMask(a_skipSlots);
			ForEachStack(a_actor, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index) {
				if (!a_stack.IsEquipped()) {
					return;
				}
				const auto verdict = Judge(a_item, a_stack, a_index, skipMask);
				const auto armor = a_item.object->As<RE::TESObjectARMO>();
				const auto name = a_item.GetDisplayFullName(a_index);
				lines.push_back(fmt::format(
					FMT_STRING("{:08X} '{}' slots={:08X} {}"),
					a_item.object->GetFormID(),
					name ? name : "",
					armor ? armor->BGSBipedObjectForm::GetFilledSlots().underlying() : 0,
					VERDICT_NAMES[static_cast<std::size_t>(verdict)]));
			});
			return lines;
		}

		std::int32_t ProtectedWornCount(std::monostate, RE::Actor* a_actor)
		{
			std::int32_t count = 0;
			ForEachStack(a_actor, [&](RE::BGSInventoryItem& a_item, const Stack& a_stack, std::uint32_t a_index) {
				if (!a_stack.IsEquipped() || !a_item.object->As<RE::TESObjectARMO>()) {
					return;
				}
				const auto verdict = Judge(a_item, a_stack, a_index, 0);
				if (verdict == Verdict::kLocked || verdict == Verdict::kQuest) {
					++count;
				}
			});
			return count;
		}

		bool SetButtonText(std::monostate, RE::BGSMessage* a_message, std::int32_t a_button, std::string_view a_text)
		{
			if (!a_message || a_button < 0) {
				return false;
			}
			std::int32_t index = 0;
			for (const auto button : a_message->buttonList) {
				if (index++ == a_button) {
					if (!button) {
						return false;
					}
					button->text = a_text;
					return true;
				}
			}
			return false;
		}
	}

	bool F4SEAPI Register(RE::BSScript::IVirtualMachine* a_vm)
	{
		// everything but Version touches inventories or forms, so it runs on the main thread
		a_vm->BindNativeMethod(SCRIPT, "Version", Version, true);
		a_vm->BindNativeMethod(SCRIPT, "StorableWorn", StorableWorn, false);
		a_vm->BindNativeMethod(SCRIPT, "MoveUnequipped", MoveUnequipped, false);
		a_vm->BindNativeMethod(SCRIPT, "TakeAndEquip", TakeAndEquip, false);
		a_vm->BindNativeMethod(SCRIPT, "DescribeWorn", DescribeWorn, false);
		a_vm->BindNativeMethod(SCRIPT, "ProtectedWornCount", ProtectedWornCount, false);
		a_vm->BindNativeMethod(SCRIPT, "SetButtonText", SetButtonText, false);
		logger::info("registered {} functions", SCRIPT);
		return true;
	}
}
