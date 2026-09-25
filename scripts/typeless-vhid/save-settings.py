#!/usr/bin/env python3
"""Save a portable snapshot from SayAll's visible Export Configuration action."""
import argparse
import json
from pathlib import Path
from uuid import UUID


def validate_application_profiles(config):
    """Only persist reviewed launch-only profiles with portable public paths."""
    approved = {
        ("com.apple.exposelauncher", "/System/Applications/Mission Control.app", "调度中心"),
        ("com.openai.codex", "/Applications/ChatGPT.app", "ChatGPT"),
    }
    profile_ids = set()
    for profile in config.get("customApplicationProfiles", []):
        if set(profile) != {"id", "bundleIdentifier", "applicationPath", "displayName", "focusStrategy"}:
            raise ValueError("Application profile fields need privacy review.")
        identity = (profile["bundleIdentifier"], profile["applicationPath"], profile["displayName"])
        if identity not in approved or profile["focusStrategy"] != "none":
            raise ValueError("Application path or focus behavior needs review.")
        UUID(profile["id"])
        profile_ids.add(profile["id"])
    references = set(config.get("buttonApplicationProfileIDs", {}).values())
    for bindings in config.get("secondaryButtonBindings", {}).values():
        references.update(binding["applicationProfileID"] for binding in bindings.values()
                          if "applicationProfileID" in binding)
    if not references <= profile_ids:
        raise ValueError("Application binding references an unknown profile.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("export", type=Path, help="JSON exported by the test App")
    args = parser.parse_args()
    config = json.loads(args.export.read_text(encoding="utf-8"))
    allowed = {
        "formatVersion", "gainDB", "selectedAudioDeviceUID", "customMappingEnabled",
        "buttonBindings", "buttonShortcuts", "buttonApplicationProfileIDs",
        "secondaryButtonBindings", "buttonRapidPressEnabled", "customApplicationProfiles",
        "applicationLanguage", "showDockIcon", "openMainWindowAtLaunch",
        "checksForPreReleaseUpdates", "experimentalContinuousRecordingEnabled",
        "voiceFnTapModeEnabled", "voiceKeyMode", "continuousRecordingPowerBindingBackup",
    }
    if not isinstance(config, dict) or config.get("formatVersion") != 1:
        parser.error("Expected SayAll formatVersion 1 configuration JSON, not a defaults plist.")
    if set(config) - allowed:
        parser.error("New configuration fields need review before saving to the public fork.")
    try:
        validate_application_profiles(config)
    except (KeyError, TypeError, ValueError) as error:
        parser.error(str(error))
    config["selectedAudioDeviceUID"] = ""
    output = Path(__file__).with_name("settings.json")
    output.write_text(json.dumps(config, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                      encoding="utf-8")
    print(f"Saved {output}; review git diff before committing and pushing.")


if __name__ == "__main__":
    main()
