import SwiftUI
import VisionKit
import Vision

// Live ISBN barcode scanner wrapping VisionKit's DataScannerViewController. Reports the first
// recognized barcode payload once, then stops. `isAvailable` gates whether the scan UI should be
// offered at all — it is false in the Simulator and on devices without the Neural Engine, so the
// add-book flow must always keep manual entry reachable.
//
// DataScannerViewControllerDelegate callbacks arrive on the main thread, so the Coordinator is a
// plain @MainActor object that updates state directly — no nonisolated bridging is needed here
// (unlike the realtime-audio speech callbacks elsewhere in the app).
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        // Idempotent: startScanning is a no-op if already running.
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var didScan = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didScan else { return }
            for case let .barcode(barcode) in addedItems {
                guard let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                didScan = true
                dataScanner.stopScanning()
                onScan(payload)
                return
            }
        }
    }
}
