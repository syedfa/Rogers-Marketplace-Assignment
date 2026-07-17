//
//  Rogers_Marketplace_AssignmentApp.swift
//  Rogers-Marketplace Assignment
//
//  Created by Fayyazuddin  Syed on 2026-07-16.
//

import SwiftUI

@main
struct Rogers_Marketplace_AssignmentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let dependencies = AppDependencies.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.dependencies, dependencies)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            Task {
                let pending = (try? await dependencies.repository.pendingChanges()) ?? []
                guard !pending.isEmpty else { return }
                for change in pending {
                    dependencies.backgroundUploader.enqueue(change)
                }
                dependencies.backgroundTaskCoordinator.scheduleSync()
            }
        }
    }
}
