import Foundation

/// The UI scope shown while the signed-in application prepares its main tree.
@MainActor
@Observable
final class PreparationUIContext {
  let message = "Your workspace is ready to assemble."
}

/// The UI scope shown when the main experience is temporarily unavailable.
@MainActor
@Observable
final class RestrictionUIContext {
  let title = "Access is paused"
  let message = "This separate surface replaces the tabs without turning a tab path into a special case."
}

/// Owns the main application's mutually exclusive surface and retained tab tree.
///
/// `tabs` remains alive while a restriction surface is visible. Restoring access
/// therefore reveals the same per-tab paths rather than reconstructing them.
@MainActor
@Observable
final class MainUIContext {
  /// Coarse-grained surfaces that cannot be visible at the same time.
  enum Surface {
    case preparing(PreparationUIContext)
    case tabs
    case restricted(RestrictionUIContext)
  }

  var surface: Surface
  let tabs: TabContainerUIContext

  init(
    surface: Surface? = nil,
    tabs: TabContainerUIContext? = nil
  ) {
    self.surface = surface ?? .preparing(PreparationUIContext())
    self.tabs = tabs ?? TabContainerUIContext()
  }
}

/// The UI scope for the in-app Route Lab presentation.
@MainActor
@Observable
final class RouteLabUIContext: Identifiable {
  let id = UUID()
}

/// The UI scope for a Session-wide announcement sheet.
@MainActor
@Observable
final class AnnouncementUIContext: Identifiable {
  let id = UUID()
  let title: String
  let message: String

  init(
    title: String = "Welcome to the UIContext prototype",
    message: String = "This sheet is owned above the tab hierarchy, so it is independent of every tab's navigation path."
  ) {
    self.title = title
    self.message = message
  }
}

/// A sheet scope presented by `SessionUIContext` above its retained tab tree.
enum SessionSheetUIContext: Identifiable {
  case routeLab(RouteLabUIContext)
  case announcement(AnnouncementUIContext)

  var id: UUID {
    switch self {
    case .routeLab(let uiContext): uiContext.id
    case .announcement(let uiContext): uiContext.id
    }
  }
}

/// The UI scope for a blocking layer independent from navigation and sheets.
@MainActor
@Observable
final class BlockingNoticeUIContext: Identifiable {
  let id = UUID()
  let title = "Action required"
  let message = "A blocking layer occupies its own presentation lane in the UIContext tree."
}
