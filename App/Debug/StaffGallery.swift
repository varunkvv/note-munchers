#if DEBUG
import NoteCore
import SwiftUI

/// `-demoScreen gallery -demoGalleryUnit <n>`: every item of a unit on its unit's
/// staff, to check drawing (ledger lines, chords, stems, beams) in one screenshot.
struct StaffGallery: View {
    let unit: NoteCore.Unit

    var body: some View {
        let spec = StaffSpec(unit: unit)
        let items = unit.newItems.isEmpty ? unit.reviews.flatMap { Curriculum.standard.unit($0)?.newItems ?? [] } : unit.newItems
        let columns = items.count > 6 ? 3 : 2
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(items, id: \.id) { item in
                    StaffView(spec: spec, item: item)
                        .frame(height: spec.layout == .grand ? 330 : 230)
                        .background(Theme.paper)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }
            }
            .padding(16)
        }
        .background(Color(white: 0.9))
    }
}
#endif
