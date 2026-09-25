import AppKit
import Testing
@testable import RemoteMic

@Suite("Global Speed shortcut scope")
struct GlobalSpeedShortcutGuardTests {
    @Test func acceptsChromeContentAndRejectsOtherAppsInputsAndFocusChanges() {
        let configured = ConfiguredButtonAction(action: .customShortcut,
            shortcut: CustomKeyboardShortcut(keyCode: 87, modifierFlags: [], keyLabel: "Numpad5"))
        let chrome = GlobalSpeedShortcutGuard.Application(pid: 42, bundleIdentifier: "com.google.Chrome")
        let other = GlobalSpeedShortcutGuard.Application(pid: 43, bundleIdentifier: "test.other")
        for state in [GlobalSpeedShortcutGuard.Focus.webContent, .editable, .outsideWebContent, .unknown] {
            let result = GlobalSpeedShortcutGuard.skipReason(button: .ok, trigger: .longPress,
                configured: configured, isTestBuild: true, frontmost: { chrome }, focus: { _ in state })
            #expect(result == (state == .webContent ? nil : state.rawValue))
        }
        #expect(GlobalSpeedShortcutGuard.skipReason(button: .ok, trigger: .longPress,
            configured: configured, isTestBuild: true, frontmost: { other },
            focus: { _ in Issue.record("Must not query other apps"); return .webContent }) == "not_chrome")
        var calls = 0
        #expect(GlobalSpeedShortcutGuard.skipReason(button: .ok, trigger: .longPress,
            configured: configured, isTestBuild: true,
            frontmost: { calls += 1; return calls == 1 ? chrome : other },
            focus: { _ in .webContent }) == "focus_changed")
    }

    @Test func protectsExactlyTheFiveVideoHolds() {
        for (button, key) in [(RemoteButton.up, UInt16(91)), (.down, 84), (.left, 86), (.right, 88), (.ok, 87)] {
            let configured = ConfiguredButtonAction(action: .customShortcut,
                shortcut: CustomKeyboardShortcut(keyCode: key, modifierFlags: [], keyLabel: "Numpad"))
            #expect(GlobalSpeedShortcutGuard.applies(button: button, trigger: .longPress, configured: configured))
            for trigger in [ButtonTrigger.singleClick, .doubleClick] {
                #expect(!GlobalSpeedShortcutGuard.applies(button: button, trigger: trigger, configured: configured))
            }
            #expect(!GlobalSpeedShortcutGuard.applies(button: .tv, trigger: .longPress, configured: configured))
            #expect(GlobalSpeedShortcutGuard.skipReason(button: button, trigger: .longPress,
                configured: configured, isTestBuild: true, frontmost: { nil }) == "not_chrome")
            #expect(GlobalSpeedShortcutGuard.skipReason(button: button, trigger: .longPress,
                configured: configured, isTestBuild: false, frontmost: { Issue.record("Must not query focus"); return nil }) == nil)
        }
        let typeless = ConfiguredButtonAction(action: .customShortcut,
            shortcut: CustomKeyboardShortcut(keyCode: 9, modifierFlags: [.control, .option], keyLabel: "V"))
        #expect(!GlobalSpeedShortcutGuard.applies(button: .ok, trigger: .longPress, configured: typeless))
    }

    @Test func rejectsInputsAncestorsBrowserChromeAndUnknownFocus() {
        typealias Node = GlobalSpeedShortcutGuard.Node
        let web = Node(role: "AXWebArea", editable: false)
        #expect(GlobalSpeedShortcutGuard.classify([web]) == .webContent)
        #expect(GlobalSpeedShortcutGuard.classify([Node(role: "AXButton", editable: false), web]) == .webContent)
        for role in ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"] {
            #expect(GlobalSpeedShortcutGuard.classify([Node(role: role, editable: false), web]) == .editable)
        }
        #expect(GlobalSpeedShortcutGuard.classify([
            Node(role: "AXStaticText", editable: false), Node(role: "AXGroup", editable: true), web
        ]) == .editable)
        #expect(GlobalSpeedShortcutGuard.classify([Node(role: "AXToolbar", editable: false), web]) == .outsideWebContent)
        #expect(GlobalSpeedShortcutGuard.classify([Node(role: "AXGroup", editable: false)]) == .unknown)
        #expect(GlobalSpeedShortcutGuard.classify([]) == .unknown)
    }
}
