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

    init() {
        loadPresets()
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
        ScrollView {
            VStack(spacing: 16) {
                Text("Welcome to Connecto")
                    .font(.title)
                    .padding()

                Text("This is the home page. Use the 'Tool' tab to make network requests and explore other features.")
                    .padding()

                Spacer()
            }
            .padding()
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

    @ObservedObject var presetViewModel: PresetViewModel
    @State private var isProtocolPickerPresented = false
    @State private var isMethodPickerPresented = false

    var body: some View {
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
                    ResponseView(responseText: $responseText)
                        .padding(.top, 16)
                }
            }
            .padding()
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
    let infoItems = [
        ("Version", "1.0"),
        ("Made by", "Eldritchy"),
        ("Contact", "eldritchy.help@gmail.com")
    ]
    
    var body: some View {
        NavigationView {
            List(infoItems, id: \.0) { item in
                HStack {
                    Text(item.0)
                        .fontWeight(.bold)
                    Spacer()
                    Text(item.1)
                        .foregroundColor(.gray)
                }
                .padding()
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

