import SwiftUI
import WatchKit
internal import Combine

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

    init() {
        loadPresets()
    }

    func savePresets() {
        if let encoded = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(encoded, forKey: presetsKey)
        }
    }

    func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = decoded
        }
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
    @StateObject private var presetViewModel = PresetViewModel()

    var body: some View {
        TabView {
            // Home Tab
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            // Tool Tab
            ToolView(presetViewModel: presetViewModel)
                .tabItem {
                    Label("Tool", systemImage: "hammer.fill")
                }

            // Presets Tab
            PresetsView(presetViewModel: presetViewModel)
                .tabItem {
                    Label("Presets", systemImage: "star.fill")
                }

            // Info Tab
            InfoView()
                .tabItem {
                    Label("Info", systemImage: "info.circle.fill")
                }
        }
        .accentColor(.blue)
    }
}

struct HomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App logo and title
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]),
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 70, height: 70)

                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
                .padding(.top, 10)

                Text("Connecto")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Network Tool")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.vertical, 5)

                // Features
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "network", text: "Make HTTP requests")
                    FeatureRow(icon: "star", text: "Save presets")
                    FeatureRow(icon: "gear", text: "Custom parameters")
                    FeatureRow(icon: "bolt", text: "Quick responses")
                }
                .padding(.horizontal)

                Text("🌐 Tap the Tool tab to get started with your first request.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding()
            }
            .padding()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .lineLimit(1)
        }
    }
}

struct ToolView: View {
    @ObservedObject var presetViewModel: PresetViewModel
    
    @State private var selectedProtocol: String = "http"
    @State private var ipAddress: String = ""
    @State private var port: String = ""
    @State private var endpoint: String = ""
    @State private var method: String = "GET"
    @State private var keyValues: [KeyValue] = [KeyValue()]
    @State private var responseText: String = ""
    @State private var showResponse = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Protocol selector
                Picker("Protocol", selection: $selectedProtocol) {
                    Text("HTTP").tag("http")
                    Text("HTTPS").tag("https")
                }
                .pickerStyle(.wheel)
                
                // Host/IP input
                VStack(alignment: .leading) {
                    Text("Host/IP")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("example.com", text: $ipAddress)
                        .textFieldStyle(.plain)
                }
                
                // Port input
                VStack(alignment: .leading) {
                    Text("Port (Optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("8080", text: $port)
                        .textFieldStyle(.plain)
                }
                
                // Endpoint input
                VStack(alignment: .leading) {
                    Text("Endpoint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("/api/resource", text: $endpoint)
                        .textFieldStyle(.plain)
                }
                
                // Method selector
                VStack(alignment: .leading) {
                    Text("Method")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Method", selection: $method) {
                        Text("GET").tag("GET")
                        Text("POST").tag("POST")
                        Text("PUT").tag("PUT")
                        Text("DELETE").tag("DELETE")
                    }
                    .pickerStyle(.wheel)
                }
                
                // Body parameters for POST/PUT
                if method == "POST" || method == "PUT" {
                    VStack(alignment: .leading) {
                        Text("Parameters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach($keyValues) { $keyValue in
                            HStack {
                                TextField("Key", text: $keyValue.key)
                                    .textFieldStyle(.plain)
                                    .frame(width: 70)
                                
                                TextField("Value", text: $keyValue.value)
                                    .textFieldStyle(.plain)
                            }
                        }
                        
                        Button(action: {
                            keyValues.append(KeyValue())
                        }) {
                            Label("Add", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .padding(.top, 2)
                    }
                }
                
                // Send button
                Button(action: sendRequest) {
                    Text("Send Request")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                
                // Save button
                Button(action: savePreset) {
                    Label("Save Preset", systemImage: "star")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                // Response section
                if showResponse {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Response")
                            .font(.headline)
                            .padding(.top, 4)
                        
                        Text(responseText)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 5)
        }
    }
    
    private func sendRequest() {
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    responseText = "Error: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    responseText = "Status: \(httpResponse.statusCode)"
                    if let data = data, let dataString = String(data: data, encoding: .utf8) {
                        responseText += "\n\n" + dataString
                    }
                } else if let data = data {
                    responseText = String(data: data, encoding: .utf8) ?? "Invalid response data"
                } else {
                    responseText = "Unknown error occurred"
                }
                showResponse = true
            }
        }.resume()
    }
    
    private func constructURL() -> URL? {
        guard !ipAddress.isEmpty else { return nil }
        
        var urlString = "\(selectedProtocol)://\(ipAddress)"
        
        if !port.isEmpty {
            urlString += ":\(port)"
        }
        
        // Ensure endpoint starts with "/"
        var endpointString = endpoint
        if !endpointString.isEmpty && !endpointString.hasPrefix("/") {
            endpointString = "/" + endpointString
        }
        
        urlString += endpointString
        return URL(string: urlString)
    }
    
    private func savePreset() {
        // Create formatter for time
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        let preset = Preset(
            id: UUID(),
            name: "Preset \(formatter.string(from: Date()))",
            protocolType: selectedProtocol,
            ipAddress: ipAddress,
            port: port,
            endpoint: endpoint,
            method: method,
            keyValues: keyValues
        )
        
        presetViewModel.addPreset(preset)
        
        // Provide feedback
        WKInterfaceDevice.current().play(.success)
    }
}

