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
                isOutputPopupVisible: $isOutputPopupVisible,
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
                showResponse: $showResponse,
                isOutputPopupVisible: $isOutputPopupVisible
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
                    Image(systemName: "globe")
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
    @Binding var isOutputPopupVisible: Bool

    @ObservedObject var presetViewModel: PresetViewModel
    @State private var isProtocolPickerPresented = false
    @State private var isMethodPickerPresented = false

    var body: some View {
        #if os(iOS)
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Text("Tool")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)

                VStack(spacing: 20) {
                    // Protocol Picker with icon
                    Button(action: { isProtocolPickerPresented = true }) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Protocol: \(selectedProtocol.uppercased())")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.white.opacity(0.3))
                        .cornerRadius(10)
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
                    
                    InputSection(title: "IP Address", placeholder: "e.g., 192.168.1.1", text: $ipAddress, iconName: "network")
                    InputSection(title: "Port (Optional)", placeholder: "e.g., 8080", text: $port, iconName: "number")
                    InputSection(title: "Endpoint", placeholder: "/api/v1/resource", text: $endpoint, iconName: "link")
                    
                    Button(action: { isMethodPickerPresented = true }) {
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            Text("Method: \(method)")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.white.opacity(0.3))
                        .cornerRadius(10)
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
                
                if method == "POST" || method == "PUT" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Request Key-Value Pairs")
                            .font(.headline)
                        
                        ForEach($keyValues) { $keyValue in
                            HStack {
                                TextField("Key", text: $keyValue.key)
                                    .padding(8)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke())
                                TextField("Value", text: $keyValue.value)
                                    .padding(8)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke())
                            }
                        }
                        Button(action: { keyValues.append(KeyValue()) }) {
                            Label("Add Pair", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                }

                VStack(spacing: 16) {
                    // Send Request Button with gradient
                    Button(action: sendRequest) {
                        Text("Send Request")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .font(.headline)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]),
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .cornerRadius(20)
                            .shadow(color: Color.blue.opacity(0.5), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    
                    // Save Preset Button with gradient
                    Button(action: savePreset) {
                        Text("Save Preset")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .font(.headline)
                            .background(
                                LinearGradient(gradient: Gradient(colors: [Color.green, Color.blue]),
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .cornerRadius(20)
                            .shadow(color: Color.green.opacity(0.5), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)

                Spacer()
            }
            .padding()
            .cornerRadius(25)
            .padding()
            
            if isOutputPopupVisible {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                    .zIndex(1)
                ResponseView(responseText: $responseText, isVisible: $isOutputPopupVisible)
                    .zIndex(2)
            }
        }
        #else
        ScrollView {
            VStack(spacing: 16) {
                Text("Tool")
                    .font(.title)
                    .padding()

                // Protocol Picker
                Button(action: { isProtocolPickerPresented = true }) {
                    HStack {
                        Text("Protocol: \(selectedProtocol.uppercased())")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding()
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
                InputSection(title: "Port (Optional)", placeholder: "e.g., 8080", text: $port)
                InputSection(title: "Endpoint", placeholder: "/api/v1/resource", text: $endpoint)

                // Method Picker
                Button(action: { isMethodPickerPresented = true }) {
                    HStack {
                        Text("Method: \(method)")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding()
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
                
                if method == "POST" || method == "PUT" {
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
                }

                // Send Request Button
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

                if showResponse {
                    ResponseView(responseText: $responseText, isVisible: $isOutputPopupVisible)
                        .padding(.top, 16)
                }
            }
            .padding()
        }
        #endif
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
                isOutputPopupVisible = true
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

struct InputSection: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var iconName: String? = nil

    var body: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .foregroundColor(.blue)
                        .frame(width: 24)
                }
                TextField(placeholder, text: $text)
                    .padding(10)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        #else
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            TextField(placeholder, text: $text)
        }
        #endif
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

    var body: some View {
        NavigationView {
            ZStack {
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
                if isOutputPopupVisible {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .transition(.opacity)
                        .zIndex(1)
                    ResponseView(responseText: $responseText, isVisible: $isOutputPopupVisible)
                        .zIndex(2)
                }
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
                isOutputPopupVisible = true
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
    @Environment(\.openURL) private var openURL

    let infoItems = [
        ("Version", "v3.0.0 EXTENDED (only IOS)"),
        ("Made by", "Velyzo"),
        ("Website", "https://velyzo.de"),
        ("GitHub", "https://github.com/velyzo.de"),
        ("Contact", "mail@velyzo.de")
    ]
    
    var body: some View {
        NavigationView {
            List {
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
                
                Section(header: Text("Legal")) {
                    NavigationLink(destination: PrivacyPolicyView()) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.blue)
                            Text("Privacy Policy")
                        }
                    }
                    
                    NavigationLink(destination: TermsOfUseView()) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                            Text("Terms of Use")
                        }
                    }
                }
            }
            .navigationTitle("Info")
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 10)
                
                Group {
                    Text("Last updated: July 2, 2025")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("1. Introduction")
                        .font(.headline)
                    
                    Text("This Privacy Policy informs you about the nature, scope, and purpose of the collection and use of personal data by the Connecto App.")
                    
                    Text("2. Responsible Person")
                        .font(.headline)
                    
                    Text("The person responsible under data protection laws is:\n\nDevin Oldenburg\nEmail:mustang.oberhalb.7a@icloud.com \nWebsite: https://velyzo.de")
                    
                    Text("3. Data Collection in the App")
                        .font(.headline)
                    
                    Text("The Connecto App stores all data locally on your device. We do not collect, store, or transfer any personal data to our servers or third parties. The network configurations and presets you enter are stored exclusively on your device in the UserDefaults database.")
                }
                
                Group {
                    Text("4. Network Requests")
                        .font(.headline)
                    
                    Text("The app allows you to send HTTP requests to self-defined endpoints. These requests are sent directly from your device to your specified target endpoints. We have no access to the contents of these requests or their responses.")
                    
                    Text("5. Permissions")
                        .font(.headline)
                    
                    Text("The app needs access to the internet to execute the HTTP requests you configure. No additional permissions are required or requested.")
                    
                    Text("6. Analytics and Crash Reporting")
                        .font(.headline)
                    
                    Text("The app does not use any analytics or crash reporting tools and does not collect usage data.")
                    
                    Text("7. Changes to this Privacy Policy")
                        .font(.headline)
                    
                    Text("We reserve the right to modify this Privacy Policy to ensure it always complies with current legal requirements or to implement changes to our services in the Privacy Policy, e.g., when introducing new features. The new Privacy Policy will then apply to your subsequent visits.")
                }
                
                Group {
                    Text("8. Contact")
                        .font(.headline)
                    
                    Text("If you have questions about the collection, processing, or use of your personal data, for information, correction, blocking, or deletion of data, please contact:\n\nEmail: velis.help@gmail.com")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}

struct TermsOfUseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Terms of Use")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 10)
                
                Group {
                    Text("Last updated: July 2, 2025")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("1. Acceptance of Terms of Use")
                        .font(.headline)
                    
                    Text("By using the Connecto App, you accept these Terms of Use in full. If you disagree with these terms, you must not use the app.")
                    
                    Text("2. Description of Services")
                        .font(.headline)
                    
                    Text("Connecto is an app that allows you to send and manage HTTP requests. The app enables configuration and sending of HTTP requests to any endpoint.")
                    
                    Text("3. Usage Restrictions")
                        .font(.headline)
                    
                    Text("You agree not to use the app for unlawful purposes or to infringe upon the rights of third parties. Use of the app is at your own risk.")
                }
                
                Group {
                    Text("4. Limitation of Liability")
                        .font(.headline)
                    
                    Text("The app is provided \"as is\" and \"as available\" without any express or implied warranty. The developer assumes no liability for direct, indirect, incidental, or consequential damages resulting from the use of the app.")
                    
                    Text("5. Changes to the Terms of Use")
                        .font(.headline)
                    
                    Text("The developer reserves the right to change these Terms of Use at any time. Continued use of the app after such changes constitutes your consent to the modified terms.")
                    
                    Text("6. Applicable Law")
                        .font(.headline)
                    
                    Text("These Terms of Use are governed by the laws of the Federal Republic of Germany.")
                }
            }
            .padding()
        }
        .navigationTitle("Terms of Use")
    }
}

struct ResponseView: View {
    @Binding var responseText: String
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            ScrollView {
                Text(responseText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .shadow(radius: 20)
        )
        .padding(40)
        .transition(.scale.combined(with: .opacity))
        .animation(.easeInOut, value: isVisible)
    }
}

#Preview {
    ContentView()
}
