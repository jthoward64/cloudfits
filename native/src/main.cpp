// SPDX-FileCopyrightText: 2026 Tag Howard <tag@jthoward.dev>
//
// SPDX-License-Identifier: GPL-3.0-only

#include "Natives.h"

namespace
{
	[[nodiscard]] constexpr std::uint32_t PackVersion(std::uint32_t a_major, std::uint32_t a_minor, std::uint32_t a_build) noexcept
	{
		return ((a_major & 0xFF) << 24) | ((a_minor & 0xFF) << 16) | ((a_build & 0xFFF) << 4);
	}

	[[nodiscard]] constexpr F4SE::PluginVersionData MakePluginVersionData() noexcept
	{
		F4SE::PluginVersionData data{};
		data.pluginVersion = PackVersion(
			static_cast<std::uint32_t>(Version::MAJOR),
			static_cast<std::uint32_t>(Version::MINOR),
			static_cast<std::uint32_t>(Version::PATCH));
		for (std::size_t i = 0; i < Version::PROJECT.size() && i < std::size(data.name) - 1; ++i) {
			data.name[i] = Version::PROJECT[i];
		}
		data.addressIndependence = F4SE::PluginVersionData::kAddressIndependence_Signatures;
		data.structureIndependence =
			F4SE::PluginVersionData::kStructureIndependence_1_10_980Layout |
			F4SE::PluginVersionData::kStructureIndependence_1_11_137Layout;
		return data;
	}

	[[nodiscard]] bool InitializeLogger()
	{
		auto path = logger::log_directory();
		if (!path) {
			return false;
		}
		*path /= fmt::format(FMT_STRING("{}.log"), Version::PROJECT);
		auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(path->string(), true);
		auto log = std::make_shared<spdlog::logger>("global log"s, std::move(sink));
		log->set_level(spdlog::level::info);
		log->flush_on(spdlog::level::info);
		spdlog::set_default_logger(std::move(log));
		spdlog::set_pattern("[%H:%M:%S.%e] [%l] %v"s);
		return true;
	}
}

extern "C" DLLEXPORT constinit F4SE::PluginVersionData F4SEPlugin_Version = MakePluginVersionData();

extern "C" DLLEXPORT bool F4SEAPI F4SEPlugin_Load(const F4SE::LoadInterface* a_f4se)
{
	if (!InitializeLogger()) {
		return false;
	}
	if (a_f4se->IsEditor()) {
		return false;
	}

	F4SE::Init(a_f4se);
	logger::info("{} v{} on runtime {}", Version::PROJECT, Version::NAME, a_f4se->RuntimeVersion().string());

	const auto papyrus = F4SE::GetPapyrusInterface();
	if (!papyrus || !papyrus->Register(Natives::Register)) {
		logger::critical("could not register Papyrus functions");
		return false;
	}
	return true;
}
