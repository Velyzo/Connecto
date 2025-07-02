import Combine
import SwiftUI

struct KeyValue: Identifiable, Codable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}

struct Preset: Identifiable, Codable {
    let id: UUID
    var name: String
    var protocolType: String
    var ipAddress: String
    var port: String
    var endpoint: String
    var method: String
    var keyValues: [KeyValue]
}

class PresetViewModel: ObservableObject {
    @Published var presets: [Preset] = []
    private let presetsKey = "SavedPresets"
    private var refreshTimer: Timer?

    init() {
        loadPresets()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshPresetsPeriodically()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }

    func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetsKey)
        }
    }

    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = decoded
        }
    }
    
    @objc private func refreshPresetsPeriodically() {
        self.loadPresets()
    }

    func addPreset(_ preset: Preset) {
        presets.append(preset)
        savePresets()
    }

    func removePreset(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        savePresets()
    }
}
struct ContentView: View {
    @State private var selectedProtocol: String = "http"
    @State private var ipAddress: String = ""
    @State private var port: String = ""
    @State private var endpoint: String = ""
    @State private var method: String = "GET"
    @State private var responseText: String = "Response will appear here..."
    @State private var keyValues: [KeyValue] = [KeyValue()]
    @State private var showResponse = false
    @State private var isOutputPopupVisible = false
    @StateObject private var presetViewModel = PresetViewModel()
    @Environment(\.colorScheme) private var colorScheme

