//
//  Video2LiveApp.swift
//  Video2Live
//
//  Created by Sun on 2025/3/17.
//

import SwiftUI

@main
struct Video2LiveApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
