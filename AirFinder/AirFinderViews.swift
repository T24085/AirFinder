import SwiftUI
import MapKit
import Combine

struct AirFinderRootView: View {
    @StateObject private var viewModel = AirFinderViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapLayer

                VStack(spacing: 12) {
                    headerCard
                    if let banner = viewModel.statusMessage {
                        InfoBanner(style: .success, message: banner) {
                            viewModel.dismissMessages()
                        }
                    }
                    if let error = viewModel.errorMessage {
                        InfoBanner(style: .error, message: error) {
                            viewModel.dismissMessages()
                        }
                    }
                    Spacer()
                }
                .padding()

                VStack {
                    Spacer()
                    bottomActionBar
                }
                .padding()
            }
            .navigationTitle("AirFinder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $viewModel.selectedSheet) { sheet in
                switch sheet {
                case .detail(let location):
                    LocationDetailSheet(
                        location: location,
                        onSuggestUpdate: {
                            viewModel.startSubmission(from: location)
                        },
                        onSubmitADifferentStop: {
                            viewModel.startSubmission()
                        },
                        openURL: openURL
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                case .submission:
                    SubmissionSheet(
                        draft: $viewModel.submissionDraft,
                        isSubmitting: viewModel.isLoading,
                        onSubmit: {
                            try await viewModel.submitCurrentDraft()
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .task {
                await viewModel.bootstrapIfNeeded()
            }
            .onReceive(viewModel.locationManager.$currentCoordinate.compactMap { $0 }) { _ in
                viewModel.locationAuthorizationChanged()
            }
            .onReceive(viewModel.locationManager.$authorizationStatus) { status in
                if status == .denied || status == .restricted {
                    viewModel.errorMessage = "Location access is off. Use search or enable location access for nearby results."
                }
            }
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.scheduleSearchRefresh()
            }
        }
    }

    private var mapLayer: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()

            ForEach(viewModel.locations) { location in
                Annotation(location.name, coordinate: location.coordinate, anchor: .bottom) {
                    let isSelected = viewModel.selectedSheet == .detail(location)

                    Button {
                        viewModel.select(location)
                    } label: {
                        LocationMarkerView(
                            location: location,
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard)
        .ignoresSafeArea()
        .onMapCameraChange(frequency: .onEnd) { context in
            viewModel.updateVisibleRegion(context.region)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AirFinder")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Free tire air on a map.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    viewModel.startSubmission()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.88), in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 8) {
                statusChip(label: viewModel.locations.count == 1 ? "1 stop" : "\(viewModel.locations.count) stops", systemImage: "map")

                if viewModel.locationManager.authorizationStatus == .authorizedAlways || viewModel.locationManager.authorizationStatus == .authorizedWhenInUse {
                    statusChip(label: "Near you", systemImage: "location.fill")
                } else {
                    statusChip(label: "Search mode", systemImage: "magnifyingglass")
                }
            }

            TextField("Search places, cities, or addresses", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.search)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 10)
        )
    }

    private func statusChip(label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(.primary)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.78))
            )
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                if let center = viewModel.currentMapCenter() {
                    viewModel.cameraPosition = .region(MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: 0.20, longitudeDelta: 0.20)
                    ))
                } else {
                    viewModel.cameraPosition = .automatic
                }
            } label: {
                Label("Recenter", systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(kind: .secondary))

            Button {
                viewModel.startSubmission()
            } label: {
                Label("Submit stop", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ActionButtonStyle(kind: .primary))
        }
    }
}

private struct LocationMarkerView: View {
    let location: AirLocation
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(location.pricingStatus.badgeText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(location.pricingStatus.tint)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )

            ZStack {
                Circle()
                    .fill(location.pricingStatus.tint)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(.white, lineWidth: 2))

                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
            }
            .shadow(color: location.pricingStatus.tint.opacity(0.35), radius: 8, x: 0, y: 6)
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

