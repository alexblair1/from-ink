import Foundation

/// Discriminator for `PageBlock` payload type. Stored on the model as a
/// raw `String` (`kindRaw`) per the CloudKit-friendly enum convention;
/// the typed accessor lives on `PageBlock`.
///
/// Three first-class kinds:
///   • `.text` — `bodyData` carries an archived `AttributedString`.
///   • `.ink` — `drawingData` carries `PKDrawing` bytes in canonical
///     coordinates (see Notebook.canonicalCanvasWidth).
///   • `.voice` — `audioData` carries m4a audio; `transcript` is the
///     editable derived text.
///
/// Future v1.1 kinds (`image`, `video`, `embed`) slot in by adding a
/// case; the architecture supports them without further changes (see
/// text experience EDD §5 / §23).
enum PageBlockKind: String, Codable, CaseIterable, Sendable {
    case text
    case ink
    case voice
}
