import Combine
import SwiftUI
import UIKit
import UserNotifications
import Network
import Foundation

struct HTTPHeader: Identifiable, Codable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}

struct HTTPRequest: Identifiable, Codable {
    var id: UUID
    var name: String
    var url: String
    var method: String
    var headers: [HTTPHeader]
    var body: String
    var timeout: Double
    var followRedirects: Bool
    
    init() {
        self.id = UUID()
        self.name = "New Request"
        self.url = ""
        self.method = "GET"
        self.headers = []
        self.body = ""
        self.timeout = 30.0
        self.followRedirects = true
    }
}

struct PingMonitor: Identifiable, Codable {
    let id: UUID
    var name: String
    var host: String
    var url: String
    var port: Int?
    var isEnabled: Bool
    var lastStatus: PingStatus
    var status: PingStatus // Current status
    var lastChecked: Date?
    var lastCheck: Date? // Alternative naming used in some places
    var responseTime: Double?
    var checkInterval: TimeInterval = 30.0 // Check every 30 seconds
    var lastError: String?
    
    init(name: String, host: String, port: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.url = port != nil ? "\(host):\(port!)" : host
        self.port = port
        self.isEnabled = true
        self.lastStatus = .unknown
        self.status = .unknown
        self.lastChecked = nil
        self.lastCheck = nil
        self.responseTime = nil
        self.lastError = nil
    }
}

enum PingStatus: String, Codable, CaseIterable {
    case online = "online"
    case offline = "offline"
    case unknown = "unknown"
    
    var color: Color {
        switch self {
        case .online: return .green
        case .offline: return .red
        case .unknown: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .online: return "checkmark.circle.fill"
        case .offline: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

// Real Network Monitoring Service
class NetworkMonitoringService: ObservableObject {
    private var timers: [UUID: Timer] = [:]
    
    func startMonitoring(_ monitor: PingMonitor, updateCallback: @escaping (PingMonitor) -> Void) {
        stopMonitoring(monitor.id)
        
        let timer = Timer.scheduledTimer(withTimeInterval: monitor.checkInterval, repeats: true) { _ in
            Task {
                await self.checkHost(monitor, updateCallback: updateCallback)
            }
        }
        
        timers[monitor.id] = timer
        
        // Perform initial check
        Task {
            await checkHost(monitor, updateCallback: updateCallback)
        }
    }
    
    func stopMonitoring(_ monitorId: UUID) {
        timers[monitorId]?.invalidate()
        timers.removeValue(forKey: monitorId)
    }
    
    func stopAllMonitoring() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
    
    private func checkHost(_ monitor: PingMonitor, updateCallback: @escaping (PingMonitor) -> Void) async {
        var updatedMonitor = monitor
        let startTime = Date()
        
        do {
            let isReachable = try await performConnectivityCheck(host: monitor.host, port: monitor.port)
            let responseTime = Date().timeIntervalSince(startTime) * 1000 // Convert to milliseconds
            
            updatedMonitor.lastStatus = updatedMonitor.status
            updatedMonitor.status = isReachable ? .online : .offline
            updatedMonitor.responseTime = responseTime
            updatedMonitor.lastChecked = Date()
            updatedMonitor.lastCheck = Date()
            updatedMonitor.lastError = nil
            
        } catch {
            updatedMonitor.lastStatus = updatedMonitor.status
            updatedMonitor.status = .offline
            updatedMonitor.responseTime = nil
            updatedMonitor.lastChecked = Date()
            updatedMonitor.lastCheck = Date()
            updatedMonitor.lastError = error.localizedDescription
        }
        
        DispatchQueue.main.async {
            updateCallback(updatedMonitor)
        }
    }
    
    private func performConnectivityCheck(host: String, port: Int?) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            let connection: NWConnection
            
            if let port = port {
                connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tcp)
            } else {
                // Default to HTTP port 80
                connection = NWConnection(host: NWEndpoint.Host(host), port: .http, using: .tcp)
            }
            
            connection.start(queue: .global())
            
            var hasCompleted = false
            
            connection.stateUpdateHandler = { state in
                guard !hasCompleted else { return }
                hasCompleted = true
                
                switch state {
                case .ready:
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed(let error):
                    connection.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    if !hasCompleted {
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            
            // Timeout after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if !hasCompleted {
                    hasCompleted = true
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

struct Collection: Identifiable, Codable {
    let id: UUID
    var name: String
    var requests: [HTTPRequest]
    var monitors: [PingMonitor]
    var color: String
    
    init(name: String, requests: [HTTPRequest] = [], monitors: [PingMonitor] = []) {
        self.id = UUID()
        self.name = name
        self.requests = requests
        self.monitors = monitors
        self.color = "blue"
    }
}

class HTTPClientViewModel: ObservableObject {
    @Published var collections: [Collection] = []
    @Published var requestHistory: [HTTPRequest] = []
    @Published var monitors: [PingMonitor] = []
    @Published var hapticFeedbackEnabled: Bool = true
    @Published var requestTimeout: Double = 30.0
    
    private let collectionsKey = "HTTPCollections"
    private let historyKey = "RequestHistory"
    private let monitorsKey = "PingMonitors"
    private let hapticKey = "HapticFeedbackEnabled"
    private let timeoutKey = "DefaultRequestTimeout"
    
    // Network monitoring service
    private let monitoringService = NetworkMonitoringService()

    init() {
        loadData()
        setupDefaultData()
        startMonitoringActiveMonitors()
    }
    
    deinit {
        monitoringService.stopAllMonitoring()
    }

    private func loadData() {
        loadCollections()
        loadHistory()
        loadMonitors()
        loadSettings()
    }
    
    private func setupDefaultData() {
        // Only create default collection if no data exists at all
        if collections.isEmpty && requestHistory.isEmpty {
            let defaultCollection = Collection(name: "My Requests")
            collections.append(defaultCollection)
            saveCollections()
        }
        
        // Don't create default environments - let users create them as needed
        // if environments.isEmpty {
        //     let localEnv = HTTPEnvironment(name: "Local", baseURL: "http://localhost:3000")
        //     environments = [localEnv]
        //     activeEnvironment = localEnv
        //     saveEnvironments()
        // }
        
        // Don't create default monitors - let users add them as needed
        // if monitors.isEmpty {
        //     let googleMonitor = PingMonitor(name: "Google", host: "google.com")
        //     monitors = [googleMonitor]
        //     saveMonitors()
        // }
    }

    func saveCollections() {
        if let encoded = try? JSONEncoder().encode(collections) {
            UserDefaults.standard.set(encoded, forKey: collectionsKey)
        }
    }

    func saveHistory() {
        if let encoded = try? JSONEncoder().encode(requestHistory) {
            UserDefaults.standard.set(encoded, forKey: historyKey)
        }
    }
    
    func saveMonitors() {
        if let encoded = try? JSONEncoder().encode(monitors) {
            UserDefaults.standard.set(encoded, forKey: monitorsKey)
        }
    }

    private func loadCollections() {
        if let data = UserDefaults.standard.data(forKey: collectionsKey),
           let decoded = try? JSONDecoder().decode([Collection].self, from: data) {
            collections = decoded
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([HTTPRequest].self, from: data) {
            requestHistory = decoded
        }
    }
    
    private func loadMonitors() {
        if let data = UserDefaults.standard.data(forKey: monitorsKey),
           let decoded = try? JSONDecoder().decode([PingMonitor].self, from: data) {
            monitors = decoded
        }
    }
    
    private func loadSettings() {
        hapticFeedbackEnabled = UserDefaults.standard.object(forKey: hapticKey) as? Bool ?? true
        requestTimeout = UserDefaults.standard.object(forKey: timeoutKey) as? Double ?? 30.0
    }
    
    func saveSettings() {
        UserDefaults.standard.set(hapticFeedbackEnabled, forKey: hapticKey)
        UserDefaults.standard.set(requestTimeout, forKey: timeoutKey)
    }
    
    
    func calculateStorageUsage() -> String {
        // Calculate actual data size in bytes
        var totalSize = 0
        
        // Calculate collections size
        if let collectionsData = try? JSONEncoder().encode(collections) {
            totalSize += collectionsData.count
        }
        
        // Calculate history size
        if let historyData = try? JSONEncoder().encode(requestHistory) {
            totalSize += historyData.count
        }
        
        // Calculate monitors size
        if let monitorsData = try? JSONEncoder().encode(monitors) {
            totalSize += monitorsData.count
        }
        
        // Convert bytes to appropriate unit
        let sizeInKB = Double(totalSize) / 1024.0
        
        if sizeInKB < 1.0 {
            return "\(totalSize) B"
        } else if sizeInKB < 1024.0 {
            return String(format: "%.1f KB", sizeInKB)
        } else {
            let sizeInMB = sizeInKB / 1024.0
            return String(format: "%.1f MB", sizeInMB)
        }
    }
    
    // MARK: - Template Functionality
    func loadRequestAsTemplate(_ request: HTTPRequest, completion: @escaping (HTTPRequest) -> Void) {
        var templateRequest = request
        templateRequest.id = UUID()
        templateRequest.name = "Copy of \(request.name)"
        completion(templateRequest)
        triggerHapticFeedback(.light)
    }
    
    func triggerHapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticFeedbackEnabled else { return }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: style)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
    }
    
    func triggerSuccessHaptic() {
        guard hapticFeedbackEnabled else { return }
        
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.success)
    }
    
    func triggerErrorHaptic() {
        guard hapticFeedbackEnabled else { return }
        
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.error)
    }
    
    func triggerWarningHaptic() {
        guard hapticFeedbackEnabled else { return }
        
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.prepare()
        feedbackGenerator.notificationOccurred(.warning)
    }
    
    func addToHistory(_ request: HTTPRequest) {
        var historyRequest = request
        historyRequest.name = "Request at \(DateFormatter.shortTime.string(from: Date()))"
        requestHistory.insert(historyRequest, at: 0)
        if requestHistory.count > 100 {
            requestHistory = Array(requestHistory.prefix(100))
        }
        saveHistory()
        triggerHapticFeedback(.light)
    }
    
    func addCollection(_ collection: Collection) {
        collections.append(collection)
        saveCollections()
        triggerHapticFeedback(.medium)
    }
    
    func addRequest(_ request: HTTPRequest, to collection: Collection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].requests.append(request)
            saveCollections()
            triggerHapticFeedback(.light)
        }
    }
    
    func deleteCollection(at offsets: IndexSet) {
        collections.remove(atOffsets: offsets)
        saveCollections()
        triggerHapticFeedback(.heavy)
    }
    
    func deleteRequest(at offsets: IndexSet, from collection: Collection) {
        if let collectionIndex = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[collectionIndex].requests.remove(atOffsets: offsets)
            saveCollections()
            triggerHapticFeedback(.medium)
        }
    }
    
    func moveRequest(_ request: HTTPRequest, from sourceCollection: Collection, to targetCollection: Collection) {
        // Remove from source collection
        if let sourceIndex = collections.firstIndex(where: { $0.id == sourceCollection.id }),
           let requestIndex = collections[sourceIndex].requests.firstIndex(where: { $0.id == request.id }) {
            collections[sourceIndex].requests.remove(at: requestIndex)
        }
        
        // Add to target collection
        if let targetIndex = collections.firstIndex(where: { $0.id == targetCollection.id }) {
            collections[targetIndex].requests.append(request)
        }
        
        saveCollections()
    }
    
    func duplicateRequest(_ request: HTTPRequest, in collection: Collection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            var duplicatedRequest = request
            duplicatedRequest.id = UUID()
            duplicatedRequest.name = "\(request.name) (Copy)"
            collections[index].requests.append(duplicatedRequest)
            saveCollections()
        }
    }
    
    // MARK: - Monitor Management
    func addMonitor(_ monitor: PingMonitor, to collection: Collection? = nil) {
        if let collection = collection {
            // Add to specific collection
            if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[index].monitors.append(monitor)
                saveCollections()
            }
        } else {
            // Add to global monitors
            monitors.append(monitor)
            saveMonitors()
        }
        
        if monitor.isEnabled {
            startMonitoringSpecific(monitor)
        }
        triggerHapticFeedback(.medium)
    }
    
    func removeMonitor(at offsets: IndexSet) {
        for index in offsets {
            let monitor = monitors[index]
            monitoringService.stopMonitoring(monitor.id)
        }
        monitors.remove(atOffsets: offsets)
        saveMonitors()
        triggerHapticFeedback(.light)
    }
    
    func updateMonitor(_ monitor: PingMonitor) {
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            let oldMonitor = monitors[index]
            monitors[index] = monitor
            saveMonitors()
            
            // Restart monitoring if status changed
            if oldMonitor.isEnabled != monitor.isEnabled {
                if monitor.isEnabled {
                    startMonitoringSpecific(monitor)
                } else {
                    monitoringService.stopMonitoring(monitor.id)
                }
            } else if monitor.isEnabled {
                // Restart with new settings
                startMonitoringSpecific(monitor)
            }
        }
    }
    
    func toggleMonitor(_ monitor: PingMonitor) {
        if let index = monitors.firstIndex(where: { $0.id == monitor.id }) {
            monitors[index].isEnabled.toggle()
            let updatedMonitor = monitors[index]
            
            if updatedMonitor.isEnabled {
                startMonitoringSpecific(updatedMonitor)
            } else {
                monitoringService.stopMonitoring(updatedMonitor.id)
            }
            
            saveMonitors()
            triggerHapticFeedback(.light)
        }
    }
    
    private func startMonitoringActiveMonitors() {
        // Monitor global monitors
        for monitor in monitors.filter({ $0.isEnabled }) {
            startMonitoringSpecific(monitor)
        }
        
        // Monitor collection monitors
        for collection in collections {
            for monitor in collection.monitors.filter({ $0.isEnabled }) {
                startMonitoringSpecific(monitor)
            }
        }
    }
    
    func getAllMonitors() -> [PingMonitor] {
        var allMonitors = monitors
        for collection in collections {
            allMonitors.append(contentsOf: collection.monitors)
        }
        return allMonitors
    }
    
    private func startMonitoringSpecific(_ monitor: PingMonitor) {
        monitoringService.startMonitoring(monitor) { [weak self] updatedMonitor in
            guard let self = self else { return }
            
            // Update in global monitors
            if let index = self.monitors.firstIndex(where: { $0.id == updatedMonitor.id }) {
                self.monitors[index] = updatedMonitor
                self.saveMonitors()
                return
            }
            
            // Update in collection monitors
            for collectionIndex in 0..<self.collections.count {
                if let monitorIndex = self.collections[collectionIndex].monitors.firstIndex(where: { $0.id == updatedMonitor.id }) {
                    self.collections[collectionIndex].monitors[monitorIndex] = updatedMonitor
                    self.saveCollections()
                    
                    // Trigger status change haptic if status changed
                    let oldStatus = self.collections[collectionIndex].monitors[monitorIndex].lastStatus
                    if oldStatus != updatedMonitor.status && updatedMonitor.status != .unknown {
                        if updatedMonitor.status == .offline && oldStatus == .online {
                            self.triggerErrorHaptic()
                        } else if updatedMonitor.status == .online && oldStatus == .offline {
                            self.triggerSuccessHaptic()
                        }
                    }
                    return
                }
            }
        }
    }
    
    func updateCollection(_ collection: Collection) {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = collection
            saveCollections()
        }
    }
    
    func clearHistory() {
        requestHistory.removeAll()
        saveHistory()
    }
    
    // MARK: - App Reset Functionality
    func resetAllData() {
        // Clear all stored data
        UserDefaults.standard.removeObject(forKey: collectionsKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        UserDefaults.standard.removeObject(forKey: monitorsKey)
        UserDefaults.standard.removeObject(forKey: hapticKey)
        UserDefaults.standard.removeObject(forKey: timeoutKey)
        
        // Reset in-memory collections
        collections.removeAll()
        requestHistory.removeAll()
        monitors.removeAll()
        
        // Reset settings to defaults
        hapticFeedbackEnabled = true
        requestTimeout = 30.0
        
        // Reinitialize with default data
        setupDefaultData()
        
        // Trigger strong haptic feedback for major action
        triggerHapticFeedback(.heavy)
    }
}

