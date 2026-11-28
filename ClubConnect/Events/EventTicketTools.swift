import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

enum TicketBarcode {
    static func payload(eventID: String, code: String) -> String {
        "clubconnect:ticket:1:\(eventID):\(code)"
    }

    static func code(in payload: String, for eventID: String) -> String? {
        let parts = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0] == "clubconnect", parts[1] == "ticket",
              parts[2] == "1", parts[3] == eventID, !parts[4].isEmpty else { return nil }
        return String(parts[4])
    }

    static func image(payload: String) -> CGImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(payload.utf8)
        qr.correctionLevel = "M"
        guard let output = qr.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

struct EventScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authorized = false
    @State private var failure: String?
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let failure {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera", description: Text(failure))
                } else if authorized {
                    EventCodeScanner { value in
                        dismiss()
                        onScan(value)
                    } onFailure: { message in
                        failure = message
                    }
                } else {
                    ProgressView("Opening camera")
                }
            }
            .navigationTitle("Scan event ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                guard DataScannerViewController.isSupported else {
                    failure = "Enter the code shown on the member’s ticket."
                    return
                }
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard granted, DataScannerViewController.isAvailable else {
                    failure = "Enter the ticket code, or enable camera access in Settings."
                    return
                }
                authorized = true
            }
        }
    }
}

private struct EventCodeScanner: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onFailure: (String) -> Void

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onFailure: (String) -> Void
        private var finished = false

        init(onScan: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for case .barcode(let barcode) in addedItems {
                guard let payload = barcode.payloadStringValue else { continue }
                finished = true
                scanner.stopScanning()
                onScan(payload)
                break
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onFailure("The camera is unavailable. Enter the member’s ticket code.")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning else { return }
        do {
            try scanner.startScanning()
        } catch {
            Task { @MainActor in onFailure("The camera could not start. Enter the member’s ticket code.") }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }
}
