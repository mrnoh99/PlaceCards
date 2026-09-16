import SwiftUI

/// Renders one `LegalDocument` — the privacy policy or the terms — as a
/// plain scrolling page.
///
/// A `ScrollView` of `Text` rather than a `Form`: these are documents to
/// read, not settings to operate, and a grouped list's row separators
/// would break paragraphs into unrelated-looking chunks.
struct LegalDocumentView: View {
    /// Which document to show. Resolved at render time rather than passed
    /// in already-built, so the caller doesn't have to know which language
    /// the device is in.
    enum Kind {
        case privacyPolicy
        case termsOfService
    }

    let kind: Kind

    private var document: LegalDocument {
        let language = AppLanguage.current()
        switch kind {
        case .privacyPolicy: return LegalDocuments.privacyPolicy(for: language)
        case .termsOfService: return LegalDocuments.termsOfService(for: language)
        }
    }

    var body: some View {
        let document = self.document
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.title2.bold())
                    Text("최종 수정: ".localized + document.lastUpdated)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(.headline)
                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            // Paragraphs of prose set solid are markedly
                            // harder to read than the short labels the
                            // rest of this app is made of.
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(kind: .privacyPolicy)
    }
}
