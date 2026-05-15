//
//  SessionNameStore.swift
//  WatchDog_iOS
//
//  Created by Sebastian Forenza 2026.
//
//  Lightweight persistent map of session id → user-chosen name. Lives in
//  UserDefaults so a name set on one app launch survives the next.
//  Keyed by `MotionSession.id` (which equals the SESSION_START event's
//  UUID, stable across rebuilds and across the parser's recomputation).
//
//  Sessions don't have to have a name; the SessionDetailView just shows
//  a placeholder ("Unnamed session") when none is set. Names are
//  trimmed and empty strings are treated as a removal so the user can
//  blank the field to clear a previously-set name.
//

import Foundation
import Observation

@Observable
class SessionNameStore {
    static let shared = SessionNameStore()

    /// Public read-only map: session id → user-chosen name. Mutations
    /// go through `setName(_:for:)` so the disk write happens in
    /// lockstep with the in-memory update.
    private(set) var names: [UUID: String] = [:]

    private let storageKey = "watchdog_session_names_v1"

    private init() {
        loadFromDisk()
    }

    func name(for sessionID: UUID) -> String? {
        names[sessionID]
    }

    /// Set or clear a name. Whitespace-only input clears the entry so
    /// the user can blank the field to revert to the default
    /// placeholder. No-ops if the value doesn't actually change, so
    /// SwiftUI doesn't see spurious updates on every keystroke.
    func setName(_ raw: String?, for sessionID: UUID) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            guard names[sessionID] != trimmed else { return }
            names[sessionID] = trimmed
        } else {
            guard names[sessionID] != nil else { return }
            names.removeValue(forKey: sessionID)
        }
        saveToDisk()
    }

    /// Wipe entries for the given session ids — keeps the on-disk
    /// dictionary from accumulating orphan names when the user clears
    /// sessions via the Motion Report menu.
    func forget(sessionIDs: Set<UUID>) {
        guard !sessionIDs.isEmpty else { return }
        let before = names.count
        names = names.filter { !sessionIDs.contains($0.key) }
        if names.count != before { saveToDisk() }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let stringKeyed: [String: String] = Dictionary(
            uniqueKeysWithValues: names.map { ($0.key.uuidString, $0.value) }
        )
        do {
            let payload = try JSONEncoder().encode(stringKeyed)
            UserDefaults.standard.set(payload, forKey: storageKey)
        } catch {
            Log.err(.persist, "Save session names · \(error)")
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let stringKeyed = try JSONDecoder().decode([String: String].self, from: data)
            names = Dictionary(uniqueKeysWithValues: stringKeyed.compactMap {
                guard let id = UUID(uuidString: $0.key) else { return nil }
                return (id, $0.value)
            })
        } catch {
            Log.err(.persist, "Load session names · \(error)")
            names = [:]
        }
    }
}
