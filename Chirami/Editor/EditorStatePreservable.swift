import Foundation

/// Protocol for models that preserve editor cursor and scroll positions across window hide/show cycles.
protocol EditorStatePreservable: AnyObject {
    var savedCursorLocation: Int { get set }
    var savedScrollOffset: CGPoint { get set }
}
