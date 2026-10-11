//
//  PlaceViews.swift
//  ShutterManager
//
//  Choosing where to plan for: your current location, a saved place, or a place picked on the
//  map, found by search, or typed as coordinates.
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

extension CLLocationCoordinate2D {
    init(_ coordinate: GeoCoordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension GeoCoordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/// The place row in a planner: shows the chosen place and opens `PlaceSelectionView` in a sheet.
///
/// A sheet, not a push: choosing a place in the map picker, which sits on top of the selection
/// list, has to close both. Dismissing the sheet does that in one step; popping a pushed list
/// from underneath the picker didn't.
struct PlaceRow: View {
    @Binding var place: PlaceValue?
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            LabeledContent {
                if let place {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(place.name)
                        Text(place.timeZone.identifier).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Choose").foregroundStyle(Color.accentColor)
                }
            } label: {
                Label("Place", systemImage: "mappin.and.ellipse")
            }
        }
        .tint(.primary)
        .accessibilityIdentifier("placeRow")
        .sheet(isPresented: $choosing) {
            NavigationStack {
                PlaceSelectionView(selection: $place)
            }
        }
    }
}

/// Current location, saved places, or a new place from the map. Shown as the root of a sheet:
/// every way of choosing dismisses the sheet.
struct PlaceSelectionView: View {
    @Binding var selection: PlaceValue?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPlace.name) private var places: [SavedPlace]
    @ObservedObject private var location = LocationService.shared
    @State private var awaitingLocation = false

    var body: some View {
        List {
            Section {
                Button {
                    awaitingLocation = true
                    location.requestLocation()
                } label: {
                    HStack {
                        Label("Use My Location", systemImage: "location")
                        Spacer()
                        if location.isLocating { ProgressView() }
                    }
                }
                .accessibilityIdentifier("useMyLocationButton")
                if let message = location.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink {
                    PlacePickerView(initial: selection) { picked in
                        selection = picked
                        dismiss()
                    }
                } label: {
                    Label("Find on the Map", systemImage: "map")
                }
                .accessibilityIdentifier("findOnMapButton")
            } footer: {
                Text("Search, tap the map, or type coordinates.")
            }

            if !places.isEmpty {
                Section("My Places") {
                    ForEach(places) { place in
                        Button {
                            selection = place.value
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).foregroundStyle(.primary)
                                    Text(place.value.coordinateText).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection?.savedPlaceID == place.id {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onChange(of: location.location) { _, newLocation in
            guard awaitingLocation, let newLocation else { return }
            awaitingLocation = false
            selection = PlaceValue(name: "Current Location", coordinate: GeoCoordinate(newLocation.coordinate),
                                   timeZoneIdentifier: TimeZone.current.identifier)
            dismiss()
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            if selection?.savedPlaceID == places[index].id { selection?.savedPlaceID = nil }
            context.delete(places[index])
        }
        if !context.saveOrLog() { context.rollback() }
    }
}

/// A map to search, tap or type a place on, with the option to save it.
struct PlacePickerView: View {
    let initial: PlaceValue?
    let onPick: (PlaceValue) -> Void

    @Environment(\.modelContext) private var context
    @State private var camera: MapCameraPosition
    @State private var picked: GeoCoordinate?
    @State private var name = ""
    @State private var timeZoneIdentifier = TimeZone.current.identifier
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var saveToPlaces = true
    @State private var saveFailed = false

    init(initial: PlaceValue?, onPick: @escaping (PlaceValue) -> Void) {
        self.initial = initial
        self.onPick = onPick
        if let initial {
            _camera = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(initial.coordinate),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))))
        } else {
            _camera = State(initialValue: .automatic)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Search for a place", text: $searchText)
                        .submitLabel(.search)
                        .onSubmit(search)
                        .accessibilityIdentifier("placeSearchField")
                    if isSearching { ProgressView() }
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        choose(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Place").foregroundStyle(.primary)
                            if let address = item.placemark.title {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                MapReader { proxy in
                    Map(position: $camera) {
                        if let picked {
                            Marker(name.isEmpty ? "Here" : name, coordinate: CLLocationCoordinate2D(picked))
                        }
                    }
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            pick(GeoCoordinate(coordinate), lookUpName: true)
                        }
                    }
                }
                .frame(height: 280)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Tap the map to drop a pin.")
            }

            Section("Coordinates") {
                TextField("Latitude (−90 to 90)", text: $latitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("latitudeField")
                TextField("Longitude (−180 to 180)", text: $longitudeText)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("longitudeField")
                Button("Use These Coordinates") {
                    if let typed = typedCoordinate { pick(typed, lookUpName: true) }
                }
                .disabled(typedCoordinate == nil)
                .accessibilityIdentifier("useCoordinatesButton")
            }

            if picked != nil {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("placeNameField")
                    NavigationLink {
                        TimeZonePicker(identifier: $timeZoneIdentifier)
                    } label: {
                        LabeledContent("Time Zone", value: timeZoneIdentifier)
                    }
                    Toggle("Save to My Places", isOn: $saveToPlaces)
                }
            }
        }
        .navigationTitle("Find a Place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use", action: use)
                    .disabled(picked == nil)
                    .accessibilityIdentifier("usePlaceButton")
            }
        }
        .persistenceErrorAlert(isPresented: $saveFailed)
        .onAppear {
            guard let initial, picked == nil else { return }
            picked = initial.coordinate
            name = initial.name == "Current Location" ? "" : initial.name
            timeZoneIdentifier = initial.timeZone.identifier
            latitudeText = String(format: "%.5f", initial.coordinate.latitude)
            longitudeText = String(format: "%.5f", initial.coordinate.longitude)
        }
    }

    private var typedCoordinate: GeoCoordinate? {
        guard let latitude = Double(localizedInput: latitudeText.trimmingCharacters(in: .whitespaces)),
              let longitude = Double(localizedInput: longitudeText.trimmingCharacters(in: .whitespaces)) else { return nil }
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValid ? coordinate : nil
    }

    private func pick(_ coordinate: GeoCoordinate, lookUpName: Bool) {
        picked = coordinate
        latitudeText = String(format: "%.5f", coordinate.latitude)
        longitudeText = String(format: "%.5f", coordinate.longitude)
        camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(coordinate),
                                            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)))
        guard lookUpName else { return }
        // The name and time zone come from Apple's geocoder, when the network allows.
        Task {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
                  picked == coordinate else { return }
            if name.isEmpty { name = placemark.name ?? placemark.locality ?? "" }
            if let zone = placemark.timeZone { timeZoneIdentifier = zone.identifier }
        }
    }

    private func choose(_ item: MKMapItem) {
        name = item.name ?? ""
        if let zone = item.timeZone { timeZoneIdentifier = zone.identifier }
        pick(GeoCoordinate(item.placemark.coordinate), lookUpName: item.timeZone == nil)
        results = []
    }

    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            results = Array((response?.mapItems ?? []).prefix(8))
            isSearching = false
        }
    }

    private func use() {
        guard let picked else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = PlaceValue(name: trimmed.isEmpty ? PlaceValue.coordinateText(picked) : trimmed,
                               coordinate: picked, timeZoneIdentifier: timeZoneIdentifier)
        if saveToPlaces {
            let place = SavedPlace(name: value.name, coordinate: picked, timeZoneIdentifier: timeZoneIdentifier)
            context.insert(place)
            guard context.saveOrLog() else {
                context.rollback()
                saveFailed = true
                return
            }
            value.savedPlaceID = place.id
        }
        onPick(value)
    }
}

/// Every time zone the system knows, searchable.
struct TimeZonePicker: View {
    @Binding var identifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let zones = TimeZone.knownTimeZoneIdentifiers.filter {
            query.isEmpty || $0.lowercased().replacingOccurrences(of: "_", with: " ").contains(query)
        }
        List(zones, id: \.self) { zone in
            Button {
                identifier = zone
                dismiss()
            } label: {
                HStack {
                    Text(zone.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.primary)
                    Spacer()
                    if zone == identifier {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .searchable(text: $searchText)
        .navigationTitle("Time Zone")
        .navigationBarTitleDisplayMode(.inline)
    }
}
