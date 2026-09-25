#!/usr/bin/env python3
"""Save a portable snapshot from SayAll's visible Export Configuration action."""
import argparse
import json
from pathlib import Path


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
    if config.get("customApplicationProfiles") or config.get("buttonApplicationProfileIDs"):
        parser.error("Custom application profiles need path/privacy review before public storage.")
    config["selectedAudioDeviceUID"] = ""
    output = Path(__file__).with_name("settings.json")
    output.write_text(json.dumps(config, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                      encoding="utf-8")
    print(f"Saved {output}; review git diff before committing and pushing.")


if __name__ == "__main__":
    main()
