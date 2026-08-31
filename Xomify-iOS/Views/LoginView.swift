import SwiftUI

// MARK: - Login View

struct LoginView: View {
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.xomifyDark, Color(red: 18/255, green: 18/255, blue: 37/255)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo section - using your "banner-logo" asset
                VStack(spacing: 24) {
                    Image("banner-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 280)
                        .shadow(color: .xomifyPurple.opacity(0.5), radius: 20)
                    
                    Text("Your Music, Your Stats")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Login button
                VStack(spacing: 16) {
                    Button {
                        login()
                    } label: {
                        HStack(spacing: 12) {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "music.note")
                                Text("Connect with Spotify")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 29/255, green: 185/255, blue: 84/255))
                        .foregroundColor(.white)
                        .cornerRadius(XomRadius.pill)
                    }
                    .disabled(isLoading)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
    }
    
    private func login() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                try await AuthService.shared.login()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
}
