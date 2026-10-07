import SwiftUI

struct WeatherLocationControls: View {
    var compact = false
    @EnvironmentObject private var model: AppModel
    @State private var choosingFixed = false
    @State private var showingPlaces = false
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var picturePlace: WeatherPlace?
    @FocusState private var searchFocused: Bool

    private var isFixed: Bool { choosingFixed || model.settings.weatherLocation.fixedPlace != nil }
    private var originalPath: String? { model.settings.uncroppedSourcePath ?? model.settings.sourcePath }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Use weather from", selection: Binding(
                get: { isFixed },
                set: { fixed in
                    choosingFixed = fixed
                    if fixed { showingPlaces = true }
                    else { model.setWeatherLocation(.current) }
                }
            )) {
                Text("Current Location").tag(false)
                Text("Fixed Location").tag(true)
            }
            .labelsHidden().pickerStyle(.menu)
            .accessibilityLabel("Weather location")
            .help("Current Location follows your Mac. Fixed Location always uses the weather in the place you choose.")

            if isFixed {
                Button { showingPlaces = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(model.settings.weatherLocation.fixedPlace?.name ?? "Choose a place…")
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.callout)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose weather location")
                .accessibilityValue(model.settings.weatherLocation.fixedPlace?.name ?? "No fixed place chosen")
                .help("Choose a town, city, or the location saved in your picture.")
            } else {
                Text(model.weatherLocationStatus).font(.caption).foregroundStyle(.secondary)
                if compact && model.needsWeatherLocationAccess {
                    Button("Allow Location Access…") { model.refreshWeatherLocation() }
                        .buttonStyle(.borderless)
                }
            }
        }
        .popover(isPresented: $showingPlaces, arrowEdge: .trailing) { placeChooser }
        .onChange(of: showingPlaces) { _, showing in
            if !showing {
                choosingFixed = false
                stopSearch()
                query = ""
                results = []
                searchMessage = nil
            }
        }
        .task(id: originalPath) {
            picturePlace = nil
            guard let path = originalPath else { return }
            let place = await Task.detached(priority: .utility) {
                ImageStore.pictureLocation(at: URL(fileURLWithPath: path))
            }.value
            guard !Task.isCancelled, let place else { return }
            let named = await WeatherPlaceLookup.named(place)
            guard !Task.isCancelled else { return }
            picturePlace = named
        }
        .onDisappear { stopSearch() }
    }

    private var placeChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a place").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Town or city", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { findPlaces() }
                    .onChange(of: query) { _, _ in findPlaces(debounced: true) }
                    .accessibilityLabel("Search for a weather location")
                if isSearching { ProgressView().controlSize(.small).accessibilityLabel("Finding places") }
            }
            .padding(9)
            .background(.background, in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.separator, lineWidth: 1) }

            ForEach(results.prefix(5)) { place in
                Button { choose(place) } label: {
                    Label(place.name, systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Use the weather in this place. Does not create an image or change your desktop.")
            }
            if let searchMessage {
                Text(searchMessage).font(.callout).foregroundStyle(.secondary)
            }
            if let picturePlace {
                if !results.isEmpty || searchMessage != nil { Divider() }
                Button { choose(picturePlace) } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Use picture location").font(.callout)
                            Text(picturePlace.name).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Uses the GPS location saved in your original picture as a fixed weather location.")
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .onAppear { searchFocused = true }
        .onExitCommand { showingPlaces = false }
    }

    private func findPlaces(debounced: Bool = false) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        stopSearch()
        results = []
        searchMessage = nil
        guard showingPlaces, !text.isEmpty else { return }
        isSearching = true
        searchTask = Task { @MainActor in
            do {
                if debounced { try await Task.sleep(for: .milliseconds(350)) }
                let places = try await WeatherPlaceLookup.search(text)
                guard !Task.isCancelled else { return }
                results = places
                searchMessage = places.isEmpty ? "No places found. Try a town and country." : nil
            } catch {
                guard !Task.isCancelled else { return }
                searchMessage = "Places could not be loaded. Try again when you’re connected."
            }
            isSearching = false
            searchTask = nil
        }
    }

    private func choose(_ place: WeatherPlace) {
        model.setWeatherLocation(.fixed(place))
        showingPlaces = false
    }

    private func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}
