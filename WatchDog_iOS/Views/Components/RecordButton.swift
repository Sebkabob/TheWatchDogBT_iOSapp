//
//  RecordButton.swift
//  BluetoothTesting
//

import SwiftUI
import UIKit

struct RecordButton: View {
    var recorder: MotionDataRecorder
    var onExport: (URL) -> Void

    var body: some View {
        Button(action: {
            if recorder.isRecording {
                if let url = recorder.stopRecording() {
                    onExport(url)
                }
            } else {
                recorder.startRecording()
            }
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.red.opacity(0.5))
                    .frame(width: 8, height: 8)
                if recorder.isRecording {
                    Text("\(recorder.sampleCount)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.red)
                } else {
                    Text("REC")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(recorder.isRecording ? Color.red.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    RecordButton(recorder: MotionDataRecorder.shared, onExport: { _ in })
        .frame(width: 80)
        .padding()
}