struct PresetsView: View {
    @ObservedObject var presetViewModel: PresetViewModel
    @State private var selectedPreset: Preset?
    @State private var showingDetail = false
    
    var body: some View {
        List {
            if presetViewModel.presets.isEmpty {
                Text("No presets saved")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(presetViewModel.presets) { preset in
                    Button {
                        selectedPreset = preset
                        showingDetail = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(preset.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Text("\(preset.method) \(preset.endpoint)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color.gray.opacity(0.1))
                }
                .onDelete(perform: presetViewModel.removePreset)
            }
        }
        .listStyle(.elliptical)
        .sheet(isPresented: $showingDetail, content: {
            if let preset = selectedPreset {
                PresetDetailView(preset: preset)
            }
        })
    }
}

struct PresetDetailView: View {
    let preset: Preset
    @State private var isLoading = false
    @State private var response = ""
    @State private var showResponse = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Preset name and method
                HStack {
                    Text(preset.name)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(preset.method)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(methodColor.opacity(0.2))
                        )
                        .foregroundColor(methodColor)
                }
                
                Divider()
                
                // URL
                Group {
                    Text("URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(preset.protocolType)://\(preset.ipAddress)\(preset.port.isEmpty ? "" : ":\(preset.port)")\(preset.endpoint)")
                        .font(.caption2)
                        .lineLimit(2)
                }
                
                // Parameters if any
                if !preset.keyValues.isEmpty && preset.keyValues.first?.key.isEmpty == false {
                    Divider()
                    
                    Text("Parameters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(preset.keyValues) { param in
                        if !param.key.isEmpty {
                            HStack {
                                Text(param.key)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text(param.value)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Execute button
                Button(action: executePreset) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Execute")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                .padding(.top, 8)
                
                // Response display
                if showResponse {
                    VStack(alignment: .leading) {
                        Text("Response")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(response)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }
    
    private var methodColor: Color {
        switch preset.method {
            case "GET":    return .blue
            case "POST":   return .green
            case "PUT":    return .orange
            case "DELETE": return .red
            default:       return .blue
        }
    }
    
    func executePreset() {
        isLoading = true
        showResponse = false
        
        guard let url = constructURL() else {
            response = "Invalid URL"
            showResponse = true
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = preset.method
        
        if preset.method == "POST" || preset.method == "PUT" {
            let jsonBody = preset.keyValues.reduce(into: [String: String]()) { result, pair in
                if !pair.key.isEmpty {
                    result[pair.key] = pair.value
                }
            }
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonBody, options: []) {
                request.httpBody = jsonData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        URLSession.shared.dataTask(with: request) { data, httpResponse, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    response = "Error: \(error.localizedDescription)"
                } else if let httpResponse = httpResponse as? HTTPURLResponse {
                    response = "Status: \(httpResponse.statusCode)"
                    if let data = data, let dataString = String(data: data, encoding: .utf8) {
                        response += "\n\n" + dataString
                    }
                } else if let data = data {
                    response = String(data: data, encoding: .utf8) ?? "Invalid response data"
                } else {
                    response = "Unknown error occurred"
                }
                
                showResponse = true
            }
        }.resume()
    }
    
    private func constructURL() -> URL? {
        var urlString = "\(preset.protocolType)://\(preset.ipAddress)"
        
        if !preset.port.isEmpty {
            urlString += ":\(preset.port)"
        }
        
        // Ensure endpoint starts with "/"
        var endpointString = preset.endpoint
        if !endpointString.isEmpty && !endpointString.hasPrefix("/") {
            endpointString = "/" + endpointString
        }
        
        urlString += endpointString
        return URL(string: urlString)
    }
}
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct InfoView: View {
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfUse = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App logo and version
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]),
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }
                
                Text("Connecto")
                    .font(.headline)
                
                Text("Version 3.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                // Info items
                VStack(spacing: 8) {
                    InfoItem(title: "Made by", value: "Velyzo")
                    InfoItem(title: "Email", value: "mail@velyzo.de")
                    InfoItem(title: "Website", value: "velyzo.de")
                }
                
                Divider()
                    .padding(.vertical, 8)
                
                // Legal links
                VStack(spacing: 10) {
                    Button(action: { showingPrivacyPolicy = true }) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.blue)
                            Text("Privacy Policy")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { showingTermsOfUse = true }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                            Text("Terms of Use")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                
                Text("© 2025 Velyzo")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showingTermsOfUse) {
            TermsOfUseView()
        }
    }
}

struct InfoItem: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy Policy")
                    .font(.headline)
                    .padding(.bottom, 6)
                
                Group {
                    Text("Last Updated: July 2, 2025")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("The app stores all data locally and doesn't collect any personal information. Network requests are sent directly to your specified endpoints.")
                        .font(.caption2)
                    
                    Text("No analytics or crash reporting is used. For more information, contact: velis.help@gmail.com")
                        .font(.caption2)
                }
            }
            .padding()
        }
    }
}

struct TermsOfUseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Terms of Use")
                    .font(.headline)
                    .padding(.bottom, 6)
                
                Group {
                    Text("Last Updated: July 2, 2025")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("By using Connecto, you agree not to use the app for unlawful purposes. The app is provided 'as is' without warranty.")
                        .font(.caption2)
                    
                    Text("The developer assumes no liability for damages resulting from use of the app. These Terms are governed by the laws of Germany.")
                        .font(.caption2)
                }
            }
            .padding()
        }
    }
}

