import SwiftUI

// DataCollectionView — hidden researcher screen for collecting labelled pose samples
// (FR-19). Accessible via a 2-second long press on the step indicator in CaptureStepView.
//
// Layout (top to bottom):
//   Camera preview — see the subject framing before recording
//   Pickers        — choose label (menu) and angle (segmented)
//   Distribution   — per-label sample counts so you can spot class imbalance
//   Actions        — Record (captures + stores) and Export (AirDrop JSON to Mac)

struct DataCollectionView: View {

    @StateObject private var viewModel = DataCollectionViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showShareSheet  = false
    @State private var exportURL: URL?
    @State private var showClearConfirm = false
    @State private var exportErrorMessage: String?
    @State private var showExportError  = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cameraPreview
                controlsScrollView
            }
            .navigationTitle("Data Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear  { viewModel.startSession() }
            .onDisappear { viewModel.stopSession() }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL { ShareSheet(url: url) }
            }
            .confirmationDialog("Clear all samples?",
                                isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button("Clear \(viewModel.store.samples.count) samples", role: .destructive) {
                    viewModel.store.clear()
                    viewModel.statusMessage = ""
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Export failed", isPresented: $showExportError) {
                Button("OK") {}
            } message: {
                Text(exportErrorMessage ?? "Unknown error")
            }
        }
    }

    // MARK: - Camera

    private var cameraPreview: some View {
        CameraPreviewView(session: viewModel.captureManager.captureSession)
            .frame(height: 300)
            .background(Color.black)
            .overlay(alignment: .bottom) {
                // Quick-glance label badge overlaid on the preview
                Text(viewModel.selectedLabel.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 10)
            }
    }

    // MARK: - Controls

    private var controlsScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                pickerCard
                distributionCard
                actionCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Pickers

    private var pickerCard: some View {
        VStack(spacing: 14) {
            // Label — 6 options, menu picker fits without truncation
            HStack {
                Text("Label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                Picker("Label", selection: $viewModel.selectedLabel) {
                    ForEach(PostureLabel.allCases, id: \.self) { label in
                        Text(label.displayName).tag(label)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Angle — 3 options fit cleanly as a segmented control
            HStack {
                Text("Angle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                Picker("Angle", selection: $viewModel.selectedAngle) {
                    ForEach(CaptureAngle.allCases, id: \.self) { angle in
                        Text(angle.title).tag(angle)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    // MARK: - Distribution

    private var distributionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sample distribution")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(viewModel.store.samples.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.store.samples.isEmpty {
                Text("No samples recorded yet — tap Record to start.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                // One row per label, width proportional to count fraction.
                // A well-balanced dataset has equal bar lengths.
                let total = max(1, viewModel.store.samples.count)
                ForEach(PostureLabel.allCases, id: \.self) { label in
                    let count    = viewModel.store.labelDistribution[label.rawValue] ?? 0
                    let fraction = Double(count) / Double(total)
                    distributionRow(name: label.displayName, count: count, fraction: fraction)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    private func distributionRow(name: String, count: Int, fraction: Double) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.caption)
                .foregroundStyle(count == 0 ? .tertiary : .primary)
                .frame(width: 150, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(count > 0 ? Color.blue.opacity(0.75) : Color.clear)
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeOut(duration: 0.3), value: fraction)
                }
            }
            .frame(height: 8)

            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
                .monospacedDigit()
        }
    }

    // MARK: - Actions

    private var actionCard: some View {
        VStack(spacing: 12) {
            // Status line from last operation
            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(
                        viewModel.statusMessage.contains("✓") ? Color.green : Color.secondary
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.statusMessage)
            }

            // Record — captures a still frame, runs Vision, stores the sample
            Button {
                viewModel.record()
            } label: {
                Label(
                    viewModel.isCapturing ? "Capturing…" : "Record Sample",
                    systemImage: viewModel.isCapturing ? "circle" : "circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCapturing)

            // Export — writes CreateML JSON and presents share sheet for AirDrop
            Button {
                do {
                    let url = try viewModel.store.exportCreateMLJSON()
                    exportURL = url
                    showShareSheet = true
                } catch {
                    exportErrorMessage = error.localizedDescription
                    showExportError = true
                }
            } label: {
                Label("Export JSON for CreateML", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.store.samples.isEmpty)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Clear", role: .destructive) {
                showClearConfirm = true
            }
            .disabled(viewModel.store.samples.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
        }
    }
}

// MARK: - Share sheet

// Bridges UIActivityViewController into SwiftUI for AirDrop / Files export.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
