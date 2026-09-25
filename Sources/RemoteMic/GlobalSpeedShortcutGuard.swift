import AppKit
import ApplicationServices

/// Scope the personal test build's five video bindings without changing ordinary shortcuts.
enum GlobalSpeedShortcutGuard {
    enum Focus: String {
        case webContent = "web_content"
        case editable
        case outsideWebContent = "outside_web_content"
        case unknown
    }

    struct Node {
        let role: String
        let editable: Bool
    }

    struct Application {
        let pid: pid_t
        let bundleIdentifier: String?
    }

    static func applies(
        button: RemoteButton, trigger: ButtonTrigger, configured: ConfiguredButtonAction
    ) -> Bool {
        let keys: [RemoteButton: UInt16] = [.up: 91, .down: 84, .left: 86, .right: 88, .ok: 87]
        guard trigger == .longPress, configured.action == .customShortcut,
              let shortcut = configured.shortcut, shortcut.modifierFlags.isEmpty
        else { return false }
        return keys[button] == shortcut.keyCode
    }

    static func skipReason(
        button: RemoteButton, trigger: ButtonTrigger, configured: ConfiguredButtonAction,
        isTestBuild: Bool = VirtualHIDShortcutBridge.isTestBuild,
        frontmost: () -> Application? = {
            NSWorkspace.shared.frontmostApplication.map {
                Application(pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier)
            }
        },
        focus: (pid_t) -> Focus = chromeFocus
    ) -> String? {
        guard isTestBuild, applies(button: button, trigger: trigger, configured: configured)
        else { return nil }
        guard let app = frontmost(), app.bundleIdentifier == "com.google.Chrome"
        else { return "not_chrome" }
        let state = focus(app.pid)
        guard state == .webContent else { return state.rawValue }
        // Do not send to a different app if focus changed while AX was responding.
        guard frontmost()?.pid == app.pid else { return "focus_changed" }
        return nil
    }

    static func classify(_ nodes: [Node]) -> Focus {
        for node in nodes {
            if node.editable || ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(node.role) {
                return .editable
            }
            if node.role == "AXWebArea" { return .webContent }
            if ["AXWindow", "AXApplication", "AXToolbar", "AXMenu", "AXMenuBar"].contains(node.role) {
                return .outsideWebContent
            }
        }
        return .unknown
    }

    /// Reads only public accessibility roles/capabilities, never text, titles, URLs or values.
    static func chromeFocus(_ pid: pid_t) -> Focus {
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(app, 0.05) == .success,
              let focused = element(app, kAXFocusedUIElementAttribute)
        else { return .unknown }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        var current = focused
        var nodes: [Node] = []
        for _ in 0..<24 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return .unknown }
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
                  let role = role as? String
            else { return .unknown }
            var writable = DarwinBoolean(false)
            let result = AXUIElementIsAttributeSettable(current, kAXValueAttribute as CFString, &writable)
            guard result == .success || result == .attributeUnsupported else { return .unknown }
            var editable: CFTypeRef?
            let editableResult = AXUIElementCopyAttributeValue(current, "AXEditable" as CFString, &editable)
            guard [.success, .attributeUnsupported, .noValue].contains(editableResult) else { return .unknown }
            nodes.append(Node(role: role, editable: writable.boolValue || (editable as? Bool == true)))
            let state = classify(nodes)
            if state != .unknown {
                guard ProcessInfo.processInfo.systemUptime < deadline,
                      let stillFocused = element(app, kAXFocusedUIElementAttribute),
                      CFEqual(focused, stillFocused)
                else { return .unknown }
                return state
            }
            guard let parent = element(current, kAXParentAttribute) else { return .unknown }
            current = parent
        }
        return .unknown
    }

    private static func element(_ source: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(source, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}