// MARK: - Notification Settings Manager
@MainActor
class NotificationManager: ObservableObject {
    @Published var notificationsEnabled = false
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    init() {
        checkNotificationStatus()
    }
    
    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationStatus = settings.authorizationStatus
                self.notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await MainActor.run {
                self.notificationsEnabled = granted
                if granted {
                    self.notificationStatus = .authorized
                }
            }
            return granted
        } catch {
            print("Error requesting notification permissions: \(error)")
            return false
        }
    }
    
    func openNotificationSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ContentView: View {
    @StateObject private var httpClientViewModel = HTTPClientViewModel()
    @Environment(\.colorScheme) private var colorScheme

    // Custom colors for the app
    var accentColor: Color {
        .blue
    }
    
    var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground)
    }

    var body: some View {
        TabView {
            HomeView(
                accentColor: accentColor, 
                backgroundColor: backgroundColor,
                httpClientViewModel: httpClientViewModel
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            HTTPClientView(
                httpClientViewModel: httpClientViewModel,
                accentColor: accentColor,
                backgroundColor: backgroundColor
            )
            .tabItem {
                Label("Client", systemImage: "network")
            }

            CollectionsView(
                httpClientViewModel: httpClientViewModel,
                accentColor: accentColor,
                backgroundColor: backgroundColor
            )
            .tabItem {
                Label("Collections", systemImage: "folder.fill")
            }

            MonitorsView(
                httpClientViewModel: httpClientViewModel,
                accentColor: accentColor,
                backgroundColor: backgroundColor
            )
            .tabItem {
                Label("Monitors", systemImage: "wave.3.right")
            }

            InfoView(
                accentColor: accentColor, 
                backgroundColor: backgroundColor,
                httpClientViewModel: httpClientViewModel
            )
            .tabItem {
                Label("Info", systemImage: "info.circle.fill")
            }
        }
        .accentColor(Color.blue)
        .onAppear {
            // Set tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
            
            // Set tab bar item colors
            let itemAppearance = UITabBarItemAppearance()
            itemAppearance.normal.iconColor = UIColor.systemGray
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemGray]
            itemAppearance.selected.iconColor = UIColor.systemBlue
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
            
            appearance.stackedLayoutAppearance = itemAppearance
            appearance.inlineLayoutAppearance = itemAppearance
            appearance.compactInlineLayoutAppearance = itemAppearance
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// Extension to create Color from hex string
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        
        let r = Double((rgbValue & 0xff0000) >> 16) / 255.0
        let g = Double((rgbValue & 0xff00) >> 8) / 255.0
        let b = Double(rgbValue & 0xff) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

struct HomeView: View {
    var accentColor: Color
    var backgroundColor: Color
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingQuickRequest = false
    @State private var showingImportOptions = false
    @State private var animateStats = false
    
    var recentRequests: [HTTPRequest] {
        Array(httpClientViewModel.requestHistory.prefix(4))
    }
    
    var favoriteCollections: [Collection] {
        Array(httpClientViewModel.collections.prefix(3))
    }
    
    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 28) {
                    // Welcome Header with better styling
                    modernWelcomeHeader
                    
                    // Action Cards Section
                    modernQuickActionsSection
                    
                    // Live Stats Dashboard
                    modernStatsDashboard
                    
                    // Recent Activity with better design
                    if !recentRequests.isEmpty {
                        modernRecentActivitySection
                    }
                    
                    // Collections with enhanced UI
                    if !favoriteCollections.isEmpty {
                        modernCollectionsSection
                    }
                    
                    // Monitors with real-time status
                    modernMonitorsSection
                    
                    // Pro Tips with modern design
                    modernTipsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Home")
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                animateStats = true
            }
        }
        .sheet(isPresented: $showingQuickRequest) {
            ModernQuickRequestSheet(httpClientViewModel: httpClientViewModel)
        }
        .sheet(isPresented: $showingImportOptions) {
            ImportOptionsSheet()
        }
    }
}

extension HomeView {
    private var modernWelcomeHeader: some View {
        VStack(spacing: 20) {
            // App branding with modern design
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("👋")
                            .font(.title)
                        Text("Welcome back!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                    
                    Text("Let's build something amazing today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                // Modern app icon with glow effect
                ZStack {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 60, height: 60)
                        .shadow(color: Color.blue.opacity(0.4), radius: 15, x: 0, y: 8)
                    
                    Image(systemName: "network")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                .scaleEffect(animateStats ? 1.0 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: animateStats)
            }
            .padding(.top, 10)
        }
    }
    
    private var modernQuickActionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick Actions")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ModernActionCard(
                    icon: "plus.circle.fill",
                    title: "New Request",
                    subtitle: "Start building",
                    color: .blue,
                    action: { showingQuickRequest = true }
                )
                
                ModernActionCard(
                    icon: "clock.arrow.circlepath",
                    title: "Recent",
                    subtitle: recentRequests.isEmpty ? "No history" : "\(recentRequests.count) items",
                    color: .green,
                    action: { /* Navigate to history */ }
                )
                
                ModernActionCard(
                    icon: "folder.badge.plus",
                    title: "Collection",
                    subtitle: "Organize work",
                    color: .purple,
                    action: { /* Navigate to collections */ }
                )
                
                ModernActionCard(
                    icon: "square.and.arrow.down",
                    title: "Import",
                    subtitle: "From file",
                    color: .orange,
                    action: { showingImportOptions = true }
                )
            }
        }
    }
    
    private var modernStatsDashboard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Overview")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            HStack(spacing: 16) {
                ModernStatCard(
                    value: "\(httpClientViewModel.requestHistory.count)",
                    label: "Requests",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue,
                    animate: animateStats
                )
                
                ModernStatCard(
                    value: "\(httpClientViewModel.collections.count)",
                    label: "Collections",
                    icon: "folder.fill",
                    color: .purple,
                    animate: animateStats
                )
                
                ModernStatCard(
                    value: "\(httpClientViewModel.monitors.filter { $0.status == .online }.count)",
                    label: "Online",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    animate: animateStats
                )
            }
        }
    }
    
    private var modernRecentActivitySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Recent Activity")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                ModernButton(
                    title: "View All",
                    style: .secondary,
                    size: .small,
                    action: { /* Navigate to history */ }
                )
            }
            
            VStack(spacing: 12) {
                ForEach(recentRequests) { request in
                    ModernRequestRow(request: request)
                }
            }
        }
    }
    
    private var modernCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Collections")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                ModernButton(
                    title: "Manage",
                    style: .secondary,
                    size: .small,
                    action: { /* Navigate to collections */ }
                )
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(favoriteCollections) { collection in
                        ModernCollectionCard(collection: collection)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
    
    private var modernMonitorsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Service Health")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                ModernButton(
                    title: "Monitor",
                    style: .secondary,
                    size: .small,
                    action: { /* Navigate to monitors */ }
                )
            }
            
            if httpClientViewModel.getAllMonitors().isEmpty {
                ModernEmptyState(
                    icon: "eye.slash",
                    title: "No Monitors",
                    subtitle: "Add monitors to track your services",
                    buttonTitle: "Add Monitor",
                    action: { /* Navigate to add monitor */ }
                )
            } else {
                VStack(spacing: 16) {
                    // Monitor status grid
                    HStack(spacing: 12) {
                        let allMonitors = httpClientViewModel.getAllMonitors()
                        let onlineCount = allMonitors.filter { $0.status == .online }.count
                        let offlineCount = allMonitors.filter { $0.status == .offline }.count
                        let totalCount = allMonitors.count
                        let uptimePercentage = totalCount > 0 ? Int((Double(onlineCount) / Double(totalCount)) * 100) : 0
                        
                        ModernMetricCard(
                            value: "\(onlineCount)",
                            total: totalCount,
                            label: "Online",
                            color: .green,
                            icon: "checkmark.circle.fill"
                        )
                        
                        ModernMetricCard(
                            value: "\(offlineCount)",
                            total: totalCount,
                            label: "Issues",
                            color: .red,
                            icon: "exclamationmark.triangle.fill"
                        )
                        
                        ModernMetricCard(
                            value: "\(uptimePercentage)",
                            total: 100,
                            label: "Uptime",
                            color: .blue,
                            icon: "clock.fill",
                            suffix: "%"
                        )
                    }
                }
            }
        }
    }
    
    private var modernTipsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pro Tips")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            VStack(spacing: 12) {
                ModernTipCard(
                    icon: "folder.badge.plus",
                    tip: "Organize related requests into collections for better management",
                    color: .purple
                )
                
                ModernTipCard(
                    icon: "doc.on.doc",
                    tip: "Use saved requests as templates by tapping the copy button in collections",
                    color: .blue
                )
            }
        }
    }
}

// MARK: - Modern UI Components

struct ModernActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Icon with solid color background
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color)
                        .frame(width: 50, height: 50)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: isPressed ? 8 : 15, x: 0, y: isPressed ? 2 : 8)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = false
                }
                action()
            }
        }
    }
}

struct ModernStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    let animate: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedValue = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon with color background
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            
            VStack(spacing: 4) {
                Text(animate ? value : "0")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        )
        .onChange(of: animate) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 0.8)) {
                    animatedValue = Int(value) ?? 0
                }
            }
        }
    }
}

struct ModernButton: View {
    let title: String
    let style: ButtonStyle
    let size: ButtonSize
    let action: () -> Void
    
    enum ButtonStyle {
        case primary, secondary, accent
    }
    
    enum ButtonSize {
        case small, medium, large
    }
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    private var backgroundColor: Color {
        switch style {
        case .primary:
            return .blue
        case .secondary:
            return colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6)
        case .accent:
            return .purple
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary, .accent:
            return .white
        case .secondary:
            return .primary
        }
    }
    
    private var padding: (horizontal: CGFloat, vertical: CGFloat) {
        switch size {
        case .small:
            return (12, 8)
        case .medium:
            return (16, 12)
        case .large:
            return (24, 16)
        }
    }
    
    private var fontSize: Font {
        switch size {
        case .small:
            return .caption
        case .medium:
            return .subheadline
        case .large:
            return .headline
        }
    }
    
    var body: some View {
        Button(action: {
            // Trigger enhanced haptic feedback based on button style
            switch style {
            case .primary, .accent:
                let notificationGenerator = UINotificationFeedbackGenerator()
                notificationGenerator.prepare()
                notificationGenerator.notificationOccurred(.success)
            case .secondary:
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.prepare()
                impactFeedback.impactOccurred()
            }
            action()
        }) {
            Text(title)
                .font(fontSize)
                .fontWeight(.semibold)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, padding.horizontal)
                .padding(.vertical, padding.vertical)
                .background(
                    Capsule()
                        .fill(backgroundColor)
                        .shadow(color: .black.opacity(0.1), radius: isPressed ? 2 : 6, x: 0, y: isPressed ? 1 : 3)
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = false
            }
        }
    }
}

struct ModernRequestRow: View {
    let request: HTTPRequest
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Method badge with modern pill design
            Text(request.method)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(methodColor(for: request.method))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if !request.url.isEmpty {
                    Text(request.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: {
                // Run request again
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
        )
    }
}

struct ModernCollectionCard: View {
    let collection: Collection
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Circle()
                    .fill(Color(collection.color))
                    .frame(width: 12, height: 12)
                
                Text(collection.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                Spacer()
            }
            
