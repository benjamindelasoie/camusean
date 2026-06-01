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
    @State private var containerState: ContainerState

    init() {
        KeychainService.seedAPIKeyIfNeeded()
        _containerState = State(initialValue: Self.loadInitial())
    }

    var body: some Scene {
        WindowGroup {
            switch containerState {
            case .loaded(let container):
                ContentView()
                    .modelContainer(container)
            case .failed(let error):
                ModelContainerErrorView(
                    error: error,
                    onReset: handleReset,
                    onRetry: handleRetry
                )
            }
        }
    }

    private static func loadInitial() -> ContainerState {
        switch ModelContainerLoader.load() {
        case .success(let container): return .loaded(container)
        case .failure(let error): return .failed(error)
        }
    }

    private func handleRetry() {
        containerState = Self.loadInitial()
    }

    private func handleReset() {
        do {
            try ModelContainerLoader.resetStore()
            containerState = Self.loadInitial()
        } catch {
            containerState = .failed(error)
        }
    }
}

private enum ContainerState {
    case loaded(ModelContainer)
    case failed(Error)
}
