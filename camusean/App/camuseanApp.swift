//
//  camuseanApp.swift
//  camusean
//
//  Created by Benjamin Delasoie on 14/05/2026.
//

import SwiftUI
import SwiftData

@main
struct camuseanApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: CamuseanSchemaV2.self)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: CamuseanMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            // TODO: replace fatalError with recovery UI before App Store. See TODOS.md.
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
