/// Where a window the assistant's page opens is shown — `window.open`, which
/// is how a provider's sign-in works.
///
/// The host decides, the way it supplies how pages are shared: a Mac window
/// has room to show the tab such a window becomes, while on a phone the
/// assistant covers the page area and that tab would sit invisibly behind it.
public enum AssistantPopupPlacement {
    /// A tab of its own, selected. The Mac's behaviour.
    case tab
    /// Over the assistant, held by the companion as `popup`. The phone's.
    case overAssistant
}
