import SwiftUI
import UIKit
import ArcaCore
@testable import ArcaUI

@main
struct ArcaUXFlows: App {
    @State private var model = ArcaAppViewModel(rootDirectoryURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(ProcessInfo.processInfo.environment["ARCA_FIXTURE_WORKSPACE"] ?? UUID().uuidString))
    @State private var fixtureError: String?
    @State private var ready = false
    @StateObject private var purchases = ArcaPurchases()
    private var scenario: String { ProcessInfo.processInfo.environment["ARCA_FLOW_SCREEN"] ?? "onboarding" }
    // A rename changes collection display order; relaunch tests must reopen the same UUID.
    private var captureSchema: CollectionSchema? {
        model.collectionsInCurrentSpace.min { $0.id.uuidString < $1.id.uuidString }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if let fixtureError { Text("Fixture failed: " + fixtureError) }
                else if ready { screen }
                else { ProgressView("Loading fixture") }
            }
            .arcaApplyAppAccentEnvironment()
            .arcaDefaultTypography()
            .environment(\.arcaSubscriptionScreen, AnyView(ArcaPlanView(purchases: purchases, model: model)))
            .environment(\.locale, model.language.locale)
            .environment(\.layoutDirection, model.language.layoutDirection)
            .preferredColorScheme(model.appearanceMode.colorScheme)
            .background(KeyboardDismissal())
            .task {
                await model.bootstrapIfNeeded()
                if let dark = ProcessInfo.processInfo.environment["ARCA_FIXTURE_DARK"] {
                    model.appearanceMode = dark == "1" ? .dark : .light
                }
                await model.refreshSuggestedTemplates()
                if scenario != "onboarding" && !model.hasCompletedOnboarding {
                    await model.finishOnboarding(defaultMode: .localOnly, acceptedCloudTerms: false, selectedTemplates: model.suggestedTemplates)
                    if let initialSchema = captureSchema {
                        if ProcessInfo.processInfo.environment["ARCA_FIXTURE_IMAGES"] == "1" {
                            await model.addField(to: initialSchema.id, label: "Cover", type: .image)
                            await model.addField(to: initialSchema.id, label: "Ingredients", type: .image)
                        }
                        let schema = model.schema(for: initialSchema.id) ?? initialSchema
                        var values: [UUID: FieldValue] = [:]
                        for field in schema.fields {
                            switch field.type {
                            case .shortText: values[field.id] = .shortText("Demo 2026")
                            case .longText: values[field.id] = .longText("Sample record for design review")
                            case .number: values[field.id] = .number(12500)
                            case .currency: values[field.id] = .currency(MoneyValue(minorUnits: 12000, currencyCode: "USD"))
                            case .date: values[field.id] = .date(CalendarDate(year: 2026, month: 11, day: 5))
                            case .dateTime: values[field.id] = .dateTime(Date(timeIntervalSince1970: 1793872800))
                            case .boolean: values[field.id] = .boolean(true)
                            case .singleSelect: values[field.id] = field.options.first.map { .singleSelect($0.id) } ?? .null
                            case .multiSelect: values[field.id] = .multiSelect(field.options.prefix(1).map(\.id))
                            case .rating: values[field.id] = .rating(4)
                            case .image:
                                let photo = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { context in
                                    (field.label == "Cover" ? UIColor.systemOrange : UIColor.systemGreen).setFill()
                                    context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                                    UIImage(systemName: field.label == "Cover" ? "fish.fill" : "carrot.fill")?
                                        .withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 120, y: 120, width: 360, height: 360))
                                }
                                if let data = photo.pngData(), let reference = try? await model.attachImage(data: data, to: schema.spaceId) {
                                    values[field.id] = .attachments([reference])
                                }
                            case .attachment: values[field.id] = .attachments([])
                            }
                        }
                        try? await model.saveRecord(existingRecord: nil, schema: schema, values: values, isFavorite: true)
                        if ProcessInfo.processInfo.environment["ARCA_FIXTURE_REDESIGN"] == "1", let title = schema.primaryTitleField {
                            for name in ["Beta tool", "Gamma tool"] {
                                var otherValues = values
                                otherValues[title.id] = .shortText(name)
                                try? await model.saveRecord(existingRecord: nil, schema: schema, values: otherValues, isFavorite: false)
                            }
                        }
                    }
                }
                if scenario == "connected-sync" || scenario == "connected-devices" {
                    do {
                        try await model.connectCloudAccount(email: "ux.\(UUID().uuidString)@example.com", password: "Fixture-Only-Password-2026!", createAccount: true, recoveryPhrase: "")
                    } catch { fixtureError = error.localizedDescription }
                }
                ready = true
            }
        }
    }
    @ViewBuilder private var screen: some View {
        if scenario == "onboarding" || scenario == "home" {
            ArcaRootContainerView(viewModel: model)
        } else {
            NavigationStack {
                switch scenario {
                case "plan": ArcaPlanView(purchases: purchases, model: model)
                case "spaces": ManageSpacesSheetView(viewModel: model)
                case "templates": TemplateGallerySheetView(viewModel: model)
                case "manual": ManualCollectionBuilderSheetView(viewModel: model)
                case "ai": AICollectionAssistantSheetView(viewModel: model)
                case "insights": InsightsScreenView(viewModel: model)
                case "settings": SettingsHubScreenView(viewModel: model)
                case "backups": BackupExportRestoreScreenView(viewModel: model)
                case "sync", "connected-sync": SyncStatusAndConflictsScreenView(viewModel: model)
                case "devices", "connected-devices": ActiveDeviceManagementScreenView(viewModel: model)
                case "privacy": PrivacyAndEncryptionDetailsView(viewModel: model)
                case "migration": if let space = model.currentSpace { StorageModeMigrationScreenView(viewModel: model, space: space) }
                case "sensitive": if let schema = captureSchema { SensitivePrivacyConsentView(viewModel: model, collectionId: schema.id) }
                case "fields": if let schema = captureSchema { FieldEditorSheetView(viewModel: model, collectionId: schema.id) }
                case "collection-settings": if let schema = captureSchema { CollectionSettingsView(viewModel: model, schema: schema) }
                case "collection": if let schema = captureSchema { CollectionRecordListView(viewModel: model, schema: schema) }
                case "record-new": if let schema = captureSchema { AddEditRecordSheetView(viewModel: model, schema: schema, existingRecord: nil) }
                case "record-edit": if let schema = captureSchema, let record = model.recordsInCurrentSpace.first { AddEditRecordSheetView(viewModel: model, schema: schema, existingRecord: record) }
                case "record-detail": if let schema = captureSchema, let record = model.recordsInCurrentSpace.first { RecordDetailView(viewModel: model, recordId: record.id, schema: schema) }
                default: Text("Unknown test route")
                }
            }
        }
    }
}
