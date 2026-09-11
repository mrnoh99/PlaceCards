import SwiftUI
import UIKit

extension View {
    /// A "완료" button pinned directly above the keyboard — works no
    /// matter which field is focused or whether the screen's own content
    /// is even long enough to scroll-to-dismiss (`scrollDismissesKeyboard`
    /// needs an actual drag; a short form like `AddBoardSheet` often isn't
    /// tall enough for that to kick in reliably). Sends
    /// `resignFirstResponder` with no specific target, the standard way
    /// to dismiss whichever responder currently has focus without every
    /// individual `TextField` needing its own `@FocusState` wired up just
    /// for this.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료".localized) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
