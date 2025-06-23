import Combine
import SwiftUI
import WatchConnectivity

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

class PresetViewModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var presets: [Preset] = []
    private let presetsKey = "SavedPresets"
    private var refreshTimer: Timer?
    @AppStorage("syncEnabled") var syncEnabled = true
    private var session: WCSession?
    
    override init() {
        super.init()
        loadPresets()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshPresetsPeriodically()
        }
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetsKey)
            sendPresetsToWatch()
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
    
    func sendPresetsToWatch() {
        guard syncEnabled else { return }
        guard let session = session else { return }
        do {
            let data = try JSONEncoder().encode(presets)
            let dict = ["presets": data]
            try session.updateApplicationContext(dict)
        } catch {
            // Handle error silently or log it
        }
    }
    
    func sendTestConnectionToWatch() {
        guard let session = session, session.isReachable else { return }
        session.sendMessage(["testConnection": true], replyHandler: nil, errorHandler: nil)
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // No action needed here
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
    @StateObject private var presetViewModel = PresetViewModel()
    @AppStorage("syncEnabled") var syncEnabled = true

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
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
                presetViewModel: presetViewModel
            )
            .tabItem {
                Label("Tool", systemImage: "wrench")
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
                showResponse: $showResponse
            )
            .tabItem {
                Label("Presets", systemImage: "list.bullet")
            }

            InfoView()
                .tabItem {
                    Label("Info", systemImage: "info.circle")
                }
        }
    }
}

