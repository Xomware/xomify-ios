import Foundation

/// ViewModel for the Login screen
@Observable
@MainActor
final class LoginViewModel {
    
    // MARK: - Properties
    
    var isLoading = false
    var errorMessage: String?
    var showError = false
    
    private let authService = AuthService.shared
    
    // MARK: - Computed
    
    var isAuthenticated: Bool {
        authService.isAuthenticated
    }
    
    // MARK: - Actions
    
    /// Initiate Spotify login
    @MainActor
    func login() async {
        isLoading = true
        errorMessage = nil
        showError = false
        
        do {
            try await authService.login()
        } catch AuthError.cancelled {
            // User cancelled - not an error to show
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
}
