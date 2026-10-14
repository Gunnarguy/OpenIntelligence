//
//  SyncableEntities.swift
//  OpenIntelligence
//

import AppIntents

/// Documents and libraries keep one identifier on every device: a UUID made with the item, which the
/// shared workspace carries to the person's other devices unchanged. Saying so lets the system refer
/// to the same item across devices, as Siri does when it carries a conversation from one device to
/// another (Apple's `SyncableEntity`: an entity whose identifier is already the same across devices
/// adopts it with no other change; read 2026-10-14). An item in a library that is not shared exists
/// on one device only, and another device finds nothing for it (5.7). Conversations are left out
/// while how they sync between devices is still an open decision.
@available(iOS 27.0, macOS 27.0, *)
extension OIDocumentEntity: SyncableEntity {}

@available(iOS 27.0, macOS 27.0, *)
extension OILibraryEntity: SyncableEntity {}
