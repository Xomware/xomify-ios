import Foundation

/// ViewModel for Release Radar screen
/// Data comes from weekly cron job - no live Spotify calls
@Observable
@MainActor
final class ReleaseRadarViewModel {
    
    // MARK: - Properties
    
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?
    
    // History weeks from database
    var historyWeeks: [ReleaseRadarWeek] = []
    var selectedWeek: ReleaseRadarWeek?
    var currentWeekKey: String?
    var currentWeekDisplay: String?
    
    // User email (set from profile)
    var userEmail: String?
    
    private let xomifyService = XomifyService.shared
    
    // MARK: - Computed
    
    var hasData: Bool {
        !historyWeeks.isEmpty
    }
    
    /// Currently displayed releases (from selected week or first week)
    var displayReleases: [Release] {
        if let week = selectedWeek {
            return week.releases ?? []
        }
        return historyWeeks.first?.releases ?? []
    }
    
    /// Stats for currently displayed week
    var displayStats: ReleaseStats? {
        if let week = selectedWeek {
            return week.stats
        }
        return historyWeeks.first?.stats
    }
    
    /// Display name for selected week
    var displayWeekName: String {
        if let week = selectedWeek {
            return week.displayName
        }
        return historyWeeks.first?.displayName ?? "No Data"
    }
    
    /// Date range for selected week
    var displayDateRange: String? {
        if let week = selectedWeek {
            return week.dateRange
        }
        return historyWeeks.first?.dateRange
    }
    
    /// Check if a specific week is currently selected
    func isWeekSelected(_ week: ReleaseRadarWeek) -> Bool {
        selectedWeek?.weekKey == week.weekKey
    }
    
    // MARK: - Actions
    
    func loadData() async {
        guard let email = userEmail, !email.isEmpty else {
            errorMessage = "Please log in first"
            print("❌ ReleaseRadar: No email provided")
            return
        }
        
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        print("📡 ReleaseRadar: Loading history for \(email)...")
        
        do {
            let response = try await xomifyService.getReleaseRadarHistory()
            
            print("✅ ReleaseRadar: Got response")
            print("   - weeks count: \(response.weeks?.count ?? 0)")
            print("   - currentWeek: \(response.currentWeek ?? "nil")")
            
            historyWeeks = response.weeks ?? []
            currentWeekKey = response.currentWeek
            currentWeekDisplay = response.currentWeekDisplay
            
            // Debug: log first week's releases
            if let firstWeek = historyWeeks.first {
                print("   - First week: \(firstWeek.weekKey)")
                print("   - Releases count: \(firstWeek.releases?.count ?? 0)")
                if let releases = firstWeek.releases {
                    for (i, release) in releases.prefix(3).enumerated() {
                        print("     [\(i)] albumId: \(release.albumId ?? "nil"), name: \(release.displayName)")
                    }
                }
            }
            
            // Select first week by default
            if selectedWeek == nil, let firstWeek = historyWeeks.first {
                selectedWeek = firstWeek
            }
            
            print("✅ ReleaseRadar: Loaded \(historyWeeks.count) weeks")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ ReleaseRadar: Error - \(error)")
            
            // More detailed error logging
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Key '\(key.stringValue)' not found: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("   Type mismatch for \(type): \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value not found for \(type): \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
        }
        
        isLoading = false
    }
    
    func refresh() async {
        guard let email = userEmail else { return }
        guard !isRefreshing else { return }
        
        isRefreshing = true
        errorMessage = nil
        
        print("🔄 ReleaseRadar: Refreshing for \(email)...")
        
        do {
            let response = try await xomifyService.getReleaseRadarHistory()
            historyWeeks = response.weeks ?? []
            currentWeekKey = response.currentWeek
            
            // Keep selection if it still exists
            if let currentSelection = selectedWeek {
                selectedWeek = historyWeeks.first { $0.weekKey == currentSelection.weekKey }
            }
            
            // If selection no longer exists, select first
            if selectedWeek == nil, let firstWeek = historyWeeks.first {
                selectedWeek = firstWeek
            }
            
            print("✅ ReleaseRadar: Refreshed - \(historyWeeks.count) weeks")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ ReleaseRadar: Refresh error - \(error)")
        }
        
        isRefreshing = false
    }
    
    func selectWeek(_ week: ReleaseRadarWeek) {
        selectedWeek = week
        print("📅 ReleaseRadar: Selected week \(week.weekKey) with \(week.releases?.count ?? 0) releases")
    }
}
