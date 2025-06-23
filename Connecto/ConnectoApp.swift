//
//  ConnectoApp.swift
//  Connecto Watch App
//
//  Created by Devin Oldenburg on 29/11/2024.
//

import SwiftUI
import WatchConnectivity

struct Preset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var value: Int
}

final class PresetStore: NSObject, ObservableObject {
    @Published var presets: [Preset] = [] {
        didSet {
            sendPresetsToPhone()
        }
    }
    
    private var session: WCSession?
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    /// Send the current presets to the paired iPhone.
    private func sendPresetsToPhone() {
        guard let session = session, session.isReachable else { return }
        do {
            let data = try JSONEncoder().encode(presets)
            let message = ["presets": data]
            session.sendMessage(message, replyHandler: nil)
        } catch {
            print("Failed to encode or send presets: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension PresetStore: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed with error: \(error.localizedDescription)")
            return
        }
        print("WCSession activated with state: \(activationState.rawValue)")
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let data = message["presets"] as? Data {
            do {
                let receivedPresets = try JSONDecoder().decode([Preset].self, from: data)
                DispatchQueue.main.async {
                    self.presets = receivedPresets
                }
            } catch {
                print("Failed to decode presets received: \(error)")
            }
        }
    }
    
    #if os(watchOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}

/// This PresetStore logic mirrors the iOS-side PresetStore, synchronizing presets between watch and phone.

@main
struct Connecto_Watch_AppApp: App {
    @StateObject private var presetStore = PresetStore()
    
    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(presetStore)
        }
    }
}