struct HomeView: View {
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "network.globe")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundColor(.blue)
                        .shadow(radius: 8)
                    
                    Text("Welcome to Connecto")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                            Text("Make network requests easily")
                                .fontWeight(.medium)
                        }
                        HStack {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(.purple)
                            Text("Save and manage your presets")
                                .fontWeight(.medium)
                        }
                        HStack {
                            Image(systemName: "gearshape")
                                .foregroundColor(.green)
                            Text("Configure HTTP methods & headers")
                                .fontWeight(.medium)
                        }
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                            Text("Quick and responsive UI")
                                .fontWeight(.medium)
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 40)
                    
                    Text("💡 Tip: Use the 'Tool' tab to create and send your first network request!")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 16)
                }
                .padding()
            }
        }
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
    @AppStorage("syncEnabled") var syncEnabled = true

    @ObservedObject var presetViewModel: PresetViewModel
    @State private var isProtocolPickerPresented = false
    @State private var isMethodPickerPresented = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Tool")
                    .font(.title)
                    .padding()

                // Connection Settings Group
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connection Settings")
                        .font(.headline)
                        .padding(.bottom, 4)

                    // Protocol Picker
                    Button(action: { isProtocolPickerPresented = true }) {
                        HStack {
                            Text("Protocol: \(selectedProtocol.uppercased())")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .actionSheet(isPresented: $isProtocolPickerPresented) {
                        ActionSheet(
                            title: Text("Select Protocol"),
                            buttons: [
                                .default(Text("HTTP")) { selectedProtocol = "http" },
                                .default(Text("HTTPS")) { selectedProtocol = "https" },
                                .cancel()
                            ]
                        )
                    }

                    InputSection(title: "IP Address", placeholder: "e.g., 192.168.1.1", text: $ipAddress)
                        .padding(.horizontal, 8)
                    InputSection(title: "Port (Optional)", placeholder: "e.g., 8080", text: $port)
                        .padding(.horizontal, 8)
                    InputSection(title: "Endpoint", placeholder: "/api/v1/resource", text: $endpoint)
                        .padding(.horizontal, 8)

                    // Method Picker
                    Button(action: { isMethodPickerPresented = true }) {
                        HStack {
                            Text("Method: \(method)")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .actionSheet(isPresented: $isMethodPickerPresented) {
                        ActionSheet(
                            title: Text("Select HTTP Method"),
                            buttons: [
                                .default(Text("GET")) { method = "GET" },
                                .default(Text("POST")) { method = "POST" },
                                .default(Text("PUT")) { method = "PUT" },
                                .default(Text("DELETE")) { method = "DELETE" },
                                .cancel()
                            ]
                        )
                    }
                }
                .padding()
                .background(Color.white.opacity(0.7))
                .cornerRadius(15)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                .padding(.horizontal)

                // Request Body Group
                if method == "POST" || method == "PUT" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Request Body")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Request Key-Value Pairs")
                                .font(.subheadline)
                            ForEach($keyValues) { $keyValue in
                                HStack {
                                    TextField("Key", text: $keyValue.key)
                                    TextField("Value", text: $keyValue.value)
                                }
                            }
                            Button(action: { keyValues.append(KeyValue()) }) {
                                Label("Add Pair", systemImage: "plus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                    }
                    .padding()
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    .padding(.horizontal)
                }

                // Actions Group
                VStack(spacing: 16) {
                    Button(action: sendRequest) {
                        Text("Send Request")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .font(.headline)
                            .background(Color.blue)
                            .cornerRadius(15)
                    }
                    .buttonStyle(.plain)

                    Button(action: savePreset) {
                        Text("Save Preset")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .font(.headline)
                            .background(Color.green)
                            .cornerRadius(15)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        presetViewModel.sendTestConnectionToWatch()
                    }) {
                        Label("Test Connection", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .font(.headline)
                            .background(Color.orange)
                            .cornerRadius(15)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                if showResponse {
                    ResponseView(responseText: $responseText)
                        .padding(.top, 16)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    func sendRequest() {
        guard let url = constructURL() else {
            responseText = "Invalid URL"
            showResponse = true
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

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    responseText = "Error: \(error.localizedDescription)"
                } else if let data = data {
                    responseText = String(data: data, encoding: .utf8) ?? "Invalid response data"
                } else {
                    responseText = "Unknown error occurred"
                }
                showResponse = true
            }
        }.resume()
    }

    func constructURL() -> URL? {
        guard !ipAddress.isEmpty else {
            return nil
        }

        var urlString = "\(selectedProtocol)://\(ipAddress)"
        if !port.isEmpty {
            urlString += ":\(port)"
        }
        urlString += endpoint
        return URL(string: urlString)
    }

    func savePreset() {
        let newPreset = Preset(
            id: UUID(),
            name: "Preset \(Date())",
            protocolType: selectedProtocol,
            ipAddress: ipAddress,
            port: port,
            endpoint: endpoint,
            method: method,
            keyValues: keyValues
        )
        presetViewModel.addPreset(newPreset)
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

    var body: some View {
        NavigationView {
            List {
                ForEach(presetViewModel.presets) { preset in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(preset.name)
                                .font(.headline)
                            Text("\(preset.protocolType)://\(preset.ipAddress):\(preset.port)\(preset.endpoint)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Button("Run") {
                            loadPreset(preset)
                            sendRequest()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .onDelete(perform: presetViewModel.removePreset)
            }
            .navigationTitle("Presets")
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

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    responseText = "Error: \(error.localizedDescription)"
                } else if let data = data {
                    responseText = String(data: data, encoding: .utf8) ?? "Invalid response data"
                } else {
                    responseText = "Unknown error occurred"
                }
                showResponse = true
            }
        }.resume()
    }

    func constructURL() -> URL? {
        guard !ipAddress.isEmpty else {
            return nil
        }

        var urlString = "\(selectedProtocol)://\(ipAddress)"
        if !port.isEmpty {
            urlString += ":\(port)"
        }
        urlString += endpoint
        return URL(string: urlString)
    }
}

struct InfoView: View {
    @AppStorage("syncEnabled") var syncEnabled = true

    let infoItems = [
        ("Version", "v3.0.0 EXTENDED"),
        ("Made by", "Velis"),
        ("Website", "https://velis.me"),
        ("GitHub", "https://github.com/veliscore"),
        ("Discord", "http://discord.velis.me"),
        ("Contact", "velis.help@gmail.com")
    ]
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Sync presets between Watch & iPhone", isOn: $syncEnabled)
                    Text("Keep this ON to sync your saved presets between devices (recommended)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                
                Section {
                    ForEach(infoItems, id: \.0) { item in
                        HStack {
                            Text(item.0)
                                .fontWeight(.bold)
                            Spacer()
                            Text(item.1)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Info")
        }
    }
}

struct ResponseView: View {
    @Binding var responseText: String

    var body: some View {
        ScrollView {
            Text(responseText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
}

struct InputSection: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            TextField(placeholder, text: $text)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
