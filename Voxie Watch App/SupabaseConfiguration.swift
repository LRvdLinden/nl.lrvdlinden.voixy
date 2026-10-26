import Foundation

/// The publishable key identifies the Supabase project; it is not a secret.
/// All privileged database access happens inside the Supabase Edge Function.
enum SupabaseConfiguration {
    static let projectURL = "https://qalcgyzkicazkmzsouiu.supabase.co"
    static let publishableKey = "sb_publishable_viy1j1i6yq63diseZWNRYg_smFp6-RR"
    static let functionURL = projectURL + "/functions/v1/voxie"
}