    // Custom colors for the app
    var accentGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [Color.blue, Color.purple.opacity(0.7)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var backgroundGradient: LinearGradient {
        colorScheme == .dark ?
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ) :
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "f5f7fa"), Color(hex: "e4e8f0")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
    }

    var body: some View {
        TabView {
            HomeView(accentGradient: accentGradient, backgroundGradient: backgroundGradient)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            ToolView(
                selectedProtocol: $selectedProtocol,
                ipAddress: $ipAddress,
                port: $port,
                endpoint: $endpoint,
                method: $method,
                keyValues: $keyValues,
                responseText: $responseText,
                showResponse: $showResponse,
                isOutputPopupVisible: $isOutputPopupVisible,
                accentGradient: accentGradient,
                backgroundGradient: backgroundGradient,
                presetViewModel: presetViewModel
            )
            .tabItem {
                Label("Tool", systemImage: "hammer.fill")
            }

            PresetsView(
                presetViewModel: presetViewModel,
                selectedProtocol: $selectedProtocol,
                ipAddress: $ipAddress,
                port: $port,
                endpoint: $endpoint,
                method: $method,
                keyValues: $keyValues,
                responseText: $responseText,
                showResponse: $showResponse,
                isOutputPopupVisible: $isOutputPopupVisible,
                accentGradient: accentGradient,
                backgroundGradient: backgroundGradient
            )
            .tabItem {
                Label("Presets", systemImage: "star.fill")
            }

            InfoView(accentGradient: accentGradient, backgroundGradient: backgroundGradient)
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
    var accentGradient: LinearGradient
    var backgroundGradient: LinearGradient
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 32) {
                    // Header with logo and welcome message
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(accentGradient)
                                .frame(width: 110, height: 110)
                                .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                            
                            Image(systemName: "globe.americas.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.white)
                        }
                        
                        Text("Welcome to Connecto")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("Your professional network toolkit")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                    }
                    .padding(.top, 20)
                    
                    // Feature cards
                    VStack(spacing: 16) {
                        FeatureCard(
                            icon: "antenna.radiowaves.left.and.right.circle.fill",
                            title: "Powerful Networking",
                            description: "Configure and send HTTP requests with support for various methods and parameters",
                            color: .blue
                        )
                        
                        FeatureCard(
                            icon: "star.circle.fill",
                            title: "Save Presets",
                            description: "Create and manage presets for your commonly used API endpoints",
                            color: .purple
                        )
                        
                        FeatureCard(
                            icon: "bolt.shield.fill",
                            title: "Fast & Secure",
                            description: "Send requests directly from your device with local data storage only",
                            color: .green
                        )
                        
                        FeatureCard(
                            icon: "iphone.and.arrow.forward",
                            title: "Get Started",
                            description: "Tap the Tool tab below to create and send your first request",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
        }
        .navigationTitle("Home")
        .navigationBarHidden(true)
        .accessibilityElement(children: .contain)
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(color)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? 
                      Color(UIColor.systemGray6) : 
                      Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}
struct ToolView: View {
    @Binding var selectedProtocol: String
    @Binding var ipAddress: String
    @Binding var port: String
    @Binding var endpoint: String
    @Binding var method: String
    @Binding var keyValues: [KeyValue]
    @Binding var responseText: String
    @Binding var showResponse: Bool
    @Binding var isOutputPopupVisible: Bool
    
    var accentGradient: LinearGradient
    var backgroundGradient: LinearGradient
    
    @ObservedObject var presetViewModel: PresetViewModel
    @State private var isProtocolPickerPresented = false
    @State private var isMethodPickerPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(iOS)
        ZStack {
            backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Network Tool")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("Configure and send HTTP requests")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    
                    // Configuration card
                    VStack(spacing: 20) {
                        // Protocol Selector
                        HStack {
                            Text("Protocol")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(width: 90, alignment: .leading)
                            
                            Picker("Protocol", selection: $selectedProtocol) {
                                Text("HTTP").tag("http")
                                Text("HTTPS").tag("https")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .accessibilityLabel("Select protocol")
                        }
                        .padding(.horizontal)
                        
                        // IP Address
                        InputField(
                            title: "IP/Host", 
                            placeholder: "example.com or 192.168.1.1",
                            text: $ipAddress
                        )
                        .accessibilityLabel("IP address or hostname")
                        
                        // Port
                        InputField(
                            title: "Port", 
                            placeholder: "Optional, e.g. 8080",
                            text: $port
                        )
                        .accessibilityLabel("Port number, optional")
                        
                        // Endpoint
                        InputField(
                            title: "Endpoint", 
                            placeholder: "/api/v1/resource",
                            text: $endpoint
                        )
                        .accessibilityLabel("API endpoint")
                        
                        // HTTP Method
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HTTP Method")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack {
                                ForEach(["GET", "POST", "PUT", "DELETE"], id: \.self) { methodType in
                                    Button(action: {
                                        method = methodType
                                    }) {
                                        Text(methodType)
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(method == methodType ? .bold : .regular)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 12)
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(method == methodType ?
                                                          (methodColor(for: method)) :
                                                          Color(UIColor.systemBackground))
                                            )
                                            .foregroundColor(method == methodType ? .white : .primary)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(methodColor(for: methodType).opacity(0.4), lineWidth: method == methodType ? 0 : 1)
                                            )
                                    }
                                    .accessibilityLabel("\(methodType) method")
                                    .accessibilityAddTraits(method == methodType ? .isSelected : [])
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray5))
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                    )
                    .padding(.horizontal)
                    
                    // Request Body section
                    if method == "POST" || method == "PUT" {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Request Body")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.horizontal)
                            
                            ForEach($keyValues) { $keyValue in
                                HStack(spacing: 12) {
                                    TextField("Key", text: $keyValue.key)
                                        .padding(12)
                                        .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                                        .cornerRadius(8)
                                    
                                    TextField("Value", text: $keyValue.value)
                                        .padding(12)
                                        .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                                        .cornerRadius(8)
                                }
                                .padding(.horizontal)
                            }
                            
                            Button(action: { keyValues.append(KeyValue()) }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Parameter")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .padding(.horizontal)
                            }
                            .accessibilityLabel("Add new key-value pair")
                        }
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray5))
                                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        )
                        .padding(.horizontal)
                    }
                    
                    // Action buttons
                    VStack(spacing: 16) {
                        // Send Request Button
                        Button(action: sendRequest) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .font(.headline)
                                Text("Send Request")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(accentGradient)
                            )
                            .foregroundColor(.white)
                            .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 3)
                        }
                        .accessibilityLabel("Send request")
                        
                        // Save Preset Button
                        Button(action: savePreset) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .font(.headline)
                                Text("Save as Preset")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                            )
                            .foregroundColor(.primary)
                        }
                        .accessibilityLabel("Save as preset")
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            
            // Response Popup
            if isOutputPopupVisible {
                Color.black.opacity(0.5)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                    .zIndex(1)
                
                ResponseView(responseText: $responseText, isVisible: $isOutputPopupVisible)
                    .zIndex(2)
            }
        }
        #else
        // watchOS version
        ScrollView {
            VStack(spacing: 16) {
                // Basic version for Watch
                Text("Tool")
                    .font(.title3)
                    .fontWeight(.bold)
                    .padding(.top)
                
                Picker("Protocol", selection: $selectedProtocol) {
                    Text("HTTP").tag("http")
                    Text("HTTPS").tag("https")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                TextField("Host/IP", text: $ipAddress)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Port", text: $port)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Endpoint", text: $endpoint)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Picker("Method", selection: $method) {
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                    Text("PUT").tag("PUT")
                    Text("DELETE").tag("DELETE")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                if method == "POST" || method == "PUT" {
                    ForEach($keyValues) { $keyValue in
                        HStack {
                            TextField("Key", text: $keyValue.key)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            TextField("Value", text: $keyValue.value)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    Button("Add Pair") {
                        keyValues.append(KeyValue())
                    }
                }
                
                Button(action: sendRequest) {
                    Text("Send Request")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: savePreset) {
                    Text("Save Preset")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                if showResponse {
                    Text("Response")
                        .font(.headline)
                        .padding(.top)
                    
                    Text(responseText)
                        .font(.system(.footnote, design: .monospaced))
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
        #endif
    }
    
    private func methodColor(for method: String) -> Color {
        switch method {
            case "GET":    return Color.blue
            case "POST":   return Color.green
            case "PUT":    return Color.orange
            case "DELETE": return Color.red
            default:       return Color.blue
        }
    }
    
    func sendRequest() {
        guard let url = constructURL() else {
            responseText = "Invalid URL"
            showResponse = true
            isOutputPopupVisible = true
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if method == "POST" || method == "PUT" {
            let jsonBody = keyValues.reduce(into: [String: String]()) { result, pair in
                if !pair.key.isEmpty {
                    result[pair.key] = pair.value
                }
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonBody, options: []) {
                request.httpBody = jsonData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    responseText = "Error: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    var responseString = "Status: \(httpResponse.statusCode)\n\n"
                    if let data = data, let dataString = String(data: data, encoding: .utf8) {
                        responseString += formatResponse(dataString)
                    } else {
                        responseString += "No response body or unable to decode"
                    }
                    responseText = responseString
                } else if let data = data {
                    responseText = formatResponse(String(data: data, encoding: .utf8) ?? "Invalid response data")
                } else {
                    responseText = "Unknown error occurred"
                }
                showResponse = true
                isOutputPopupVisible = true
            }
        }.resume()
    }
    
    private func formatResponse(_ text: String) -> String {
        // Basic attempt to pretty-format JSON
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

    func constructURL() -> URL? {
        guard !ipAddress.isEmpty else {
            return nil
        }

        var urlString = "\(selectedProtocol)://\(ipAddress)"
        if !port.isEmpty {
            urlString += ":\(port)"
        }
        
        // Make sure endpoint starts with /
        var endpointString = endpoint
        if !endpointString.isEmpty && !endpointString.hasPrefix("/") {
            endpointString = "/" + endpointString
        }
        
        urlString += endpointString
        return URL(string: urlString)
    }

    func savePreset() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        
        let newPreset = Preset(
            id: UUID(),
            name: "Preset \(formatter.string(from: Date()))",
            protocolType: selectedProtocol,
            ipAddress: ipAddress,
            port: port,
            endpoint: endpoint,
            method: method,
            keyValues: keyValues
        )
        presetViewModel.addPreset(newPreset)
        
        // Provide haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

struct InputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            HStack {
                
                TextField(placeholder, text: $text)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
}

struct PresetsView: View {
    @ObservedObject var presetViewModel: PresetViewModel
    @Binding var selectedProtocol: String
    @Binding var ipAddress: String
    @Binding var port: String
    @Binding var endpoint: String
    @Binding var method: String
    @Binding var keyValues: [KeyValue]
    @Binding var responseText: String
    @Binding var showResponse: Bool
    @Binding var isOutputPopupVisible: Bool
    var accentGradient: LinearGradient
    var backgroundGradient: LinearGradient
    
    @State private var showingDeleteAlert = false
    @State private var presetToDelete: IndexSet?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                if presetViewModel.presets.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No Presets Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Your saved presets will appear here. Create presets in the Tool tab to quickly reuse configurations.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 40)
                        
                        Button(action: {
                            // Switch to tool tab - This would need a more complex state management
                            // For now, we'll just provide instruction
                        }) {
                            Text("Go to Tool Tab")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(accentGradient)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    // List of presets
                    List {
                        ForEach(presetViewModel.presets) { preset in
                            PresetCard(
                                preset: preset,
                                loadPreset: {
                                    loadPreset(preset)
                                    sendRequest()
                                },
                                accentGradient: accentGradient
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                        .onDelete { indexSet in
                            presetToDelete = indexSet
                            showingDeleteAlert = true
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .background(Color.clear)
                }
                
                // Response popup
                if isOutputPopupVisible {
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                        .transition(.opacity)
                        .zIndex(1)
                    ResponseView(responseText: $responseText, isVisible: $isOutputPopupVisible)
                        .zIndex(2)
                }
            }
            .navigationTitle("Presets")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !presetViewModel.presets.isEmpty {
                        EditButton()
                    }
                }
            }
            .alert(isPresented: $showingDeleteAlert) {
                Alert(
                    title: Text("Delete Preset"),
                    message: Text("Are you sure you want to delete this preset?"),
                    primaryButton: .destructive(Text("Delete")) {
                        if let indexSet = presetToDelete {
                            presetViewModel.removePreset(at: indexSet)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    func loadPreset(_ preset: Preset) {
        selectedProtocol = preset.protocolType
        ipAddress = preset.ipAddress
        port = preset.port
        endpoint = preset.endpoint
        method = preset.method
        keyValues = preset.keyValues
    }

    func sendRequest() {
        guard let url = constructURL() else {
            responseText = "Invalid URL"
            showResponse = true
            isOutputPopupVisible = true
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if method == "POST" || method == "PUT" {
            let jsonBody = keyValues.reduce(into: [String: String]()) { result, pair in
                if !pair.key.isEmpty {
                    result[pair.key] = pair.value
                }
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonBody, options: []) {
                request.httpBody = jsonData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    responseText = "Error: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    var responseString = "Status: \(httpResponse.statusCode)\n\n"
                    if let data = data, let dataString = String(data: data, encoding: .utf8) {
                        responseString += formatResponse(dataString)
                    } else {
                        responseString += "No response body or unable to decode"
                    }
                    responseText = responseString
                } else if let data = data {
                    responseText = formatResponse(String(data: data, encoding: .utf8) ?? "Invalid response data")
                } else {
                    responseText = "Unknown error occurred"
                }
                showResponse = true
                isOutputPopupVisible = true
            }
        }.resume()
    }
    
    private func formatResponse(_ text: String) -> String {
        // Basic attempt to pretty-format JSON
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

    func constructURL() -> URL? {
        guard !ipAddress.isEmpty else {
            return nil
        }

        var urlString = "\(selectedProtocol)://\(ipAddress)"
        if !port.isEmpty {
            urlString += ":\(port)"
        }
        
        // Make sure endpoint starts with /
        var endpointString = endpoint
        if !endpointString.isEmpty && !endpointString.hasPrefix("/") {
            endpointString = "/" + endpointString
        }
        
        urlString += endpointString
        return URL(string: urlString)
    }
}

struct PresetCard: View {
    var preset: Preset
    var loadPreset: () -> Void
    var accentGradient: LinearGradient
    
    @Environment(\.colorScheme) private var colorScheme
    
    private func methodColor(for method: String) -> Color {
        switch method {
            case "GET":    return Color.blue
            case "POST":   return Color.green
            case "PUT":    return Color.orange
            case "DELETE": return Color.red
            default:       return Color.blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(preset.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Method Badge
                Text(preset.method)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(methodColor(for: preset.method).opacity(0.2))
                    )
                    .foregroundColor(methodColor(for: preset.method))
            }
            
            // URL Details
            VStack(alignment: .leading, spacing: 4) {
                // Protocol and host
                HStack {
                    Text(preset.protocolType)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text("://")
                        .foregroundColor(.secondary)
                    Text(preset.ipAddress)
                        .foregroundColor(.secondary)
                    if !preset.port.isEmpty {
                        Text(":")
                            .foregroundColor(.secondary)
                        Text(preset.port)
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(.subheadline, design: .monospaced))
                
                // Endpoint
                Text(preset.endpoint)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Body parameters summary (if any)
            if !preset.keyValues.isEmpty && preset.keyValues.first?.key.isEmpty == false {
                HStack {
                    Image(systemName: "doc.plaintext")
                        .foregroundColor(.secondary)
                    Text("\(preset.keyValues.filter { !$0.key.isEmpty }.count) parameters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Execute button
            Button(action: loadPreset) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Execute")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(accentGradient)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .accessibilityLabel("Execute preset \(preset.name)")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
    }
}
struct InfoView: View {
    @Environment(\.openURL) private var openURL
    var accentGradient: LinearGradient
    var backgroundGradient: LinearGradient
    @Environment(\.colorScheme) private var colorScheme

    let infoItems = [
        ("Version", "1.0.0"),
        ("Made by", "Velyzo"),
        ("Website", "https://velyzo.de"),
        ("GitHub", "https://github.com/velyzo.de"),
        ("Contact", "mail@velyzo.de")
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // App logo and version
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(accentGradient)
                                    .frame(width: 100, height: 100)
                                    .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                                
                                Image(systemName: "globe.americas.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                                    .foregroundColor(.white)
                            }
                            
                            Text("Connecto")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            
                            Text("Version 1.0.0")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                        
                        // Info card
                        VStack(spacing: 0) {
                            ForEach(infoItems.dropFirst(), id: \.0) { item in
                                InfoRow(title: item.0, value: item.1)
                                
                                if item.0 != infoItems.last?.0 {
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                        )
                        .padding(.horizontal)
                        
                        // Legal section
                        VStack(spacing: 16) {
                            Text("Legal")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            
                            NavigationLink(destination: PrivacyPolicyView(backgroundGradient: backgroundGradient)) {
                                HStack {
                                    Image(systemName: "hand.raised.fill")
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.blue)
                                    
                                    Text("Privacy Policy")
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            NavigationLink(destination: TermsOfUseView(backgroundGradient: backgroundGradient)) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .frame(width: 24, height: 24)
                                        .foregroundColor(.blue)
                                    
                                    Text("Terms of Use")
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal)
                        
                        // About / Copyright
                        Text("© 2025 Velyzo. All rights reserved.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Info")
            .navigationBarHidden(true)
        }
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
    var backgroundGradient: LinearGradient
    
    var body: some View {
        ZStack {
            backgroundGradient
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
    var backgroundGradient: LinearGradient
    
    var body: some View {
        ZStack {
            backgroundGradient
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

struct ResponseView: View {
    @Binding var responseText: String
    @Binding var isVisible: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Response")
                    .font(.headline)
                    .foregroundColor(.primary)
                
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
            .background(
                colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white
            )
            
            // Divider
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.2))
            
            // Content
            ScrollView {
                Text(responseText)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Response content")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .frame(maxWidth: .infinity, maxHeight: 500)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(), value: isVisible)
    }
}

#Preview {
    ContentView()
}

