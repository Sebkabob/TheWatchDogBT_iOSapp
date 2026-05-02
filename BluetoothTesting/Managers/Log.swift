//
//  Log.swift
//  BluetoothTesting
//
//  Centralized debug logger. Replaces ad-hoc print() calls with a
//  consistent boxed format that auto-includes device context (SOC,
//  charge, lock state) on connection-relevant lines.
//
//  Usage:
//      Log.ok(.ble, "Connected to WatchDog 01")
//      Log.warn(.bond, "Already bonded")
//      Log.tx(.loyalty, "CLAIM token=AABBCCDD")
//
//  Output:
//      ╭──────────────────────────────────────────────╮
//      │  🐶  WatchDog · Debug Log                    │
//      ╰──────────────────────────────────────────────╯
//      ┃ 📡 BLE     ┃ ✓ Connected to WatchDog 01    ⟢ 🔋84% 🔌 · 🔒 Armed
//

import Foundation

// MARK: - Tags

enum LogTag: String {
    case ble      = "BLE"
    case bond     = "BOND"
    case loyalty  = "LOYALTY"
    case motion   = "MOTION"
    case diag     = "DIAG"
    case battery  = "BATTERY"
    case settings = "SETTING"
    case nav      = "NAV"
    case name     = "NAME"
    case icon     = "ICON"
    case persist  = "PERSIST"
    case view     = "VIEW"
    case scene    = "SCENE"

    var glyph: String {
        switch self {
        case .ble:      return "📡"
        case .bond:     return "🔗"
        case .loyalty:  return "🛡"
        case .motion:   return "📈"
        case .diag:     return "🩺"
        case .battery:  return "🔋"
        case .settings: return "⚙"
        case .nav:      return "🧭"
        case .name:     return "🏷"
        case .icon:     return "🎨"
        case .persist:  return "💾"
        case .view:     return "🎬"
        case .scene:    return "🎭"
        }
    }

    /// Lines for these tags auto-append device context (SOC, lock state)
    /// when a device is connected.
    var includesContext: Bool {
        switch self {
        case .ble, .bond, .loyalty, .motion, .diag, .battery, .settings:
            return true
        case .nav, .name, .icon, .persist, .view, .scene:
            return false
        }
    }
}

// MARK: - Levels

enum LogLevel {
    case info, ok, warn, error, tx, rx

    var glyph: String {
        switch self {
        case .info:  return "·"
        case .ok:    return "✓"
        case .warn:  return "⚠"
        case .error: return "✗"
        case .tx:    return "→"
        case .rx:    return "←"
        }
    }
}

// MARK: - Log

enum Log {
    /// Returns a short context string like "🔋84% 🔌 · 🔒 Armed".
    /// Set by BluetoothManager.init. Returns nil if no device connected.
    nonisolated(unsafe) static var contextProvider: () -> String? = { nil }

    private static let tagColumnCells = 12  // visual width of "GLYPH TAG     "
    nonisolated(unsafe) private static var headerPrinted = false
    private static let lock = NSLock()

    // MARK: Banner

    static func banner() {
        lock.lock(); defer { lock.unlock() }
        guard !headerPrinted else { return }
        headerPrinted = true
        print("")
        print("╭──────────────────────────────────────────────╮")
        print("│  🐶  WatchDog · Debug Log                    │")
        print("╰──────────────────────────────────────────────╯")
    }

    // MARK: Core write

    static func write(_ tag: LogTag, _ level: LogLevel, _ msg: String, ctx: Bool? = nil) {
        if !headerPrinted { banner() }

        // Pad the tag column. Glyph counts as 2 visual cells in most
        // monospaced fonts; one space separator; then the tag text.
        let glyphCells = 2
        let used = glyphCells + 1 + tag.rawValue.count
        let pad = max(1, tagColumnCells - used)
        let padding = String(repeating: " ", count: pad)

        var line = "┃ \(tag.glyph) \(tag.rawValue)\(padding)┃ \(level.glyph) \(msg)"

        let useCtx = ctx ?? tag.includesContext
        if useCtx, let context = contextProvider() {
            line += "    ⟢ \(context)"
        }

        print(line)
    }

    // MARK: Convenience

    static func info(_ tag: LogTag, _ msg: String, ctx: Bool? = nil)  { write(tag, .info,  msg, ctx: ctx) }
    static func ok(_ tag: LogTag, _ msg: String, ctx: Bool? = nil)    { write(tag, .ok,    msg, ctx: ctx) }
    static func warn(_ tag: LogTag, _ msg: String, ctx: Bool? = nil)  { write(tag, .warn,  msg, ctx: ctx) }
    static func err(_ tag: LogTag, _ msg: String, ctx: Bool? = nil)   { write(tag, .error, msg, ctx: ctx) }
    static func tx(_ tag: LogTag, _ msg: String, ctx: Bool? = nil)    { write(tag, .tx,    msg, ctx: ctx) }
    static func rx(_ tag: LogTag, _ msg: String, ctx: Bool? = nil)    { write(tag, .rx,    msg, ctx: ctx) }

    // MARK: Section divider — for grouping a multi-step flow

    static func section(_ title: String) {
        if !headerPrinted { banner() }
        let inner = " \(title) "
        let dashes = max(2, 44 - inner.count)
        print("┃")
        print("┃ ╭─\(inner)\(String(repeating: "─", count: dashes))╮")
    }

    static func endSection() {
        print("┃ ╰\(String(repeating: "─", count: 50))╯")
        print("┃")
    }
}