            // Stats
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "doc.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(collection.requests.count) requests")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                if !collection.monitors.isEmpty {
                    HStack {
                        Image(systemName: "wave.3.right")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(collection.monitors.count) monitors")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            
            // Method badges
            if !collection.requests.isEmpty {
                HStack(spacing: 4) {
                    let methods = Array(Set(collection.requests.map { $0.method })).prefix(4)
                    ForEach(Array(methods), id: \.self) { method in
                        Text(method)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(methodColor(for: method))
                            )
                    }
                    if methods.count < collection.requests.count {
                        Text("+\(collection.requests.count - methods.count)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Add requests")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 4)
        )
    }
}

struct ModernEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            ModernButton(
                title: buttonTitle,
                style: .primary,
                size: .medium,
                action: action
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 12, x: 0, y: 6)
        )
    }
}

struct ModernMetricCard: View {
    let value: String
    let total: Int
    let label: String
    let color: Color
    let icon: String
    let suffix: String
    
    init(value: String, total: Int, label: String, color: Color, icon: String, suffix: String = "") {
        self.value = value
        self.total = total
        self.label = label
        self.color = color
        self.icon = icon
        self.suffix = suffix
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            
            VStack(spacing: 4) {
                Text(value + suffix)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
        )
    }
}

struct ModernTipCard: View {
    let icon: String
    let tip: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
            }
            
            Text(tip)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Button Press Events Extension
extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEvents(onPress: onPress, onRelease: onRelease))
    }
}

struct PressEvents: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0)
            .onTapGesture {
                onPress()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onRelease()
                }
            }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                }
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RecentRequestRow: View {
    let request: HTTPRequest
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Method badge
            Text(request.method)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(methodColor(for: request.method))
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !request.url.isEmpty {
                    Text(request.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: {
                // Run request again
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
        )
    }
}

struct CollectionOverviewCard: View {
    let collection: Collection
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(collection.color))
                    .frame(width: 8, height: 8)
                
                Text(collection.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Text("\(collection.requests.count) requests")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Method preview
            HStack(spacing: 4) {
                let methods = Array(Set(collection.requests.map { $0.method })).prefix(3)
                ForEach(Array(methods), id: \.self) { method in
                    Text(method)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(3)
                }
                if methods.count < collection.requests.count {
                    Text("+\(collection.requests.count - methods.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: 120)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }
}

struct TipCard: View {
    let icon: String
    let tip: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            
            Text(tip)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct ModernQuickRequestSheet: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var method = "GET"
    @State private var isLoading = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    // Header with icon
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.blue)
                                .frame(width: 80, height: 80)
                                .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                            
                            Image(systemName: "paperplane.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Quick Request")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            Text("Send a quick HTTP request")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                        }
                    }
                    
                    VStack(spacing: 24) {
                        // Method selector with modern pills
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Method")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(["GET", "POST", "PUT", "DELETE", "PATCH"], id: \.self) { methodOption in
                                        Button(action: { method = methodOption }) {
                                            Text(methodOption)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(method == methodOption ? .white : .primary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 10)
                                                .background(
                                                    Capsule()
                                                        .fill(method == methodOption ? 
                                                              .blue :
                                                              Color(UIColor.systemGray6))
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 1)
                            }
                        }
                        
                        // URL input with modern styling
                        VStack(alignment: .leading, spacing: 12) {
                            Text("URL")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            TextField("Enter URL (e.g., https://api.example.com)", text: $url)
                                .font(.system(.body, design: .monospaced))
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                                )
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        // Send button with loading state
                        Button(action: sendQuickRequest) {
                            HStack(spacing: 12) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.headline)
                                }
                                
                                Text(isLoading ? "Sending..." : "Send Request")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(url.isEmpty ? 
                                          Color.gray :
                                          .blue)
                                    .shadow(color: url.isEmpty ? .clear : .blue.opacity(0.3), radius: 12, x: 0, y: 6)
                            )
                        }
                        .disabled(url.isEmpty || isLoading)
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Quick Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func sendQuickRequest() {
        isLoading = true
        
        // Create request
        var request = HTTPRequest()
        request.url = url
        request.method = method
        request.name = "Quick \(method) Request"
        
        // Simulate network request
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            httpClientViewModel.addToHistory(request)
            dismiss()
        }
    }
}

struct ImportOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.orange)
                                .frame(width: 80, height: 80)
                                .shadow(color: .orange.opacity(0.3), radius: 15, x: 0, y: 8)
                            
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Import Requests")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            
                            Text("Choose your import method")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                        }
                    }
                    
                    VStack(spacing: 16) {
                        ImportOptionCard(
                            icon: "doc.text.fill",
                            title: "Postman Collection",
                            subtitle: "Import from .json file",
                            color: .orange,
                            action: { /* Handle Postman import */ }
                        )
                        
                        ImportOptionCard(
                            icon: "terminal.fill",
                            title: "cURL Command",
                            subtitle: "Paste cURL command",
                            color: .green,
                            action: { /* Handle cURL import */ }
                        )
                        
                        ImportOptionCard(
                            icon: "link",
                            title: "OpenAPI/Swagger",
                            subtitle: "Import API specification",
                            color: .blue,
                            action: { /* Handle OpenAPI import */ }
                        )
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ImportOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QuickRequestSheet: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var method = "GET"
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Request")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Send a quick HTTP request without saving")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        Picker("Method", selection: $method) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                            Text("PUT").tag("PUT")
                            Text("DELETE").tag("DELETE")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                        
                        Spacer()
                    }
                    
                    TextField("Enter URL (e.g., https://api.example.com)", text: $url)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button(action: sendQuickRequest) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text("Send Request")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .disabled(url.isEmpty || isLoading)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Quick Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func sendQuickRequest() {
        isLoading = true
        
        // Simulate request (you can implement actual request logic here)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isLoading = false
            
            // Create and add to history
            var request = HTTPRequest()
            request.url = url
            request.method = method
            request.name = "Quick \(method) Request"
            
            httpClientViewModel.addToHistory(request)
            dismiss()
        }
    }
}
// MARK: - HTTP Client Views

struct HTTPClientView: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    var accentColor: Color
    var backgroundColor: Color
    
    @State private var currentRequest = HTTPRequest()
    @State private var selectedTab = 0
    @State private var selectedConfigTab = 0
    @State private var responseText = ""
    @State private var isOutputPopupVisible = false
    @State private var responseData: (data: Data?, response: URLResponse?, error: Error?)? = nil
    @State private var requestStartTime: Date?
    @State private var requestDuration: TimeInterval = 0
    @State private var isLoading = false
    @State private var showingSaveDialog = false
    @State private var showingRequestTemplates = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Modern Header
                    modernHeader
                    
                    // Request Builder Card
                    requestBuilderCard
                    
                    // Tabs Section
                    tabsSection
                    
                    // Send Button
                    sendButtonSection
                }
                .padding(.horizontal, 16)
                
                // Response Modal
                if isOutputPopupVisible {
                    ModernResponseView(
                        responseText: $responseText,
                        isVisible: $isOutputPopupVisible,
                        responseData: responseData,
                        requestDuration: requestDuration,
                        request: currentRequest
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(10)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingRequestTemplates) {
            RequestTemplatesSheet(
                onSelectTemplate: { template in
                    currentRequest = template
                    showingRequestTemplates = false
                }
            )
        }
        .sheet(isPresented: $showingSaveDialog) {
            SaveRequestSheet(
                request: currentRequest,
                collections: httpClientViewModel.collections,
                onSave: { collection in
                    httpClientViewModel.addRequest(currentRequest, to: collection)
                    showingSaveDialog = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LoadRequestTemplate"))) { notification in
            if let templateRequest = notification.object as? HTTPRequest {
                currentRequest = templateRequest
                selectedTab = 0 // Switch to first tab to show the loaded request
            }
        }
    }
    
    private var modernHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("HTTP Client")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Build and test API requests")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: { showingRequestTemplates = true }) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                
                Button(action: { showingSaveDialog = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 36, height: 36)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Circle())
                }
                .disabled(currentRequest.url.isEmpty)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
    
    private var requestBuilderCard: some View {
        VStack(spacing: 16) {
            // URL Input Section
            VStack(spacing: 12) {
                HStack {
                    Text("Request URL")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Template Picker
                    let allRequests = httpClientViewModel.collections.flatMap { $0.requests }
                    if !allRequests.isEmpty {
                        Menu {
                            ForEach(httpClientViewModel.collections) { collection in
                                if !collection.requests.isEmpty {
                                    Section(collection.name) {
                                        ForEach(collection.requests) { request in
                                            Button(request.name) {
                                                httpClientViewModel.loadRequestAsTemplate(request) { templateRequest in
                                                    currentRequest = templateRequest
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                                Text("Use Template")
                                    .font(.caption)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(12)
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    // Method Picker
                    Menu {
                        ForEach(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"], id: \.self) { method in
                            Button(method) {
                                currentRequest.method = method
                            }
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(methodColor(currentRequest.method))
                                .frame(width: 8, height: 8)
                            Text(currentRequest.method)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(methodColor(currentRequest.method).opacity(0.4), lineWidth: 2)
                                )
                        )
                    }
                    .frame(width: 100)
                    
                    // URL Input
                    TextField(
                        "https://api.example.com/endpoint",
                        text: $currentRequest.url
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))
                }
                
                // Request Name
                TextField("Request Name (optional)", text: $currentRequest.name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
    }
    
    private var tabsSection: some View {
        VStack(spacing: 0) {
            // Modern Tab Headers with pill design
            HStack(spacing: 8) {
                TabButton(
                    title: "Headers",
                    icon: "list.bullet",
                    index: 0,
                    selectedIndex: selectedTab,
                    action: { selectedTab = 0 }
                )
                
                TabButton(
                    title: "Body",
                    icon: "doc.text",
                    index: 1,
                    selectedIndex: selectedTab,
                    action: { selectedTab = 1 }
                )
                
                TabButton(
                    title: "Auth",
                    icon: "key",
                    index: 2,
                    selectedIndex: selectedTab,
                    action: { selectedTab = 2 }
                )
                
                TabButton(
                    title: "History",
                    icon: "clock.arrow.circlepath",
                    index: 3,
                    selectedIndex: selectedTab,
                    action: { selectedTab = 3 }
                )
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            
            // Tab Content
            Group {
                switch selectedTab {
                case 0:
                    ModernHeadersView(request: $currentRequest)
                case 1:
                    ModernBodyView(request: $currentRequest)
                case 2:
                    ModernAuthView(request: $currentRequest)
                case 3:
                    ModernHistoryView(
                        httpClientViewModel: httpClientViewModel,
                        onLoadRequest: { request in
                            currentRequest = request
                            selectedTab = 0
                        }
                    )
                default:
                    EmptyView()
                }
            }
            .frame(height: 300)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
            )
        }
        .padding(.top, 16)
    }
    
    private var sendButtonSection: some View {
        Button(action: {
            httpClientViewModel.triggerHapticFeedback(.medium)
            sendRequest()
        }) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .bold))
                }
                
                Text(isLoading ? "Sending..." : "Send Request")
                    .fontWeight(.semibold)
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        currentRequest.url.isEmpty || !isValidURL(currentRequest.url) ?
                        Color.gray :
                        accentColor
                    )
            )
            .disabled(currentRequest.url.isEmpty || !isValidURL(currentRequest.url) || isLoading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
    
    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme != nil && url.host != nil
    }
    
    private func sendRequest() {
        isLoading = true
        
        let urlString = currentRequest.url.isEmpty ? "https://api.example.com" : currentRequest.url
        
        guard let url = URL(string: urlString) else {
            responseText = "Invalid URL"
            isOutputPopupVisible = true
            isLoading = false
            return
        }
        
        requestStartTime = Date()
        var request = URLRequest(url: url)
        request.httpMethod = currentRequest.method
        request.timeoutInterval = httpClientViewModel.requestTimeout
        
        // Add request headers
        for header in currentRequest.headers {
            if !header.key.isEmpty && !header.value.isEmpty {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }
        }
        
        // Add body for applicable methods
        if ["POST", "PUT", "PATCH"].contains(currentRequest.method) && !currentRequest.body.isEmpty {
            request.httpBody = currentRequest.body.data(using: .utf8)
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let startTime = requestStartTime {
                    requestDuration = Date().timeIntervalSince(startTime)
                }
                
                responseData = (data: data, response: response, error: error)
                
                if let error = error {
                    responseText = "Error: \(error.localizedDescription)"
                    httpClientViewModel.triggerErrorHaptic()
                } else if let httpResponse = response as? HTTPURLResponse {
                    var responseString = "Status: \(httpResponse.statusCode) - \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\n"
                    responseString += "Duration: \(String(format: "%.2f", requestDuration))s\n\n"
                    
                    responseString += "Headers:\n"
                    for (key, value) in httpResponse.allHeaderFields {
                        responseString += "\(key): \(value)\n"
                    }
                    responseString += "\n"
                    
                    if let data = data, let dataString = String(data: data, encoding: .utf8) {
                        responseString += "Body:\n\(formatResponse(dataString))"
                    } else {
                        responseString += "No response body"
                    }
                    responseText = responseString
                    
                    // Trigger haptic feedback based on status code
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        httpClientViewModel.triggerSuccessHaptic()
                    } else if httpResponse.statusCode >= 400 {
                        httpClientViewModel.triggerErrorHaptic()
                    } else {
                        httpClientViewModel.triggerWarningHaptic()
                    }
                }
                
                // Add to history
                httpClientViewModel.addToHistory(currentRequest)
                
                isOutputPopupVisible = true
            }
        }
        
        task.resume()
    }
    
    private func formatResponse(_ text: String) -> String {
        if text.hasPrefix("{") || text.hasPrefix("[") {
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                return prettyString
            }
        }
        return text
    }
}

// MARK: - Optimized Tab Button Component
struct TabButton: View {
    let title: String
    let icon: String
    let index: Int
    let selectedIndex: Int
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isSelected: Bool {
        index == selectedIndex
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Modern HTTP Client Components

struct ModernHeadersView: View {
    @Binding var request: HTTPRequest
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Quick Actions
                HStack {
                    Text("Headers")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: { request.headers.append(HTTPHeader()) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                }
                
                // Headers List
                if request.headers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        
                        Text("No headers added")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Add headers to customize your request")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach($request.headers) { $header in
                        ModernHeaderRow(header: $header, onDelete: {
                            request.headers.removeAll { $0.id == header.id }
                        })
                    }
                }
            }
            .padding()
        }
    }
}