private struct LocationDetailSheet: View {
    let location: AirLocation
    let onSuggestUpdate: () -> Void
    let onSubmitADifferentStop: () -> Void
    let openURL: OpenURLAction

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(location.name)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 8) {
                                badge(text: location.pricingStatus.title, tint: location.pricingStatus.tint)
                                badge(text: location.sourceBadge, tint: .black.opacity(0.82))
                            }
                        }
                        Spacer(minLength: 8)
                        Text(location.pricingStatus.badgeText)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(location.pricingStatus.tint)
                    }

                    if let distance = location.distanceMeters {
                        Text(distanceFormatter.string(fromMeters: distance))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(title: "Address", value: location.displayAddress)
                    DetailRow(title: "Location", value: String(format: "%.5f, %.5f", location.latitude, location.longitude))
                    DetailRow(title: "Verified", value: location.lastVerifiedAt.map { dateFormatter.string(from: $0) } ?? "Not yet verified")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )

                if let notes = location.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        Text(notes)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        let query = location.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location.name
                        let url = URL(string: "http://maps.apple.com/?ll=\(location.latitude),\(location.longitude)&q=\(query)")!
                        openURL(url)
                    } label: {
                        Label("Open in Maps", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(kind: .primary))

                    Button {
                        onSuggestUpdate()
                    } label: {
                        Label("Suggest an edit", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(kind: .secondary))

                    Button {
                        onSubmitADifferentStop()
                    } label: {
                        Text("Add another stop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(kind: .tertiary))
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.93, green: 0.96, blue: 0.99)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Capsule().fill(tint))
    }
}

private struct SubmissionSheet: View {
    @Binding var draft: LocationSubmissionDraft
    let isSubmitting: Bool
    let onSubmit: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var localError: String?

    enum Field {
        case name, address, city, state, postalCode, notes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stop details") {
                    TextField("Location name", text: $draft.name)
                        .focused($focusedField, equals: .name)
                    TextField("Street address", text: $draft.addressLine1)
                        .focused($focusedField, equals: .address)
                    TextField("City", text: $draft.city)
                        .focused($focusedField, equals: .city)
                    TextField("State", text: $draft.state)
                        .focused($focusedField, equals: .state)
                    TextField("ZIP code", text: $draft.postalCode)
                        .focused($focusedField, equals: .postalCode)
                }

                Section("Pricing") {
                    Picker("Price", selection: $draft.pricingStatus) {
                        Text("Free").tag(PricingStatus.free)
                        Text("Paid").tag(PricingStatus.paid)
                        Text("Unknown").tag(PricingStatus.unknown)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Map position") {
                    if let coordinate = draft.coordinate {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Latitude: \(coordinate.latitude, specifier: "%.5f")")
                            Text("Longitude: \(coordinate.longitude, specifier: "%.5f")")
                            Text("Move the map before opening this form to change the pin position.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Choose a map location before submitting.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Helpful notes for reviewers", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                }

                if let localError {
                    Section {
                        Text(localError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Submit a stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Sending..." : "Submit") {
                        Task {
                            do {
                                localError = nil
                                try await onSubmit()
                                dismiss()
                            } catch {
                                localError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InfoBanner: View {
    enum Style {
        case success
        case error

        var tint: Color {
            switch self {
            case .success:
                return Color(red: 0.12, green: 0.64, blue: 0.41)
            case .error:
                return Color(red: 0.86, green: 0.24, blue: 0.23)
            }
        }
    }

    let style: Style
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(style.tint)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(style.tint.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct ActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case tertiary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary:
            return Color.black
        case .secondary:
            return Color.black.opacity(0.06)
        case .tertiary:
            return Color.clear
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary, .tertiary:
            return .primary
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

private let distanceFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .providedUnit
    formatter.unitStyle = .medium
    return formatter
}()

private extension MeasurementFormatter {
    func string(fromMeters value: Double) -> String {
        let miles = Measurement(value: value, unit: UnitLength.meters).converted(to: .miles)
        return string(from: miles)
    }
}
