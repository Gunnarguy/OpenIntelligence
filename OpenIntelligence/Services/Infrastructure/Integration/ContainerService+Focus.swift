//
//  ContainerService+Focus.swift
//  OpenIntelligence
//

import Combine
import Foundation

/// What the library pickers offer while a Focus filter is on (5.7).
///
/// The filter (`LibraryFocusFilterIntent`) names libraries in Settings, Focus. While that Focus is
/// on, the pickers list those libraries, and the open library moves to the first of them when it is
/// not one. The allowed set is kept in `UserDefaults` beside the open library's id, because the
/// system can run the filter while no screen is open.
extension ContainerService {
    static let focusLibraryIdsKey = "focusLibraryIds"

    /// The libraries the Focus filter allows; nil when no filter is in force.
    var focusLibraryIds: Set<UUID>? {
        guard let stored = UserDefaults.standard.array(forKey: Self.focusLibraryIdsKey) as? [String] else {
            return nil
        }
        let ids = Set(stored.compactMap(UUID.init(uuidString:)))
        return ids.isEmpty ? nil : ids
    }

    /// The libraries a picker lists: all of them, or the ones the Focus filter allows. The open
    /// library is always listed, and a filter that names no library that exists hides nothing.
    var pickableContainers: [KnowledgeContainer] {
        // In the order this device shows them (`orderedContainers`, 5.7).
        Self.pickable(orderedContainers, allowed: focusLibraryIds, active: activeContainerId)
    }

    static func pickable(
        _ containers: [KnowledgeContainer], allowed: Set<UUID>?, active: UUID
    ) -> [KnowledgeContainer] {
        guard let allowed else { return containers }
        let shown = containers.filter { allowed.contains($0.id) || $0.id == active }
        return shown.contains(where: { allowed.contains($0.id) }) ? shown : containers
    }

    /// Applies a Focus filter: the libraries it names, or none to lift it. The system sends the
    /// filter's empty value when the Focus turns off.
    func applyFocusFilter(_ ids: [UUID]?) {
        let allowed = Set(ids ?? [])
        objectWillChange.send()
        if allowed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.focusLibraryIdsKey)
            Log.info("[Focus] Library filter lifted", category: .ui)
            return
        }
        UserDefaults.standard.set(allowed.map(\.uuidString).sorted(), forKey: Self.focusLibraryIdsKey)
        Log.info("[Focus] Library filter: \(allowed.count) librar\(allowed.count == 1 ? "y" : "ies")", category: .ui)
        if !allowed.contains(activeContainerId), let first = orderedContainers.first(where: { allowed.contains($0.id) }) {
            setActive(first.id)
        }
    }
}
