//
//  ViewAppIntent.swift
//  AltWidgetExtension
//
//  Replaces the legacy SiriKit ViewAppIntent (ViewApp.intentdefinition) with a
//  modern AppIntents-based intent. Required because IntentConfiguration does not
//  support containerBackground on iOS 17+, causing the blank-widget bug.
//

import AppIntents
import WidgetKit

// Represents one installed app in the picker list.
@available(iOS 17.0, *)
struct InstalledAppEntity: AppEntity
{
    // Disambiguates from the AppEntity name used in AppIntents framework.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Installed App"
    static var defaultQuery = InstalledAppQuery()

    var id: String // bundle identifier
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17.0, *)
struct InstalledAppQuery: EntityQuery
{
    func entities(for identifiers: [String]) async throws -> [InstalledAppEntity]
    {
        debugLog("[InstalledAppQuery] Fetching entities for identifiers: \(identifiers)")
        let snapshot = WidgetDataManager.shared.fetchSnapshot()
        let matching = snapshot.allApps.filter { identifiers.contains($0.bundleIdentifier) }
        return matching.map { InstalledAppEntity(id: $0.bundleIdentifier, name: $0.name) }
    }

    func suggestedEntities() async throws -> [InstalledAppEntity]
    {
        let snapshot = WidgetDataManager.shared.fetchSnapshot()
        let items = snapshot.activeApps.isEmpty ? snapshot.allApps : snapshot.activeApps
        debugLog("[InstalledAppQuery] Suggested entities requested (\(items.count) app(s) returned)")
        return items
            .map { InstalledAppEntity(id: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name < $1.name }
    }
}

@available(iOS 17.0, *)
struct SelectAppIntent: WidgetConfigurationIntent
{
    static var title: LocalizedStringResource = "Select App"
    static var description = IntentDescription("Choose which app to display.")

    @Parameter(title: "App")
    var app: InstalledAppEntity?

    // WidgetConfigurationIntent requires perform() — no-op for configuration intents.
    func perform() async throws -> some IntentResult { .result() }
}
