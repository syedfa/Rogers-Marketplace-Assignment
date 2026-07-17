import SwiftUI
import PhotosUI
import AVFoundation

struct CreateListingView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateListingViewModel?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCameraPrimer = false
    @State private var showCamera = false
    @State private var showCameraDeniedAlert = false

    var body: some View {
        NavigationStack {
            Form {
                if let viewModel {
                    photosSection(viewModel)
                    detailsSection(viewModel)
                    descriptionSection(viewModel)
                    publishSection(viewModel)
                }
            }
            .navigationTitle("Sell Something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(viewModel?.isPublishing == true)
            .onChange(of: photoPickerItems) { _, items in
                Task { await loadPickedPhotos(items) }
            }
            .sheet(isPresented: $showCameraPrimer) {
                CameraPermissionPrimer(
                    onContinue: {
                        showCameraPrimer = false
                        requestCameraAccess()
                    },
                    onCancel: { showCameraPrimer = false }
                )
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    viewModel?.pickedImages.append(image)
                }
                .ignoresSafeArea()
            }
            .alert("Camera Access Needed", isPresented: $showCameraDeniedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enable camera access in Settings to photograph items for your listing.")
            }
            .onChange(of: viewModel?.didPublish) { _, didPublish in
                // Dismissing (rather than just clearing the form) is the
                // signal to the user that the listing actually saved.
                if didPublish == true {
                    dismiss()
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = CreateListingViewModel(repository: dependencies.repository)
            }
        }
    }

    @ViewBuilder
    private func photosSection(_ viewModel: CreateListingViewModel) -> some View {
        Section("Photos") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.pickedImages.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    viewModel.removeImage(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                    }

                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 10, matching: .images) {
                        addPhotoTile(systemImage: "photo.on.rectangle")
                    }

                    Button {
                        handleCameraTap()
                    } label: {
                        addPhotoTile(systemImage: "camera.fill")
                    }
                }
            }
            if let error = viewModel.fieldErrors[.images] {
                errorText(error)
            }
        }
    }

    @ViewBuilder
    private func detailsSection(_ viewModel: CreateListingViewModel) -> some View {
        Section("Details") {
            TextField("Title", text: Binding(get: { viewModel.title }, set: { viewModel.title = $0 }))
            if let error = viewModel.fieldErrors[.title] {
                errorText(error)
            }

            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField(
                    "Price",
                    text: Binding(get: { viewModel.priceText }, set: { viewModel.priceText = $0 })
                )
                .keyboardType(.decimalPad)
            }
            if let error = viewModel.fieldErrors[.price] {
                errorText(error)
            }

            Picker("Category", selection: Binding(get: { viewModel.category }, set: { viewModel.category = $0 })) {
                ForEach(Category.allCases) { category in
                    Label(category.displayName, systemImage: category.symbolName).tag(category)
                }
            }
        }
    }

    @ViewBuilder
    private func descriptionSection(_ viewModel: CreateListingViewModel) -> some View {
        Section("Description") {
            TextEditor(
                text: Binding(get: { viewModel.descriptionText }, set: { viewModel.descriptionText = $0 })
            )
            .frame(minHeight: 100)
            if let error = viewModel.fieldErrors[.description] {
                errorText(error)
            }
        }
    }

    @ViewBuilder
    private func publishSection(_ viewModel: CreateListingViewModel) -> some View {
        Section {
            Button {
                Task { await viewModel.publish() }
            } label: {
                if viewModel.isPublishing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Publish Listing").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isPublishing)
        } footer: {
            Text("Your listing saves immediately and works offline — it syncs automatically once you're back online.")
        }
    }

    private func addPhotoTile(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.secondarySystemBackground))
            .frame(width: 84, height: 84)
            .overlay(Image(systemName: systemImage).font(.title3).foregroundStyle(.secondary))
    }

    private func errorText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.red)
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        viewModel?.pickedImages.append(contentsOf: images)
        photoPickerItems = []
    }

    private func handleCameraTap() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            showCameraPrimer = true
        case .authorized:
            showCamera = true
        default:
            showCameraDeniedAlert = true
        }
    }

    private func requestCameraAccess() {
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                showCamera = true
            } else {
                showCameraDeniedAlert = true
            }
        }
    }
}
