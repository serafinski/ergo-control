import ApplicationServices
import ErgoCore

/// Bounded transport-only discovery shared by focused and explicit music routing.
struct MediaAccessibilitySnapshot {
    let nodes: [MediaControlNode]
    let elements: [AXUIElement]
    let discovery: MediaControlDiscovery
    static func read(_ root: AXUIElement, deadline: TimeInterval = ProcessInfo.processInfo.systemUptime + 0.6) -> MediaAccessibilitySnapshot? {
        var pending: [(AXUIElement, Int?, Int)] = [(root, nil, 0)]
        var nodes: [MediaControlNode] = [], elements: [AXUIElement] = []
        while let (element, parent, depth) = pending.popLast() {
            guard elements.count < 1600, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let values = attributes(element, [kAXRoleAttribute, kAXChildrenAttribute])
            let role = values.first as? String ?? ""
            var control: MediaControl?, enabled = true
            if role == kAXButtonRole {
                let labels = attributes(element, [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXEnabledAttribute])
                control = MediaControl.button(labels: labels.prefix(3).compactMap { $0 as? String })
                enabled = (labels.last as? Bool) ?? true
            } else if role == kAXSliderRole {
                let labels = attributes(element, [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute])
                control = MediaControl.slider(labels: labels.compactMap { $0 as? String })
            }
            let index = elements.count
            elements.append(element); nodes.append(MediaControlNode(parent: parent, control: control, enabled: enabled))
            if let children = values.last as? [AXUIElement] {
                // An incomplete tree cannot safely establish a unique player.
                guard children.isEmpty || depth < 40 else { return nil }
                for child in children.reversed() { pending.append((child, index, depth + 1)) }
            }
        }
        return MediaAccessibilitySnapshot(nodes: nodes, elements: elements, discovery: MediaControlDiscovery.find(in: nodes))
    }
    private static func attributes(_ element: AXUIElement, _ names: [String]) -> [Any] {
        var result: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &result) == .success,
              let values = result as? [Any] else { return [] }
        return values
    }
}