struct ModernHeaderRow: View {
    @Binding var header: HTTPHeader
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Header name", text: $header.key)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                    )
                
                Button(action: {
                    let notificationGenerator = UINotificationFeedbackGenerator()
                    notificationGenerator.prepare()
                    notificationGenerator.notificationOccurred(.error)
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            TextField("Header value", text: $header.value)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                )
        }
    }
}

struct ModernBodyView: View {
    @Binding var request: HTTPRequest
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedFormat = "JSON"
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Request Body")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Menu {
                    Button("JSON") { selectedFormat = "JSON"; formatJSON() }
                    Button("XML") { selectedFormat = "XML" }
                    Button("Plain Text") { selectedFormat = "Text" }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedFormat)
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Body Editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $request.body)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                    )
                    .padding(.horizontal)
                
                if request.body.isEmpty {
                    Text("Enter request body here...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }
    
    private func formatJSON() {
        if !request.body.isEmpty {
            if let data = request.body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                request.body = prettyString
            }
        }
    }
}

struct ModernAuthView: View {
    @Binding var request: HTTPRequest
    @State private var authType = "none"
    @State private var bearerToken = ""
    @State private var basicUsername = ""
    @State private var basicPassword = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Text("Authentication")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Auth Type Picker
                Picker("Auth Type", selection: $authType) {
                    Text("No Auth").tag("none")
                    Text("Bearer Token").tag("bearer")
                    Text("Basic Auth").tag("basic")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Auth Configuration
                Group {
                    switch authType {
                    case "bearer":
                        bearerTokenSection
                    case "basic":
                        basicAuthSection
                    default:
                        noAuthSection
                    }
                }
                
                Spacer()
            }
        }
        .onChange(of: authType) { _, _ in updateAuthHeaders() }
        .onChange(of: bearerToken) { _, _ in updateAuthHeaders() }
        .onChange(of: basicUsername) { _, _ in updateAuthHeaders() }
        .onChange(of: basicPassword) { _, _ in updateAuthHeaders() }
    }
    
    private var noAuthSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.open")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No authentication required")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }
    
    private var bearerTokenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bearer Token")
                .font(.subheadline)
                .fontWeight(.medium)
            
            SecureField("Enter your bearer token", text: $bearerToken)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal)
    }
    
    private var basicAuthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Authentication")
                .font(.subheadline)
                .fontWeight(.medium)
            
            TextField("Username", text: $basicUsername)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            SecureField("Password", text: $basicPassword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding(.horizontal)
    }
    
    private func updateAuthHeaders() {
        request.headers.removeAll { $0.key.lowercased() == "authorization" }
        
        switch authType {
        case "bearer":
            if !bearerToken.isEmpty {
                request.headers.append(HTTPHeader(key: "Authorization", value: "Bearer \(bearerToken)"))
            }
        case "basic":
            if !basicUsername.isEmpty || !basicPassword.isEmpty {
                let credentials = "\(basicUsername):\(basicPassword)"
                if let data = credentials.data(using: .utf8) {
                    let base64 = data.base64EncodedString()
                    request.headers.append(HTTPHeader(key: "Authorization", value: "Basic \(base64)"))
                }
            }
        default:
            break
        }
    }
}

struct ModernHistoryView: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    let onLoadRequest: (HTTPRequest) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    
    var filteredHistory: [HTTPRequest] {
        if searchText.isEmpty {
            return httpClientViewModel.requestHistory
        } else {
            return httpClientViewModel.requestHistory.filter { request in
                request.name.localizedCaseInsensitiveContains(searchText) ||
                request.url.localizedCaseInsensitiveContains(searchText) ||
                request.method.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
            )
            .padding(.horizontal)
            .padding(.top)
            
            // History List
            ScrollView {
                if filteredHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        
                        Text(searchText.isEmpty ? "No Request History" : "No Results Found")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(searchText.isEmpty ? 
                             "Your request history will appear here" :
                             "Try searching for a different term")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredHistory) { request in
                            ModernHistoryRow(
                                request: request,
                                onLoad: { onLoadRequest(request) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct ModernHistoryRow: View {
    let request: HTTPRequest
    let onLoad: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Method Badge
            Text(request.method)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(methodColor(for: request.method))
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !request.url.isEmpty {
                    Text(request.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: onLoad) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
        )
    }
}

struct ModernResponseView: View {
    @Binding var responseText: String
    @Binding var isVisible: Bool
    let responseData: (data: Data?, response: URLResponse?, error: Error?)?
    let requestDuration: TimeInterval
    let request: HTTPRequest
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible = false
                    }
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Response")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            if let httpResponse = responseData?.response as? HTTPURLResponse {
                                HStack(spacing: 8) {
                                    StatusBadge(statusCode: httpResponse.statusCode)
                                    Text("\(String(format: "%.2f", requestDuration))s")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isVisible = false
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    // Content
                    ScrollView {
                        Text(responseText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(maxHeight: 400)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                )
                .padding()
            }
        }
    }
}

struct StatusBadge: View {
    let statusCode: Int
    
    var statusColor: Color {
        switch statusCode {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<500: return .red
        case 500...: return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        Text("\(statusCode)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor)
            .cornerRadius(6)
    }
}

extension HTTPClientView {
    private var requestBuilderSection: some View {
        VStack(spacing: 16) {
            // Request Name Section
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Untitled Request", text: $currentRequest.name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                Spacer()
            }
            
            // Method & URL Builder
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Method Selector with Visual Indicators
                    Picker("Method", selection: $currentRequest.method) {
                        HStack {
                            Circle().fill(Color.blue).frame(width: 8, height: 8)
                            Text("GET")
                        }.tag("GET")
                        HStack {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("POST")
                        }.tag("POST")
                        HStack {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text("PUT")
                        }.tag("PUT")
                        HStack {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("DELETE")
                        }.tag("DELETE")
                        HStack {
                            Circle().fill(Color.purple).frame(width: 8, height: 8)
                            Text("PATCH")
                        }.tag("PATCH")
                        Text("HEAD").tag("HEAD")
                        Text("OPTIONS").tag("OPTIONS")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 90)
                    
                    // Smart URL Field with Validation
                    ZStack(alignment: .trailing) {
                        TextField(
                            "https://api.example.com/endpoint",
                            text: $currentRequest.url
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        
                        // URL Validation Indicator
                        if !currentRequest.url.isEmpty {
                            Image(systemName: isValidURL(currentRequest.url) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isValidURL(currentRequest.url) ? .green : .red)
                                .padding(.trailing, 8)
                        }
                    }
                }
                
                // Send Button with Loading State
                Button(action: sendRequest) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(isLoading ? "Sending..." : "Send Request")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        currentRequest.url.isEmpty || !isValidURL(currentRequest.url) ? 
                        Color.gray : accentColor
                    )
                    .cornerRadius(10)
                }
                .disabled(currentRequest.url.isEmpty || !isValidURL(currentRequest.url) || isLoading)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
        .padding(.top)
    }
    
    private var configurationSection: some View {
        let titles = ["Headers", "Body", "Auth", "History"]
        let icons = ["list.bullet", "doc.text", "key", "clock.arrow.circlepath"]
        
        return VStack(spacing: 0) {
            // Enhanced Tab Picker
            HStack {
                ForEach(0..<4) { index in
                    Button(action: { selectedConfigTab = index }) {
                        VStack(spacing: 4) {
                            Image(systemName: icons[index])
                                .font(.caption)
                            Text(titles[index])
                                .font(.caption2)
                        }
                        .foregroundColor(selectedConfigTab == index ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedConfigTab == index ? 
                            Color.blue.opacity(0.1) : Color.clear
                        )
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
            )
            .padding(.horizontal)
            .padding(.top)
            
            // Tab Content
            TabView(selection: $selectedConfigTab) {
                EnhancedHeadersView(request: $currentRequest)
                    .tag(0)
                
                EnhancedBodyView(request: $currentRequest, colorScheme: colorScheme)
                    .tag(1)
                
                AuthenticationView(request: $currentRequest)
                    .tag(2)
                
                EnhancedHistoryView(
                    httpClientViewModel: httpClientViewModel,
                    onLoadRequest: { request in
                        currentRequest = request
                        selectedConfigTab = 0
                    },
                    accentColor: accentColor
                )
                .tag(3)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
    }
    
    private var quickActionsBar: some View {
        HStack {
            Button(action: duplicateRequest) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Duplicate")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button(action: clearRequest) {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(8)
            }
            
            Spacer()
            
            Button(action: exportToCurl) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export cURL")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: -1)
        )
    }
    
    private func duplicateRequest() {
        var newRequest = currentRequest
        newRequest.id = UUID()
        newRequest.name = "\(currentRequest.name) (Copy)"
        currentRequest = newRequest
    }
    
    private func clearRequest() {
        currentRequest = HTTPRequest()
    }
    
    private func clearAll() {
        currentRequest = HTTPRequest()
        selectedConfigTab = 0
    }
    
    private func exportToCurl() {
        let curl = generateCurlCommand(from: currentRequest)
        UIPasteboard.general.string = curl
        
        // Show feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func generateCurlCommand(from request: HTTPRequest) -> String {
        var curl = "curl -X \(request.method)"
        
        // Add headers
        for header in request.headers where !header.key.isEmpty && !header.value.isEmpty {
            curl += " -H '\(header.key): \(header.value)'"
        }
        
        // Add body
        if !request.body.isEmpty {
            curl += " -d '\(request.body)'"
        }
        
        // Add URL        
        curl += " '\(request.url)'"
        return curl
    }
}

struct CollectionsView: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    var accentColor: Color
    var backgroundColor: Color
    
    @State private var showingAddCollection = false
    @State private var newCollectionName = ""
    @State private var selectedCollection: Collection?
    @State private var showingCollectionDetail = false
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme
    
    var filteredCollections: [Collection] {
        if searchText.isEmpty {
            return httpClientViewModel.collections
        } else {
            return httpClientViewModel.collections.filter { collection in
                collection.name.localizedCaseInsensitiveContains(searchText) ||
                collection.requests.contains { request in
                    request.name.localizedCaseInsensitiveContains(searchText) ||
                    request.url.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    modernHeader
                    
                    // Search Bar
                    searchBar
                    
                    // Content
                    collectionsContent
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarHidden(true)
        .alert("New Collection", isPresented: $showingAddCollection) {
            TextField("Collection Name", text: $newCollectionName)
            Button("Create") {
                if !newCollectionName.isEmpty {
                    let newCollection = Collection(name: newCollectionName)
                    httpClientViewModel.addCollection(newCollection)
                    newCollectionName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
        }
        .sheet(isPresented: $showingCollectionDetail) {
            if let collection = selectedCollection {
                ModernCollectionDetailView(
                    collection: collection,
                    httpClientViewModel: httpClientViewModel
                )
            }
        }
    }
    
    private var modernHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Collections")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Organize your API requests")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                httpClientViewModel.triggerHapticFeedback(.light)
                showingAddCollection = true
            }) {
                Image(systemName: "plus")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .shadow(color: Color.blue.opacity(0.2), radius: 4, x: 0, y: 2)
                    )
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search collections...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
        .padding(.bottom, 16)
    }
    
    private var collectionsContent: some View {
        Group {
            if filteredCollections.isEmpty {
                emptyCollectionsView
            } else {
                collectionsGrid
            }
        }
    }
    
    private var emptyCollectionsView: some View {
        VStack(spacing: 24) {
            Image(systemName: searchText.isEmpty ? "folder.badge.plus" : "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No Collections Yet" : "No Results Found")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(searchText.isEmpty ? 
                     "Create your first collection to organize API requests and monitors." :
                     "Try searching for a different term.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            if searchText.isEmpty {
                Button(action: { 
                    httpClientViewModel.triggerHapticFeedback(.medium)
                    showingAddCollection = true 
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Create Collection")
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accentColor)
                            .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var collectionsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(filteredCollections) { collection in
                    Button(action: {
                        selectedCollection = collection
                        showingCollectionDetail = true
                    }) {
                        ModernCollectionCard(collection: collection)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Add Collection Card
                Button(action: {
                    httpClientViewModel.triggerHapticFeedback(.medium)
                    showingAddCollection = true
                }) {
                    VStack(spacing: 16) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                        
                        Text("New Collection")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.05))
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 100)
        }
    }
}

struct MonitorCollectionSection: View {
    let collection: Collection
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color(collection.color))
                    .frame(width: 8, height: 8)
                
                Text(collection.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(collection.monitors.count) monitors")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            ForEach(collection.monitors) { monitor in
                MonitorCard(monitor: monitor, collection: collection, httpClientViewModel: httpClientViewModel)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
        )
    }
}

struct MonitorCard: View {
    let monitor: PingMonitor
    let collection: Collection
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isToggling = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            HStack(spacing: 6) {
                Image(systemName: monitor.lastStatus.icon)
                    .font(.caption)
                    .foregroundColor(monitor.lastStatus.color)
                
                Circle()
                    .fill(monitor.lastStatus.color)
                    .frame(width: 8, height: 8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(monitor.host)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let port = monitor.port {
                        Text(":\(port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let lastChecked = monitor.lastChecked {
                    Text("Last checked: \(formatDate(lastChecked))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let responseTime = monitor.responseTime {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(responseTime))ms")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(responseTimeColor(responseTime))
                    
                    Text("ping")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Toggle Switch
            Toggle("", isOn: Binding(
                get: { monitor.isEnabled },
                set: { newValue in
                    toggleMonitor(newValue)
                }
            ))
            .scaleEffect(0.8)
            .disabled(isToggling)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func responseTimeColor(_ time: Double) -> Color {
        switch time {
        case 0..<100: return .green
        case 100..<500: return .orange
        default: return .red
        }
    }
    
    private func toggleMonitor(_ isEnabled: Bool) {
        isToggling = true
        
        // Update the monitor in the collection
        if let collectionIndex = httpClientViewModel.collections.firstIndex(where: { $0.id == collection.id }),
           let monitorIndex = httpClientViewModel.collections[collectionIndex].monitors.firstIndex(where: { $0.id == monitor.id }) {
            httpClientViewModel.collections[collectionIndex].monitors[monitorIndex].isEnabled = isEnabled
            httpClientViewModel.saveCollections()
        }
        
        isToggling = false
    }
}

struct AddMonitorSheet: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Binding var isPresented: Bool
    
    @State private var monitorName = ""
    @State private var monitorHost = ""
    @State private var monitorPort = ""
    @State private var selectedCollectionId: UUID?
    @Environment(\.colorScheme) private var colorScheme
    
    var selectedCollection: Collection? {
        httpClientViewModel.collections.first { $0.id == selectedCollectionId }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add Monitor")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Monitor domains, IPs, or specific ports. Get notified when services go offline.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Form
                    VStack(spacing: 20) {
                        // Monitor Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Monitor Name")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            TextField("e.g., Main API Server", text: $monitorName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // Host/IP
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Host or IP Address")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            TextField("e.g., api.example.com or 192.168.1.1", text: $monitorHost)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        
                        // Port (Optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Port (Optional)")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            TextField("e.g., 80, 443, 3000", text: $monitorPort)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        
                        // Collection Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Collection")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            if httpClientViewModel.collections.isEmpty {
                                Text("No collections available. Create a collection first.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.orange.opacity(0.1))
                                    )
                            } else {
                                Menu {
                                    ForEach(httpClientViewModel.collections) { collection in
                                        Button(collection.name) {
                                            selectedCollectionId = collection.id
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedCollection?.name ?? "Select Collection")
                                            .foregroundColor(selectedCollection != nil ? .primary : .secondary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        
                        // Info Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("Monitoring Information")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                IconInfoRow(icon: "clock", text: "Checks every 15 minutes")
                                IconInfoRow(icon: "bell", text: "Push notifications when offline")
                                IconInfoRow(icon: "app.badge", text: "Works in background")
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.05))
                        )
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        httpClientViewModel.triggerWarningHaptic()
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        httpClientViewModel.triggerSuccessHaptic()
                        addMonitor()
                    }
                    .disabled(!canAddMonitor)
                }
            }
        }
    }
    
    private var canAddMonitor: Bool {
        !monitorName.isEmpty && !monitorHost.isEmpty && selectedCollectionId != nil
    }
    
    private func addMonitor() {
        guard let collectionId = selectedCollectionId,
              let collectionIndex = httpClientViewModel.collections.firstIndex(where: { $0.id == collectionId }) else {
            return
        }
        
        let port = Int(monitorPort.isEmpty ? "" : monitorPort)
        let monitor = PingMonitor(name: monitorName, host: monitorHost, port: port)
        
        httpClientViewModel.collections[collectionIndex].monitors.append(monitor)
        httpClientViewModel.saveCollections()
        
        isPresented = false
        
        // Request notification permissions
        requestNotificationPermissions()
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permissions granted")
            } else if let error = error {
                print("Notification permissions error: \(error)")
            }
        }
    }
}

struct IconInfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ModernCollectionDetailView: View {
    let collection: Collection
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0 // 0: Requests, 1: Monitors
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Circle()
                        .fill(Color(collection.color))
                        .frame(width: 16, height: 16)
                    
                    Text(collection.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                }
                .padding()
                
                // Tab Selector
                HStack(spacing: 0) {
                    ForEach(0..<2) { index in
                        let titles = ["Requests", "Monitors"]
                        let counts = [collection.requests.count, collection.monitors.count]
                        
                        Button(action: { selectedTab = index }) {
                            VStack(spacing: 4) {
                                Text(titles[index])
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("\(counts[index])")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(selectedTab == index ? .blue : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Rectangle()
                                    .fill(selectedTab == index ? Color.blue.opacity(0.1) : Color.clear)
                            )
                            .overlay(
                                Rectangle()
                                    .fill(selectedTab == index ? Color.blue : Color.clear)
                                    .frame(height: 2)
                                    .offset(y: 16)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                )
                .padding(.horizontal)
                
                // Content
                if selectedTab == 0 {
                    requestsContent
                } else {
                    monitorsContent
                }
                
                Spacer()
            }
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var requestsContent: some View {
        ScrollView {
            if collection.requests.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Text("No Requests")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Add requests to this collection from the HTTP Client")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(collection.requests) { request in
                        RequestRowView(
                            request: request, 
                            collection: collection,
                            httpClientViewModel: httpClientViewModel
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    private var monitorsContent: some View {
        ScrollView {
            if collection.monitors.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Text("No Monitors")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Add monitors to track service availability")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(collection.monitors) { monitor in
                        MonitorCard(monitor: monitor, collection: collection, httpClientViewModel: httpClientViewModel)
                    }
                }
                .padding()
            }
        }
    }
}

struct RequestRowView: View {
    let request: HTTPRequest
    let collection: Collection
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingRequestDetail = false
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        Button(action: {
            showingRequestDetail = true
        }) {
            HStack(spacing: 16) {
                // Method Badge
                VStack(spacing: 4) {
                    Text(request.method)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(methodColor(for: request.method))
                        .cornerRadius(6)
                    
                    if request.timeout != 30.0 {
                        Text("\(Int(request.timeout))s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(request.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if !request.url.isEmpty {
                        Text(request.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Show headers and body info
                    HStack(spacing: 12) {
                        if !request.headers.isEmpty {
                            Label("\(request.headers.count)", systemImage: "list.bullet")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if !request.body.isEmpty {
                            Label("Body", systemImage: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Button(action: {
                        httpClientViewModel.loadRequestAsTemplate(request) { templateRequest in
                            // Navigate to HTTP Client with template loaded
                            NotificationCenter.default.post(
                                name: Notification.Name("LoadRequestTemplate"),
                                object: templateRequest
                            )
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                httpClientViewModel.loadRequestAsTemplate(request) { templateRequest in
                    NotificationCenter.default.post(
                        name: Notification.Name("LoadRequestTemplate"),
                        object: templateRequest
                    )
                }
            }) {
                Label("Use as Template", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                httpClientViewModel.duplicateRequest(request, in: collection)
            }) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            
            Button(action: {
                if let collectionIndex = httpClientViewModel.collections.firstIndex(where: { $0.id == collection.id }),
                   let requestIndex = httpClientViewModel.collections[collectionIndex].requests.firstIndex(where: { $0.id == request.id }) {
                    httpClientViewModel.collections[collectionIndex].requests.remove(at: requestIndex)
                    httpClientViewModel.saveCollections()
                }
            }) {
                Label("Delete", systemImage: "trash")
            }
            .foregroundColor(.red)
        }
        .sheet(isPresented: $showingRequestDetail) {
            RequestDetailView(request: request, httpClientViewModel: httpClientViewModel)
        }
    }
}

struct RequestDetailView: View {
    let request: HTTPRequest
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Request Info
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(request.method)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(methodColor(for: request.method))
                                .cornerRadius(8)
                            
                            Text(request.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                        }
                        
                        if !request.url.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(request.url)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray6))
                                    )
                            }
                        }
                    }
                    
                    // Headers
                    if !request.headers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Headers (\(request.headers.count))")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            ForEach(request.headers) { header in
                                HStack {
                                    Text(header.key)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                    
                                    Text(":")
                                        .foregroundColor(.secondary)
                                    
                                    Text(header.value)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray6))
                                )
                            }
                        }
                    }
                    
                    // Body
                    if !request.body.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Request Body")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text(request.body)
                                .font(.system(.caption, design: .monospaced))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray6))
                                )
                        }
                    }
                    
                    // Settings
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Text("Timeout:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(request.timeout))s")
                                .fontWeight(.medium)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray6))
                        )
                        
                        HStack {
                            Text("Follow Redirects:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(request.followRedirects ? "Yes" : "No")
                                .fontWeight(.medium)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray6))
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Request Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Use as Template") {
                        httpClientViewModel.loadRequestAsTemplate(request) { templateRequest in
                            NotificationCenter.default.post(
                                name: Notification.Name("LoadRequestTemplate"),
                                object: templateRequest
                            )
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct MonitoringView: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @State private var showingAddMonitor = false
    @State private var newMonitorName = ""
    @State private var newMonitorHost = ""
    @State private var newMonitorPort = ""
    @State private var selectedCollection: Collection?
    @Environment(\.colorScheme) private var colorScheme
    
    var allMonitors: [PingMonitor] {
        httpClientViewModel.collections.flatMap { $0.monitors }
    }
    
    var body: some View {
        Group {
            if allMonitors.isEmpty {
                emptyMonitorsView
            } else {
                monitorsContent
            }
        }
        .sheet(isPresented: $showingAddMonitor) {
            AddMonitorSheet(
                httpClientViewModel: httpClientViewModel,
                isPresented: $showingAddMonitor
            )
        }
    }
    
    private var emptyMonitorsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Monitors Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Add domains, IPs, or specific ports to monitor.\nGet notified when services go offline.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Button(action: { showingAddMonitor = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Monitor")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.green)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var monitorsContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(httpClientViewModel.collections) { collection in
                    if !collection.monitors.isEmpty {
                        MonitorCollectionSection(
                            collection: collection,
                            httpClientViewModel: httpClientViewModel
                        )
                    }
                }
                
                // Add Monitor Button
                Button(action: { 
                    httpClientViewModel.triggerSuccessHaptic()
                    showingAddMonitor = true 
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        
                        Text("Add New Monitor")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 100)
        }
    }
}

