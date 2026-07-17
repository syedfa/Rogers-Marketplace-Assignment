import SwiftUI

/// HIG-recommended "primer" screen shown before the first system camera
/// permission prompt, explaining why the app wants access so the system
/// dialog isn't the user's first signal.
struct CameraPermissionPrimer: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text("Allow Camera Access")
                .font(.title2.weight(.semibold))
            Text("Marketplace uses your camera so you can photograph the item you're listing. You'll be asked to confirm this on the next screen.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Button("Not Now", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
