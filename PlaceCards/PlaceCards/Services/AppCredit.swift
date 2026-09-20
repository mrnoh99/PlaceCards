import SwiftUI

/// The build's own credit line, in one place.
///
/// Settings has shown this at the bottom of its last section for a while;
/// Home and Gallery show the same line now, so it lives here rather than
/// as a private copy on whichever screen happened to need it first.
enum AppCredit {
    /// Read from the bundle rather than written out here, so the numbers
    /// can never drift from the build they are printed on. Not localized:
    /// a name and two version numbers read the same in either language.
    static var line: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "Developed by JaiSung NOH MD 2026, Ver(\(version)) Build(\(build))"
    }
}

/// The credit line itself, with no opinion about what it sits inside —
/// the three screens showing it are a `Form`, a `List` and a `ScrollView`,
/// and each needs its own wrapping (`Section` plus cleared row chrome in
/// the first two, plain padding in the last). Keeping that out of here is
/// what lets one definition serve all three.
struct CreditFooter: View {
    var body: some View {
        Text(AppCredit.line)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