struct MonitorsView: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    var accentColor: Color
    var backgroundColor: Color
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddMonitor = false
    @State private var searchText = ""
    
    var allMonitors: [PingMonitor] {
        httpClientViewModel.collections.flatMap { $0.monitors }
    }
    
    var filteredMonitors: [PingMonitor] {
        if searchText.isEmpty {
            return allMonitors
        } else {
            return allMonitors.filter { monitor in
                monitor.name.localizedCaseInsensitiveContains(searchText) ||
                monitor.host.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var onlineMonitors: [PingMonitor] {
        filteredMonitors.filter { $0.lastStatus == .online }
    }
    
    var offlineMonitors: [PingMonitor] {
        filteredMonitors.filter { $0.lastStatus == .offline }
    }
    
    var unknownMonitors: [PingMonitor] {
        filteredMonitors.filter { $0.lastStatus == .unknown }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    modernHeader
                    
                    // Search Bar
                    searchBar
                    
                    // Stats Overview
                    statsOverview
                    
                    // Content
                    if allMonitors.isEmpty {
                        emptyMonitorsView
                    } else {
                        monitorsContent
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingAddMonitor) {
            AddMonitorSheet(
                httpClientViewModel: httpClientViewModel,
                isPresented: $showingAddMonitor
            )
        }
    }
    
    private var modernHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monitors")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Track service availability")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { showingAddMonitor = true }) {
                Image(systemName: "plus")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .shadow(color: Color.blue.opacity(0.2), radius: 4, x: 0, y: 2)
                    )
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search monitors...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
        .padding(.bottom, 16)
    }
    
    private var statsOverview: some View {
        HStack(spacing: 12) {
            StatCard(
                value: "\(onlineMonitors.count)",
                label: "Online",
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            StatCard(
                value: "\(offlineMonitors.count)",
                label: "Offline",
                icon: "xmark.circle.fill",
                color: .red
            )
            
            StatCard(
                value: "\(unknownMonitors.count)",
                label: "Unknown",
                icon: "questionmark.circle.fill",
                color: .orange
            )
        }
        .padding(.bottom, 20)
    }
    
    private var emptyMonitorsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Monitors Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Add domains, IPs, or specific ports to monitor.\nGet notified when services go offline.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            Button(action: { showingAddMonitor = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Add Monitor")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(accentColor)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var monitorsContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if !onlineMonitors.isEmpty {
                    MonitorSection(
                        title: "Online",
                        monitors: onlineMonitors,
                        color: .green,
                        httpClientViewModel: httpClientViewModel
                    )
                }
                
                if !offlineMonitors.isEmpty {
                    MonitorSection(
                        title: "Offline",
                        monitors: offlineMonitors,
                        color: .red,
                        httpClientViewModel: httpClientViewModel
                    )
                }
                
                if !unknownMonitors.isEmpty {
                    MonitorSection(
                        title: "Unknown",
                        monitors: unknownMonitors,
                        color: .orange,
                        httpClientViewModel: httpClientViewModel
                    )
                }
                
                // Collection-based monitors (existing functionality)
                ForEach(httpClientViewModel.collections) { collection in
                    if !collection.monitors.isEmpty {
                        MonitorCollectionSection(
                            collection: collection,
                            httpClientViewModel: httpClientViewModel
                        )
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }
}

struct MonitorSection: View {
    let title: String
    let monitors: [PingMonitor]
    let color: Color
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(monitors.count) monitor\(monitors.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            ForEach(monitors) { monitor in
                if let collection = httpClientViewModel.collections.first(where: { $0.monitors.contains(where: { $0.id == monitor.id }) }) {
                    EnhancedMonitorCard(
                        monitor: monitor,
                        collection: collection,
                        httpClientViewModel: httpClientViewModel
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

struct EnhancedMonitorCard: View {
    let monitor: PingMonitor
    let collection: Collection
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isToggling = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator with Animation
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(monitor.lastStatus.color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: monitor.lastStatus.icon)
                        .font(.caption)
                        .foregroundColor(monitor.lastStatus.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(monitor.host)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let port = monitor.port {
                            Text(":\(port)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let responseTime = monitor.responseTime {
                    Text("\(Int(responseTime))ms")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(responseTimeColor(responseTime))
                    
                    Text("response")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let lastChecked = monitor.lastChecked {
                    Text(formatRelativeTime(lastChecked))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Toggle Switch
            Toggle("", isOn: Binding(
                get: { monitor.isEnabled },
                set: { newValue in
                    toggleMonitor(newValue)
                }
            ))
            .scaleEffect(0.8)
            .disabled(isToggling)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
        )
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
    
    private func responseTimeColor(_ time: Double) -> Color {
        switch time {
        case 0..<100: return .green
        case 100..<500: return .orange
        default: return .red
        }
    }
    
    private func toggleMonitor(_ isEnabled: Bool) {
        isToggling = true
        
        // Update the monitor in the collection
        if let collectionIndex = httpClientViewModel.collections.firstIndex(where: { $0.id == collection.id }),
           let monitorIndex = httpClientViewModel.collections[collectionIndex].monitors.firstIndex(where: { $0.id == monitor.id }) {
            httpClientViewModel.collections[collectionIndex].monitors[monitorIndex].isEnabled = isEnabled
            httpClientViewModel.saveCollections()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isToggling = false
        }
    }
}

struct InfoView: View {
    @Environment(\.openURL) private var openURL
    var accentColor: Color
    var backgroundColor: Color
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notificationManager = NotificationManager()
    @State private var showingResetAlert = false
    @State private var showingResetConfirmation = false
    @State private var showingSettings = false
    
    let infoItems = [
        ("Version", "2.0.0"),
        ("Made by", "Velyzo"),
        ("Website", "https://velyzo.de"),
        ("GitHub", "https://github.com/velyzo"),
        ("Contact", "mail@velyzo.de")
    ]
    
    let features = [
        ("HTTP Client", "Send and test API requests", "network"),
        ("Collections", "Organize your requests", "folder.fill"),
        ("Monitors", "Track service status", "wave.3.right"),
        ("Real-time", "Live monitoring updates", "clock.arrow.circlepath")
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Modern app header
                        modernAppHeader
                        
                        // Settings section with functional options
                        modernSettingsSection
                        
                        // Features showcase
                        modernFeaturesSection
                        
                        // About information
                        modernAboutSection
                        
                        // Legal links
                        modernLegalSection
                        
                        // Copyright
                        Text("© 2025 Velyzo. All rights reserved.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Settings")
            .navigationBarHidden(true)
            .onAppear {
                notificationManager.checkNotificationStatus()
            }
            .alert("Reset App Data", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    httpClientViewModel.resetAllData()
                    showingResetConfirmation = true
                }
            } message: {
                Text("This will delete all your collections, requests, monitors, and settings. This action cannot be undone.")
            }
            .alert("Data Reset Complete", isPresented: $showingResetConfirmation) {
                Button("OK") { }
            } message: {
                Text("All app data has been successfully reset.")
            }
            .sheet(isPresented: $showingSettings) {
                ModernAppSettingsView(
                    notificationManager: notificationManager,
                    httpClientViewModel: httpClientViewModel
                )
            }
        }
    }
    
    private var modernAppHeader: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.blue.opacity(0.4), radius: 20, x: 0, y: 10)
                
                Image(systemName: "globe.americas.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text("Connecto")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("Professional HTTP Client & API Monitor")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                
                Text("Version 2.0.0")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.blue)
                    )
            }
        }
    }
    
    private var modernSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            VStack(spacing: 16) {
                // Notifications
                ModernSettingsRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: notificationManager.notificationsEnabled ? "Enabled" : "Tap to enable",
                    color: .orange,
                    trailing: {
                        Image(systemName: notificationManager.notificationsEnabled ? "checkmark.circle.fill" : "chevron.right")
                            .foregroundStyle(notificationManager.notificationsEnabled ? .green : .secondary)
                    }
                ) {
                    handleNotificationSettings()
                }
                
                Divider()
                
                // App Settings
                ModernSettingsRow(
                    icon: "gear",
                    title: "App Preferences",
                    subtitle: "Customize your experience",
                    color: .blue,
                    trailing: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                ) {
                    showingSettings = true
                }
                
                Divider()
                
                // Data Management
                ModernSettingsRow(
                    icon: "trash.fill",
                    title: "Clear All Data",
                    subtitle: "Reset app to initial state",
                    color: .red,
                    trailing: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                ) {
                    showingResetAlert = true
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 15, x: 0, y: 8)
            )
        }
    }
    
    private var modernFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Features")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(features, id: \.0) { feature in
                    ModernFeatureCard(
                        title: feature.0,
                        description: feature.1,
                        icon: feature.2
                    )
                }
            }
        }
    }
    
    private var modernAboutSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("About")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            
            VStack(spacing: 0) {
                ForEach(infoItems.dropFirst(), id: \.0) { item in
                    ModernInfoRow(title: item.0, value: item.1, openURL: openURL)
                    
                    if item.0 != infoItems.last?.0 {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 15, x: 0, y: 8)
            )
        }
    }
    
    private var modernLegalSection: some View {
        VStack(spacing: 16) {
            NavigationLink(destination: PrivacyPolicyView(backgroundColor: backgroundColor)) {
                ModernLegalRow(
                    icon: "hand.raised.fill",
                    title: "Privacy Policy",
                    color: .blue
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            NavigationLink(destination: TermsOfUseView(backgroundColor: backgroundColor)) {
                ModernLegalRow(
                    icon: "doc.text.fill",
                    title: "Terms of Use",
                    color: .purple
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func handleNotificationSettings() {
        if notificationManager.notificationStatus == .denied {
            notificationManager.openNotificationSettings()
        } else if notificationManager.notificationStatus == .notDetermined {
            Task {
                await notificationManager.requestNotificationPermission()
            }
        } else {
            // Already authorized, maybe show status or settings
            notificationManager.openNotificationSettings()
        }
    }
}

// MARK: - Modern Settings Components
struct ModernSettingsRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let trailing: () -> Trailing
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                trailing()
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModernFeatureCard: View {
    let title: String
    let description: String
    let icon: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
        )
    }
}

struct ModernInfoRow: View {
    let title: String
    let value: String
    let openURL: OpenURLAction
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            handleAction()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Text(value)
                        .font(.system(size: 13))
                        .foregroundStyle(isActionable ? .blue : .secondary)
                }
                
                Spacer()
                
                if isActionable {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isActionable)
    }
    
    private var isActionable: Bool {
        title == "Website" || title == "GitHub" || title == "Contact" || isValidURL
    }
    
    private var isValidURL: Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
    
    private func handleAction() {
        // Trigger haptic feedback for all link actions
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.prepare()
        impactFeedback.impactOccurred()
        
        if title == "Contact" {
            if let url = URL(string: "mailto:\(value)") {
                openURL(url)
            }
        } else if title == "Website" || title == "GitHub" || isValidURL {
            var urlString = value
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                urlString = "https://\(urlString)"
            }
            
            if let url = URL(string: urlString) {
                openURL(url)
            }
        }
    }
}

