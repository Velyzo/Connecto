import SwiftUI

struct ContentView: View {
    @State private var selectedProtocol: String = "http"
    @State private var ipAddress: String = ""
    @State private var port: String = ""
    @State private var endpoint: String = ""
    @State private var method: String = "GET" // Default to GET
    @State private var responseText: String = "Response will appear here..."
    @State private var keyValues: [KeyValue] = [KeyValue()]
    @State private var isMethodPickerPresented = false
    @State private var isProtocolPickerPresented = false
    @State private var showResponse = false

    var body: some View {
        // TabView to enable swipe navigation between pages
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
                showResponse: $showResponse
            )
            .tabItem {
                Label("Tool", systemImage: "wrench")
            }

            InfoView()
                .tabItem {
                    Label("Info", systemImage: "info.circle")
                }
        }
        .navigationTitle("Connecto")
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

    @State private var isProtocolPickerPresented = false
    @State private var isMethodPickerPresented = false
    @State private var buttonScale: CGFloat = 1.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Tool")
                    .font(.title)
                    .padding()

                Button(action: {
                    isProtocolPickerPresented = true
                }) {
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

                Button(action: {
                    isMethodPickerPresented = true
                }) {
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
                        Button(action: addKeyValue) {
                            Label("Add Pair", systemImage: "plus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button(action: sendRequest) {
                    Text("Send Request")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.white)
                        .font(.headline)
                        .background(
                            LinearGradient(gradient: Gradient(colors: [Color.purple, Color.blue]), startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .cornerRadius(15)
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
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

    func addKeyValue() {
        keyValues.append(KeyValue())
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



struct InputSection: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline)
            TextField(placeholder, text: $text)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

struct ResponseView: View {
    @Binding var responseText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Response").font(.subheadline)
            ScrollView {
                Text(responseText)
                    .font(.footnote)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
        }
    }
}

struct KeyValue: Identifiable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}

#Preview {
    ContentView()
}

