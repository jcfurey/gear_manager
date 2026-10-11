import SwiftUI

extension View {
    func persistenceErrorAlert(isPresented: Binding<Bool>) -> some View {
        alert("Changes Not Saved", isPresented: isPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your changes could not be written to storage. Please check available space and try saving again.")
        }
    }
}