struct ModernLegalRow: View {
    let icon: String
    let title: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
        )
    }
}

struct ModernAppSettingsView: View {
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                List {
                    Section("Preferences") {
                        ModernToggleRow(
                            icon: "hand.tap.fill",
                            title: "Haptic Feedback",
                            subtitle: "Feel vibrations for interactions",
                            color: .orange,
                            isOn: $httpClientViewModel.hapticFeedbackEnabled
                        )
                        .onChange(of: httpClientViewModel.hapticFeedbackEnabled) { _, _ in
                            httpClientViewModel.saveSettings()
                            httpClientViewModel.triggerHapticFeedback(.light)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                    Section("Request Settings") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Default Timeout")
                                    .font(.system(size: 16, weight: .medium))
                                
                                Spacer()
                                
                                Text("\(Int(httpClientViewModel.requestTimeout))s")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(value: $httpClientViewModel.requestTimeout, in: 5...120, step: 5) {
                                Text("Timeout")
                            }
                            .tint(.blue)
                            .onChange(of: httpClientViewModel.requestTimeout) { _, _ in
                                httpClientViewModel.saveSettings()
                                httpClientViewModel.triggerHapticFeedback(.light)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    
                    Section("Data Statistics") {
                        ModernDataInfoRow(
                            icon: "doc.fill",
                            title: "Saved Requests",
                            value: "\(httpClientViewModel.collections.flatMap(\.requests).count)",
                            color: .blue
                        )
                        
                        ModernDataInfoRow(
                            icon: "clock.arrow.circlepath",
                            title: "History Entries",
                            value: "\(httpClientViewModel.requestHistory.count)",
                            color: .orange
                        )
                        
                        ModernDataInfoRow(
                            icon: "folder.fill",
                            title: "Collections",
                            value: "\(httpClientViewModel.collections.count)",
                            color: .purple
                        )
                        
                        if !httpClientViewModel.monitors.isEmpty {
                            ModernDataInfoRow(
                                icon: "wave.3.right",
                                title: "Monitors",
                                value: "\(httpClientViewModel.monitors.count)",
                                color: .green
                            )
                        }
                        
                        ModernDataInfoRow(
                            icon: "internaldrive",
                            title: "Storage Used",
                            value: httpClientViewModel.calculateStorageUsage(),
                            color: .gray
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("App Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ModernToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: 28, height: 28)
                
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct ModernDataInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: 28, height: 28)
                
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
                .fontWeight(.medium)
            
            Spacer()
            
            if value.hasPrefix("http") {
                Text(value)
                    .foregroundColor(.blue)
            } else {
                Text(value)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

struct PrivacyPolicyView: View {
    var backgroundColor: Color
    
    var body: some View {
        ZStack {
            backgroundColor
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Last updated: July 2, 2025")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("1. Introduction")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("This Privacy Policy informs you about the nature, scope, and purpose of the collection and use of personal data by the Connecto App.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("2. Responsible Person")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("The person responsible under data protection laws is:\n\nDevin Oldenburg\nEmail: mustang.oberhalb.7a@icloud.com \nWebsite: https://velyzo.de")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("3. Data Collection in the App")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("The Connecto App stores all data locally on your device. We do not collect, store, or transfer any personal data to our servers or third parties. The network configurations and presets you enter are stored exclusively on your device in the UserDefaults database.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Group {
                        Text("4. Network Requests")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("The app allows you to send HTTP requests to self-defined endpoints. These requests are sent directly from your device to your specified target endpoints. We have no access to the contents of these requests or their responses.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("5. Permissions")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("The app needs access to the internet to execute the HTTP requests you configure. No additional permissions are required or requested.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("6. Analytics and Crash Reporting")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("The app does not use any analytics or crash reporting tools and does not collect usage data.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("7. Changes to this Privacy Policy")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("We reserve the right to modify this Privacy Policy to ensure it always complies with current legal requirements or to implement changes to our services in the Privacy Policy, e.g., when introducing new features. The new Privacy Policy will then apply to your subsequent visits.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Group {
                        Text("8. Contact")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("If you have questions about the collection, processing, or use of your personal data, for information, correction, blocking, or deletion of data, please contact:\n\nEmail: velis.help@gmail.com")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TermsOfUseView: View {
    var backgroundColor: Color
    
    var body: some View {
        ZStack {
            backgroundColor
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Last updated: July 2, 2025")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("1. Acceptance of Terms of Use")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("By using the Connecto App, you accept these Terms of Use in full. If you disagree with these terms, you must not use the app.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("2. Description of Services")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("Connecto is an app that allows you to send and manage HTTP requests. The app enables configuration and sending of HTTP requests to any endpoint.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("3. Usage Restrictions")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("You agree not to use the app for unlawful purposes or to infringe upon the rights of third parties. Use of the app is at your own risk.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Group {
                        Text("4. Limitation of Liability")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("The app is provided \"as is\" and \"as available\" without any express or implied warranty. The developer assumes no liability for direct, indirect, incidental, or consequential damages resulting from the use of the app.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("5. Changes to the Terms of Use")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("The developer reserves the right to change these Terms of Use at any time. Continued use of the app after such changes constitutes your consent to the modified terms.")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("6. Applicable Law")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text("These Terms of Use are governed by the laws of the Federal Republic of Germany.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
            }
            .navigationTitle("Terms of Use")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


// MARK: - Enhanced HTTP Client Components

struct EnhancedHeadersView: View {
    @Binding var request: HTTPRequest
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Quick Header Templates
                VStack(alignment: .leading, spacing: 8) {
                    Text("Common Headers")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        HeaderTemplateButton(title: "JSON Content", key: "Content-Type", value: "application/json", request: $request)
                        HeaderTemplateButton(title: "Authorization", key: "Authorization", value: "Bearer ", request: $request)
                        HeaderTemplateButton(title: "User Agent", key: "User-Agent", value: "Connecto/2.0", request: $request)
                        HeaderTemplateButton(title: "Accept JSON", key: "Accept", value: "application/json", request: $request)
                    }
                }
                
                Divider()
                
                // Custom Headers
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Custom Headers")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button(action: { request.headers.append(HTTPHeader()) }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    ForEach($request.headers) { $header in
                        HeaderRow(header: $header, onDelete: {
                            request.headers.removeAll { $0.id == header.id }
                        })
                    }
                    
                    if request.headers.isEmpty {
                        Text("No custom headers added")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
            }
            .padding()
        }
    }
}

struct HeaderTemplateButton: View {
    let title: String
    let key: String
    let value: String
    @Binding var request: HTTPRequest
    
    var body: some View {
        Button(action: {
            if !request.headers.contains(where: { $0.key == key }) {
                request.headers.append(HTTPHeader(key: key, value: value))
            }
        }) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct HeaderRow: View {
    @Binding var header: HTTPHeader
    let onDelete: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                TextField("Header Name", text: $header.key)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(.body, design: .monospaced))
            }
            
            VStack(spacing: 4) {
                TextField("Header Value", text: $header.value)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(.body, design: .monospaced))
            }
            
            Button(action: {
                let notificationGenerator = UINotificationFeedbackGenerator()
                notificationGenerator.prepare()
                notificationGenerator.notificationOccurred(.error)
                onDelete()
            }) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
        )
    }
}

struct EnhancedBodyView: View {
    @Binding var request: HTTPRequest
    let colorScheme: ColorScheme
    
    @State private var selectedBodyType = "raw"
    @State private var selectedRawType = "json"
    
    var body: some View {
        VStack(spacing: 0) {
            // Body Type Selector
            HStack {
                Picker("Body Type", selection: $selectedBodyType) {
                    Text("Raw").tag("raw")
                    Text("Form Data").tag("form")
                    Text("Binary").tag("binary")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Spacer()
            }
            .padding()
            
            if selectedBodyType == "raw" {
                VStack(spacing: 12) {
                    // Raw Type Selector
                    HStack {
                        Text("Format:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Raw Type", selection: $selectedRawType) {
                            Text("JSON").tag("json")
                            Text("XML").tag("xml")
                            Text("HTML").tag("html")
                            Text("Text").tag("text")
                        }
                        .pickerStyle(MenuPickerStyle())
                        
                        Spacer()
                        
                        // Format Button
                        Button("Format") {
                            formatBody()
                        }
                        .font(.caption)
                        .disabled(request.body.isEmpty)
                    }
                    .padding(.horizontal)
                    
                    // Body Editor
                    TextEditor(text: $request.body)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal)
                    
                    // Body Templates
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            BodyTemplateButton(
                                title: "JSON Object",
                                template: "{\n  \"key\": \"value\",\n  \"number\": 123,\n  \"boolean\": true\n}",
                                contentType: "application/json",
                                request: $request
                            )
                            
                            BodyTemplateButton(
                                title: "JSON Array",
                                template: "[\n  {\n    \"id\": 1,\n    \"name\": \"item1\"\n  },\n  {\n    \"id\": 2,\n    \"name\": \"item2\"\n  }\n]",
                                contentType: "application/json",
                                request: $request
                            )
                            
                            BodyTemplateButton(
                                title: "XML",
                                template: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n  <element>value</element>\n  <number>123</number>\n</root>",
                                contentType: "application/xml",
                                request: $request
                            )
                            
                            BodyTemplateButton(
                                title: "GraphQL",
                                template: "{\n  \"query\": \"query { user { id name email } }\",\n  \"variables\": {}\n}",
                                contentType: "application/json",
                                request: $request
                            )
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            Spacer()
        }
    }
    
    private func formatBody() {
        if selectedRawType == "json" && !request.body.isEmpty {
            if let data = request.body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                request.body = prettyString
            }
        }
    }
}

struct AuthenticationView: View {
    @Binding var request: HTTPRequest
    @State private var authType = "none"
    @State private var bearerToken = ""
    @State private var basicUsername = ""
    @State private var basicPassword = ""
    @State private var apiKey = ""
    @State private var apiKeyHeader = "X-API-Key"
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Authentication Type")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Picker("Auth Type", selection: $authType) {
                        Text("No Auth").tag("none")
                        Text("Bearer Token").tag("bearer")
                        Text("Basic Auth").tag("basic")
                        Text("API Key").tag("apikey")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                if authType == "bearer" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bearer Token")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        SecureField("Enter bearer token", text: $bearerToken)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: bearerToken) { _, newValue in
                                updateAuthHeader(type: "bearer", value: newValue)
                            }
                    }
                }
                
                if authType == "basic" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Basic Authentication")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Username", text: $basicUsername)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: basicUsername) { _, _ in
                                updateBasicAuth()
                            }
                        
                        SecureField("Password", text: $basicPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: basicPassword) { _, _ in
                                updateBasicAuth()
                            }
                    }
                }
                
                if authType == "apikey" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("API Key")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("Header Name", text: $apiKeyHeader)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: apiKey) { _, newValue in
                                updateAuthHeader(type: "apikey", value: newValue)
                            }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func updateAuthHeader(type: String, value: String) {
        // Remove existing auth headers
        request.headers.removeAll { header in
            header.key.lowercased() == "authorization" ||
            header.key.lowercased() == apiKeyHeader.lowercased()
        }
        
        if !value.isEmpty {
            switch type {
            case "bearer":
                request.headers.append(HTTPHeader(key: "Authorization", value: "Bearer \(value)"))
            case "apikey":
                request.headers.append(HTTPHeader(key: apiKeyHeader, value: value))
            default:
                break
            }
        }
    }
    
    private func updateBasicAuth() {
        request.headers.removeAll { $0.key.lowercased() == "authorization" }
        
        if !basicUsername.isEmpty || !basicPassword.isEmpty {
            let credentials = "\(basicUsername):\(basicPassword)"
            if let data = credentials.data(using: .utf8) {
                let base64 = data.base64EncodedString()
                request.headers.append(HTTPHeader(key: "Authorization", value: "Basic \(base64)"))
            }
        }
    }
}

struct EnhancedHistoryView: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    let onLoadRequest: (HTTPRequest) -> Void
    let accentColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    
    var filteredHistory: [HTTPRequest] {
        if searchText.isEmpty {
            return httpClientViewModel.requestHistory
        } else {
            return httpClientViewModel.requestHistory.filter { request in
                request.name.localizedCaseInsensitiveContains(searchText) ||
                request.url.localizedCaseInsensitiveContains(searchText) ||
                request.method.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
            )
            .padding(.horizontal)
            .padding(.top)
            
            ScrollView {
                if filteredHistory.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text(searchText.isEmpty ? "No Request History" : "No Results Found")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(searchText.isEmpty ? 
                             "Your request history will appear here" :
                             "Try searching for a different term")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 50)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredHistory) { request in
                            EnhancedHistoryRequestCard(
                                request: request,
                                onLoad: { onLoadRequest(request) },
                                accentColor: accentColor
                            )
                        }
                    }
                    .padding()
                    
                    if !searchText.isEmpty {
                        Button("Clear History") {
                            httpClientViewModel.clearHistory()
                        }
                        .foregroundColor(.red)
                        .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced Response Components

struct EnhancedResponseView: View {
    @Binding var responseText: String
    @Binding var isVisible: Bool
    let responseData: (data: Data?, response: URLResponse?, error: Error?)?
    let requestDuration: TimeInterval
    let request: HTTPRequest
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedResponseTab = 0
    @State private var showingShareSheet = false
    
    var statusCode: Int? {
        (responseData?.response as? HTTPURLResponse)?.statusCode
    }
    
    var statusColor: Color {
        guard let code = statusCode else { return .gray }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400..<500: return .red
        case 500...: return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Status
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Response")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        if let code = statusCode {
                            HStack {
                                Text("\(code)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(statusColor)
                                
                                Text(HTTPURLResponse.localizedString(forStatusCode: code))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(String(format: "%.0f", requestDuration * 1000))ms")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: { isVisible = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Quick Stats
                if let httpResponse = responseData?.response as? HTTPURLResponse {
                    HStack {
                        StatPill(title: "Size", value: formatSize(responseData?.data?.count ?? 0))
                        StatPill(title: "Headers", value: "\(httpResponse.allHeaderFields.count)")
                        
                        Spacer()
                        
                        Button(action: { showingShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
            )
            .padding()
            
            // Response Tabs
            HStack {
                ForEach(0..<2) { index in
                    let titles = ["Body", "Headers"]
                    
                    Button(action: { selectedResponseTab = index }) {
                        Text(titles[index])
                            .font(.subheadline)
                            .fontWeight(selectedResponseTab == index ? .semibold : .regular)
                            .foregroundColor(selectedResponseTab == index ? .blue : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedResponseTab == index ? 
                                Color.blue.opacity(0.1) : Color.clear
                            )
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            
            // Response Content
            TabView(selection: $selectedResponseTab) {
                ResponseBodyView(responseData: responseData)
                    .tag(0)
                
                ResponseHeadersView(responseData: responseData)
                    .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color(UIColor.systemBackground) : Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
    }
    
    private func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct StatPill: View {
    let title: String
    let value: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
        )
    }
}

struct ResponseBodyView: View {
    let responseData: (data: Data?, response: URLResponse?, error: Error?)?
    
    @State private var formattedText = ""
    @State private var isFormatted = false
    
    var body: some View {
        ScrollView {
            if let data = responseData?.data, let text = String(data: data, encoding: .utf8) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Response Body")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(isFormatted ? "Raw" : "Format") {
                            toggleFormat(text)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    
                    Text(isFormatted ? formattedText : text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.systemGray6))
                        )
                }
                .padding()
            } else {
                Text("No response body")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if let data = responseData?.data, let text = String(data: data, encoding: .utf8) {
                formatText(text)
            }
        }
    }
    
    private func toggleFormat(_ text: String) {
        if isFormatted {
            isFormatted = false
        } else {
            formatText(text)
            isFormatted = true
        }
    }
    
    private func formatText(_ text: String) {
        if text.hasPrefix("{") || text.hasPrefix("[") {
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                formattedText = prettyString
                return
            }
        }
        formattedText = text
    }
}

struct ResponseHeadersView: View {
    let responseData: (data: Data?, response: URLResponse?, error: Error?)?
    
    var body: some View {
        ScrollView {
            if let httpResponse = responseData?.response as? HTTPURLResponse {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(httpResponse.allHeaderFields.keys), id: \.self) { key in
                        if let value = httpResponse.allHeaderFields[key] {
                            HeaderResponseRow(key: String(describing: key), value: String(describing: value))
                        }
                    }
                }
                .padding()
            } else {
                Text("No response headers")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct HeaderResponseRow: View {
    let key: String
    let value: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray5))
        )
    }
}

// MARK: - Legacy Component Views

struct HeadersConfigView: View {
    @Binding var request: HTTPRequest
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach($request.headers) { $header in
                    HStack(spacing: 12) {
                        TextField("Header Name", text: $header.key)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextField("Header Value", text: $header.value)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            request.headers.removeAll { $0.id == header.id }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Button(action: { 
                    let notificationGenerator = UINotificationFeedbackGenerator()
                    notificationGenerator.prepare()
                    notificationGenerator.notificationOccurred(.success)
                    request.headers.append(HTTPHeader()) 
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Header")
                    }
                    .foregroundColor(.blue)
                }
                
                // Common Headers Quick Add
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach([
                        ("Authorization", "Bearer "),
                        ("Content-Type", "application/json"),
                        ("Accept", "application/json"),
                        ("User-Agent", "Connecto/2.0"),
                        ("X-API-Key", ""),
                        ("Cache-Control", "no-cache")
                    ], id: \.0) { headerPair in
                        Button(action: {
                            let notificationGenerator = UINotificationFeedbackGenerator()
                            notificationGenerator.prepare()
                            notificationGenerator.notificationOccurred(.success)
                            if !request.headers.contains(where: { $0.key == headerPair.0 }) {
                                request.headers.append(HTTPHeader(key: headerPair.0, value: headerPair.1))
                            }
                        }) {
                            Text(headerPair.0)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top)
            }
            .padding()
        }
    }
}

struct BodyConfigView: View {
    @Binding var request: HTTPRequest
    let colorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request Body")
                .font(.headline)
                .padding(.horizontal)
            
            TextEditor(text: $request.body)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)
            
            // Body Templates
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    BodyTemplateButton(title: "JSON", template: "{\n  \"key\": \"value\",\n  \"number\": 123,\n  \"boolean\": true\n}", contentType: "application/json", request: $request)
                    
                    BodyTemplateButton(title: "XML", template: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n  <element>value</element>\n  <number>123</number>\n</root>", contentType: "application/xml", request: $request)
                    
                    BodyTemplateButton(title: "Form Data", template: "key1=value1&key2=value2&key3=value3", contentType: "application/x-www-form-urlencoded", request: $request)
                    
                    BodyTemplateButton(title: "GraphQL", template: "{\n  \"query\": \"query { user { id name email } }\",\n  \"variables\": {}\n}", contentType: "application/json", request: $request)
                    
                    BodyTemplateButton(title: "Plain Text", template: "This is plain text content", contentType: "text/plain", request: $request)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
    }
}

struct BodyTemplateButton: View {
    let title: String
    let template: String
    let contentType: String
    @Binding var request: HTTPRequest
    
    var body: some View {
        Button(action: {
            request.body = template
            if !request.headers.contains(where: { $0.key == "Content-Type" }) {
                request.headers.append(HTTPHeader(key: "Content-Type", value: contentType))
            } else {
                if let index = request.headers.firstIndex(where: { $0.key == "Content-Type" }) {
                    request.headers[index].value = contentType
                }
            }
        }) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsConfigView: View {
    @Binding var request: HTTPRequest
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Timeout")
                    .font(.headline)
                
                HStack {
                    Text("\(Int(request.timeout))s")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 40, alignment: .leading)
                    
                    Slider(value: $request.timeout, in: 5...120, step: 5)
                    
                    Text("120s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Request timeout duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Follow Redirects", isOn: $request.followRedirects)
                    .font(.headline)
                
                Text("Automatically follow HTTP redirects")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Settings")
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    QuickSettingButton(title: "Reset Timeout", subtitle: "30s", action: {
                        request.timeout = 30.0
                    })
                    
                    QuickSettingButton(title: "Long Timeout", subtitle: "120s", action: {
                        request.timeout = 120.0
                    })
                    
                    QuickSettingButton(title: "Clear Headers", subtitle: "Remove all", action: {
                        request.headers.removeAll()
                    })
                    
                    QuickSettingButton(title: "Clear Body", subtitle: "Empty body", action: {
                        request.body = ""
                    })
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

struct QuickSettingButton: View {
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct HistoryView: View {
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    let onLoadRequest: (HTTPRequest) -> Void
    let accentColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            if httpClientViewModel.requestHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    
                    Text("No Request History")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Your request history will appear here")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(httpClientViewModel.requestHistory) { request in
                        HTTPHistoryRequestCard(
                            request: request,
                            onLoad: { onLoadRequest(request) },
                            accentColor: accentColor
                        )
                    }
                }
                .padding()
                
                Button("Clear History") {
                    httpClientViewModel.clearHistory()
                }
                .foregroundColor(.red)
                .padding()
            }
        }
    }
}

struct HTTPHistoryRequestCard: View {
    let request: HTTPRequest
    let onLoad: () -> Void
    let accentColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        case "HEAD": return .gray
        case "OPTIONS": return .brown
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(request.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(request.method)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(methodColor(for: request.method).opacity(0.2))
                    )
                    .foregroundColor(methodColor(for: request.method))
            }
            
            Text(request.url.isEmpty ? "No URL" : request.url)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                if !request.headers.isEmpty {
                    Text("\(request.headers.filter { !$0.key.isEmpty }.count) headers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if !request.body.isEmpty {
                    Text("• Body: \(request.body.count) chars")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: onLoad) {
                Text("Load Request")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }
}

struct EnhancedCollectionCard: View {
    let collection: Collection
    let accentColor: Color
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    let onMoveRequest: (HTTPRequest) -> Void
    let onEditCollection: (Collection) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingActionSheet = false
    
    private var cardBackground: Color {
        Color(collection.color).opacity(0.1)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color(collection.color))
                            .frame(width: 8, height: 8)
                        
                        Text(collection.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    
                    Text("\(collection.requests.count) request\(collection.requests.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Menu {
                    Button(action: {
                        onEditCollection(collection)
                    }) {
                        Label("View Details", systemImage: "eye")
                    }
                    
                    Button(action: {
                        // Edit collection name
                    }) {
                        Label("Rename", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        if let index = httpClientViewModel.collections.firstIndex(where: { $0.id == collection.id }) {
                            httpClientViewModel.deleteCollection(at: IndexSet(integer: index))
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
            
            // Request Preview
            if collection.requests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Text("No requests")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(collection.requests.prefix(2)) { request in
                        RequestPreviewRow(
                            request: request,
                            collection: collection,
                            onMove: { onMoveRequest(request) }
                        )
                    }
                    
                    if collection.requests.count > 2 {
                        Text("+\(collection.requests.count - 2) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }
                }
            }
            
            // Stats Bar
            if !collection.requests.isEmpty {
                let methodCounts = Dictionary(grouping: collection.requests, by: { $0.method })
                
                HStack(spacing: 4) {
                    ForEach(["GET", "POST", "PUT", "DELETE"], id: \.self) { method in
                        if let count = methodCounts[method]?.count, count > 0 {
                            Text("\(method): \(count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(methodColor(for: method).opacity(0.2))
                                .foregroundColor(methodColor(for: method))
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(collection.color).opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .onTapGesture {
            onEditCollection(collection)
        }
    }
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
}

struct RequestPreviewRow: View {
    let request: HTTPRequest
    let collection: Collection
    let onMove: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(request.method)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(methodColor(for: request.method))
                .frame(width: 40, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !request.url.isEmpty {
                    Text(request.url)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Menu {
                Button(action: onMove) {
                    Label("Move to...", systemImage: "arrow.right.square")
                }
                
                Button(action: {
                    // Duplicate request
                }) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                
                Button(role: .destructive, action: {
                    // Delete request
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
        )
    }
}

struct CollectionDetailView: View {
    let collection: Collection
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    let accentColor: Color
    let backgroundColor: Color
    let onMoveRequest: (HTTPRequest) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var showingAddRequest = false
    @State private var editingCollection = false
    @State private var editedName = ""
    @State private var editedColor = "blue"
    
    var filteredRequests: [HTTPRequest] {
        if searchText.isEmpty {
            return collection.requests
        } else {
            return collection.requests.filter { request in
                request.name.localizedCaseInsensitiveContains(searchText) ||
                request.url.localizedCaseInsensitiveContains(searchText) ||
                request.method.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundColor
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Collection Header
                    VStack(spacing: 16) {
                        HStack {
                            Circle()
                                .fill(Color(collection.color))
                                .frame(width: 12, height: 12)
                            
                            Text(collection.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button("Edit") {
                                editedName = collection.name
                                editedColor = collection.color
                                editingCollection = true
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Requests")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(collection.requests.count)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                            
                            Spacer()
                            
                            let methodCounts = Dictionary(grouping: collection.requests, by: { $0.method })
                            ForEach(["GET", "POST", "PUT", "DELETE"], id: \.self) { method in
                                if let count = methodCounts[method]?.count, count > 0 {
                                    VStack(spacing: 2) {
                                        Text(method)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(count)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(methodColor(for: method))
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    )
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search requests...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    )
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Requests List
                    if filteredRequests.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: searchText.isEmpty ? "plus.circle.dashed" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.4))
                            
                            Text(searchText.isEmpty ? "No Requests" : "No Results Found")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            
                            if searchText.isEmpty {
                                Button("Add First Request") {
                                    showingAddRequest = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredRequests) { request in
                                    DetailedRequestCard(
                                        request: request,
                                        collection: collection,
                                        httpClientViewModel: httpClientViewModel,
                                        onMove: { onMoveRequest(request) }
                                    )
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top)
                        }
                    }
                }
            }
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddRequest = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("Edit Collection", isPresented: $editingCollection) {
            TextField("Collection Name", text: $editedName)
            
            Button("Save") {
                var updatedCollection = collection
                updatedCollection.name = editedName
                updatedCollection.color = editedColor
                httpClientViewModel.updateCollection(updatedCollection)
                editingCollection = false
            }
            .disabled(editedName.isEmpty)
            
            Button("Cancel", role: .cancel) {
                editingCollection = false
            }
        }
    }
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
}

struct DetailedRequestCard: View {
    let request: HTTPRequest
    let collection: Collection
    @ObservedObject var httpClientViewModel: HTTPClientViewModel
    let onMove: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(request.method)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(methodColor(for: request.method))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(methodColor(for: request.method).opacity(0.1))
                            .cornerRadius(6)
                        
                        Text(request.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    
                    if !request.url.isEmpty {
                        Text(request.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Menu {
                    Button(action: {
                        // Load in client
                    }) {
                        Label("Load in Client", systemImage: "play.fill")
                    }
                    
                    Button(action: onMove) {
                        Label("Move to...", systemImage: "arrow.right.square")
                    }
                    
                    Button(action: {
                        httpClientViewModel.duplicateRequest(request, in: collection)
                    }) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        if let index = collection.requests.firstIndex(where: { $0.id == request.id }) {
                            httpClientViewModel.deleteRequest(at: IndexSet(integer: index), from: collection)
                        }
                    }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }
            
            // Request Details
            HStack {
                if !request.headers.isEmpty {
                    Label("\(request.headers.count)", systemImage: "list.bullet")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if !request.body.isEmpty {
                    Label("\(request.body.count) chars", systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Label("\(Int(request.timeout))s", systemImage: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct MoveRequestSheet: View {
    let request: HTTPRequest
    let sourceCollection: Collection
    let collections: [Collection]
    let onMove: (Collection) -> Void
    let onCancel: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var availableCollections: [Collection] {
        collections.filter { $0.id != sourceCollection.id }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "arrow.right.square")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("Move Request")
                                .font(.headline)
                            Text("From \(sourceCollection.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text(request.method)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue)
                            .cornerRadius(6)
                        
                        Text(request.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                )
                .padding(.horizontal)
                .padding(.top)
                
                // Collections List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(availableCollections) { collection in
                            Button(action: {
                                onMove(collection)
                            }) {
                                HStack {
                                    Circle()
                                        .fill(Color(collection.color))
                                        .frame(width: 12, height: 12)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(collection.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("\(collection.requests.count) requests")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                
                if availableCollections.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.4))
                        
                        Text("No Other Collections")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text("Create another collection to move requests between them.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .navigationTitle("Move Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

struct HTTPResponseView: View {
    @Binding var responseText: String
    @Binding var isVisible: Bool
    let responseData: (data: Data?, response: URLResponse?, error: Error?)?
    let requestDuration: TimeInterval
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedResponseTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Response")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let httpResponse = responseData?.response as? HTTPURLResponse {
                        HStack {
                            Text("Status: \(httpResponse.statusCode)")
                                .font(.caption)
                                .foregroundColor(httpResponse.statusCode < 400 ? .green : .red)
                            
                            if requestDuration > 0 {
                                Text("• \(String(format: "%.2f", requestDuration))s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Close response")
            }
            .padding()
            .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
            
            // Response tabs
            if responseData != nil {
                Picker("Response View", selection: $selectedResponseTab) {
                    Text("Body").tag(0)
                    Text("Headers").tag(1)
                    Text("Raw").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
            }
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.2))
            
            // Content
            if selectedResponseTab == 0 {
                // Body view
                ScrollView {
                    if let data = responseData?.data, let body = String(data: data, encoding: .utf8) {
                        Text(formatResponse(body))
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text("No response body")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            } else if selectedResponseTab == 1 {
                // Headers view
                ScrollView {
                    if let httpResponse = responseData?.response as? HTTPURLResponse {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(httpResponse.allHeaderFields), id: \.key) { key, value in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(describing: key))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text(String(describing: value))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                
                                if key.description != Array(httpResponse.allHeaderFields).last?.key.description {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                    }
                }
            } else {
                // Raw view
                ScrollView {
                    Text(responseText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: .infinity, maxHeight: 650)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(), value: isVisible)
    }
    
    private func formatResponse(_ text: String) -> String {
        if text.hasPrefix("{") || text.hasPrefix("[") {
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                return prettyString
            }
        }
        return text
    }
}

struct EnhancedHistoryRequestCard: View {
    let request: HTTPRequest
    let onLoad: () -> Void
    let accentColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        case "PATCH": return .purple
        default: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Method badge
                Text(request.method)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(methodColor(for: request.method))
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if !request.url.isEmpty {
                        Text(request.url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(action: onLoad) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Load")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
                }
            }
            
            // Headers preview
            if !request.headers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Headers (\(request.headers.count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        ForEach(request.headers.prefix(3)) { header in
                            if !header.key.isEmpty {
                                Text(header.key)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        
                        if request.headers.count > 3 {
                            Text("+\(request.headers.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct RequestTemplatesSheet: View {
    let onSelectTemplate: (HTTPRequest) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let templates = [
        ("GET JSON API", "GET", "https://jsonplaceholder.typicode.com/posts", [HTTPHeader(key: "Content-Type", value: "application/json")], ""),
        ("POST JSON", "POST", "https://httpbin.org/post", [HTTPHeader(key: "Content-Type", value: "application/json")], "{\"key\": \"value\"}"),
        ("GraphQL Query", "POST", "https://api.example.com/graphql", [HTTPHeader(key: "Content-Type", value: "application/json")], "{\"query\": \"{ user { name email } }\"}"),
        ("File Upload", "POST", "https://httpbin.org/post", [HTTPHeader(key: "Content-Type", value: "multipart/form-data")], "")
    ]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(templates.indices, id: \.self) { index in
                    let template = templates[index]
                    Button(action: {
                        var request = HTTPRequest()
                        request.name = template.0
                        request.method = template.1
                        request.url = template.2
                        request.headers = template.3
                        request.body = template.4
                        onSelectTemplate(request)
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.0)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("\(template.1) \(template.2)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Request Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SaveRequestSheet: View {
    let request: HTTPRequest
    let collections: [Collection]
    let onSave: (Collection) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCollection: Collection?
    @State private var newCollectionName = ""
    @State private var showingNewCollection = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Save Request")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose a collection to save '\(request.name)' to:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if collections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("No collections yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Button("Create First Collection") {
                            showingNewCollection = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(collections) { collection in
                            Button(action: {
                                selectedCollection = collection
                                onSave(collection)
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(collection.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("\(collection.requests.count) requests")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Save Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("New Collection") {
                        showingNewCollection = true
                    }
                }
            }
        }
        .alert("New Collection", isPresented: $showingNewCollection) {
            TextField("Collection Name", text: $newCollectionName)
            Button("Create") {
                if !newCollectionName.isEmpty {
                    let newCollection = Collection(name: newCollectionName)
                    onSave(newCollection)
                    newCollectionName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
        }
    }
}

struct MonitorSummaryCard: View {
    let monitor: PingMonitor
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var statusColor: Color {
        switch monitor.status {
        case .online: return .green
        case .offline: return .red
        case .unknown: return .orange
        }
    }
    
    private var statusIcon: String {
        switch monitor.status {
        case .online: return "checkmark.circle.fill"
        case .offline: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Indicator
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundColor(statusColor)
                .frame(width: 24)
            
            // Monitor Info
            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(monitor.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Response Time or Status
            VStack(alignment: .trailing, spacing: 2) {
                if let responseTime = monitor.responseTime, monitor.status == .online {
                    Text("\(Int(responseTime))ms")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(responseTime < 200 ? .green : responseTime < 500 ? .orange : .red)
                } else {
                    Text(monitor.status.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                
                if let lastCheck = monitor.lastCheck {
                    Text(formatRelativeTime(lastCheck))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(statusColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(statusColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct FeatureCard: View {
    let title: String
    let description: String
    let icon: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(height: 24)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct EnhancedInfoRow: View {
    let title: String
    let value: String
    let openURL: OpenURLAction
    
    private var isURL: Bool {
        value.hasPrefix("http")
    }
    
    private var isEmail: Bool {
        value.contains("@") && value.contains(".")
    }
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
                .fontWeight(.medium)
            
            Spacer()
            
            if isURL || isEmail {
                Button(action: {
                    if isEmail {
                        openURL(URL(string: "mailto:\(value)")!)
                    } else {
                        openURL(URL(string: value)!)
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(value)
                            .foregroundColor(.blue)
                        
                        Image(systemName: isEmail ? "envelope" : "arrow.up.right.square")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Text(value)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

#Preview {
    ContentView()
}
