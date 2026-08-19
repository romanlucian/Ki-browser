import Foundation

/// The 104 hand-drawn Clearframe folder icons, shipped in the app the same
/// way the AI catalog and the tracker list are: reviewed, tested, and
/// compiled in. Nothing here is fetched or replaced at runtime.
///
/// Generated from the source artwork, so the markup is stored verbatim: a
/// 16x16 box, stroke-only geometry in `currentColor`, and the set's one
/// design rule — every closed form has its top-right corner clipped at 45
/// degrees over 1.75 units. Renderers scale it uniformly and never re-round
/// or snap it. Edit the artwork, not this file.
enum ClearframeIconCatalogData {
    static let icons: [ClearframeIcon] =
        work
        + creative
        + reading
        + shopping
        + travel
        + code
        + people
        + media
        + home
        + markers
        + nature
        + objects
        + interface

    // MARK: - Work

    private static let work: [ClearframeIcon] = [
        icon("folder", .work, #"<path d="M2.75 12.75 V4.75 H6.25 L8 6.5 H11.75 L13.25 8 V12.75 Z"/>"#),
        icon("briefcase", .work, #"<path d="M2.75 12.75 V6.5 H11.75 L13.25 8 V12.75 Z"/><path d="M5.75 6.5 V4.75 H10.25 V6.5"/>"#),
        icon("calendar", .work, #"<path d="M2.75 13.25 V5 H11.75 L13.25 6.5 V13.25 Z"/><path d="M2.75 8.25 H13.25"/><path d="M5.5 5 V3.25"/><path d="M10.5 5 V3.25"/>"#),
        icon("task", .work, #"<path d="M3.25 7.25 L6.5 10.5 L12.75 4.25"/><path d="M3.25 13 H12.75"/>"#),
        icon("meeting", .work, #"<path d="M2.75 11.75 V8.25 H11.75 L13.25 9.75 V11.75 Z"/><circle cx="5.75" cy="4.4" r="1.25" fill="currentColor" stroke="none"/><circle cx="10.35" cy="4.4" r="1.25" fill="currentColor" stroke="none"/>"#),
        icon("deadline", .work, #"<circle cx="8" cy="8" r="5.25"/><path d="M8 4.25 V8 L10.75 10.75"/>"#),
        icon("archive", .work, #"<path d="M2.75 9.75 V12.75 H13.25 V11.25 L11.75 9.75"/><path d="M8 2.75 V8"/><path d="M5.5 5.5 L8 8 L10.5 5.5"/>"#)
    ]

    // MARK: - Creative

    private static let creative: [ClearframeIcon] = [
        icon("palette", .creative, #"<path d="M3 3 H11.5 L13 4.5 V13 H3 Z"/><path d="M3 3 L13 13"/>"#),
        icon("camera", .creative, #"<path d="M2.75 13.25 V5 H5.5 L7 3.5 H9.25 L10.75 5 H11.75 L13.25 6.5 V13.25 Z"/><circle cx="8" cy="9.1" r="1.6" fill="currentColor" stroke="none"/>"#),
        icon("film", .creative, #"<path d="M2.5 12.5 V5.5 H11.75 L13.5 7.25 V12.5 Z"/><path d="M5.5 5.5 V12.5"/>"#),
        icon("brush", .creative, #"<path d="M11.25 2.75 L13.25 4.75 L5.75 12.25 H3.75 V10.25 Z"/>"#),
        icon("layers", .creative, #"<path d="M6.25 10 V2.5 H12.25 L13.75 4 V10 Z"/><path d="M2.25 13.5 V6 H8.25 L9.75 7.5 V13.5 Z"/>"#),
        icon("type", .creative, #"<path d="M3.25 13.25 L7.15 4.5 H8.85 L12.75 13.25"/><path d="M5.6 9.25 H10.4"/>"#),
        icon("crop", .creative, #"<path d="M5.25 2.75 V10 L6.75 11.5 H13.25"/><path d="M2.75 5.25 H10 L11.5 6.75 V13.25"/>"#)
    ]

    // MARK: - Reading

    private static let reading: [ClearframeIcon] = [
        icon("book", .reading, #"<path d="M4.25 13.25 V2.75 H11 L12.75 4.5 V13.25 Z"/><path d="M6.75 2.75 V13.25"/>"#),
        icon("article", .reading, #"<path d="M2.75 4.5 H13.25"/><path d="M2.75 8 H9.75"/><path d="M2.75 11.5 H6.25"/>"#),
        icon("bookmark", .reading, #"<path d="M4.25 13.25 V2.75 H10 L11.75 4.5 V13.25 L8 9.5 Z"/>"#),
        icon("quote", .reading, #"<path d="M3 3.75 V12.25"/><path d="M6.25 6.5 H13.25"/><path d="M6.25 10 H9.75"/>"#),
        icon("note", .reading, #"<path d="M3.75 13.25 V2.75 H9.75 L12.75 5.75 V13.25 Z"/><path d="M9.75 2.75 V5.75 H12.75"/>"#),
        icon("highlight", .reading, #"<path d="M3 6 H13.25"/><path d="M3 9.75 H10.5 L12.75 12"/>"#),
        icon("library", .reading, #"<path d="M2.75 12.75 H13.25"/><path d="M4.75 5.5 V12.75"/><path d="M7.5 3.75 V12.75"/><path d="M10.5 12.75 L13.25 10"/>"#)
    ]

    // MARK: - Shopping

    private static let shopping: [ClearframeIcon] = [
        icon("bag", .shopping, #"<path d="M3.25 13.25 V5.5 H11.25 L12.75 7 V13.25 Z"/><path d="M6.25 5.5 V4.75 a1.75 1.75 0 0 1 3.5 0 V5.5"/>"#),
        icon("tag", .shopping, #"<path d="M2.75 11.5 V4.5 H9.75 L13.25 8 L9.75 11.5 Z"/><circle cx="6" cy="8" r="0.9" fill="currentColor" stroke="none"/>"#),
        icon("receipt", .shopping, #"<path d="M2.75 12.75 V3.25 H11.5 L13.25 5 V12.75 Z"/><path d="M5.75 6.5 H10.25"/><path d="M5.75 9.75 H7"/>"#),
        icon("card", .shopping, #"<path d="M2.5 12.25 V5.5 H11.75 L13.5 7.25 V12.25 Z"/><path d="M2.5 8.5 H13.5"/>"#),
        icon("coin", .shopping, #"<circle cx="9.75" cy="6.25" r="3.5"/><circle cx="6.25" cy="9.75" r="3.5"/>"#),
        icon("percent", .shopping, #"<path d="M4 12 L12 4"/><circle cx="4.9" cy="4.9" r="1.15" fill="currentColor" stroke="none"/><circle cx="11.1" cy="11.1" r="1.15" fill="currentColor" stroke="none"/>"#),
        icon("cart", .shopping, #"<path d="M3.75 7 H13.25 L10.5 9.75 H6.5 Z"/><path d="M2.75 5.25 H4.25 L6 7"/><circle cx="6.75" cy="12.9" r="0.85" fill="currentColor" stroke="none"/><circle cx="10.25" cy="12.9" r="0.85" fill="currentColor" stroke="none"/>"#)
    ]

    // MARK: - Travel

    private static let travel: [ClearframeIcon] = [
        icon("plane", .travel, #"<path d="M13.25 2.75 L2.75 7.5 L7.5 9.5 L9.5 13.25 Z"/>"#),
        icon("pin", .travel, #"<path d="M8 13.5 L4.5 10 A3.75 3.75 0 1 1 11.5 10 Z"/>"#),
        icon("globe", .travel, #"<circle cx="8" cy="8" r="5.25"/><ellipse cx="8" cy="8" rx="2" ry="5.25"/><path d="M2.75 8 H13.25"/>"#),
        icon("ticket", .travel, #"<path d="M2.75 12.5 V5 H6.25 L8.5 7.25 L10.75 5 H11.75 L13.5 6.75 V12.5 H10.75 L8.5 10.25 L6.25 12.5 Z"/>"#),
        icon("compass", .travel, #"<circle cx="8" cy="8" r="5.25"/><path d="M10 6 L8.75 8.75 L6 10 L7.25 7.25 Z"/>"#),
        icon("hotel", .travel, #"<path d="M2.75 5.75 V12.75 H13.25 V11.25 L11.5 9.5 H2.75"/>"#),
        icon("route", .travel, #"<path d="M2.75 8 V12.75 H6.25 L9.75 9.25 H13.25"/>"#)
    ]

    // MARK: - Code

    private static let code: [ClearframeIcon] = [
        icon("terminal", .code, #"<path d="M3 5.5 L6.5 9 L3 12.5"/><path d="M8.5 12.5 H13.25"/>"#),
        icon("branch", .code, #"<path d="M4.5 13 V3.5"/><path d="M4.5 9 L8.25 5.25 V3.5"/>"#),
        icon("bug", .code, #"<circle cx="8" cy="9.5" r="3.25"/><path d="M5.5 3.75 L7.25 5.5"/><path d="M10.5 3.75 L8.75 5.5"/>"#),
        icon("package", .code, #"<path d="M2.75 12.75 V5.5 H11.5 L13.25 7.25 V12.75 Z"/><path d="M8 5.5 V12.75"/>"#),
        icon("gear", .code, #"<circle cx="8" cy="8" r="3.25"/><path d="M3.4 3.4 L5.7 5.7 M10.3 10.3 L12.6 12.6 M3.4 12.6 L5.7 10.3 M10.3 5.7 L12.6 3.4"/>"#),
        icon("database", .code, #"<path d="M2.75 6.5 V3.5 H11.5 L13.25 5.25 V6.5 Z"/><path d="M2.75 12.5 V9.5 H11.5 L13.25 11.25 V12.5 Z"/>"#),
        icon("key", .code, #"<circle cx="5" cy="11" r="2.6"/><path d="M6.85 9.15 L13 3"/><path d="M10.75 5.25 L12.25 6.75"/>"#)
    ]

    // MARK: - People

    private static let people: [ClearframeIcon] = [
        icon("person", .people, #"<circle cx="8" cy="4.25" r="2.1"/><path d="M3.25 13.25 V12.5 L6.25 9.5 H9.75 L12.75 12.5 V13.25"/>"#),
        icon("group", .people, #"<circle cx="5.5" cy="4.5" r="1.9"/><circle cx="10.5" cy="4.5" r="1.9"/><path d="M2.75 13.25 V12 L5 9.75 H11 L13.25 12 V13.25"/>"#),
        icon("chat", .people, #"<path d="M2.75 11.5 V4.5 H11.5 L13.25 6.25 V11.5 H6.5 L3.75 14.25 V11.5 Z"/>"#),
        icon("mail", .people, #"<path d="M2.75 12 V5 H11.5 L13.25 6.75 V12 Z"/><path d="M4.5 5 L8 8.5 L11.5 5"/>"#),
        icon("call", .people, #"<path d="M3.5 6 L6 3.5 L8.25 5.75 L6.75 7.25 L8.75 9.25 L10.25 7.75 L12.5 10 L10 12.5 Z"/>"#),
        icon("share", .people, #"<circle cx="4.25" cy="8" r="1.3" fill="currentColor" stroke="none"/><circle cx="9.25" cy="3" r="1.3" fill="currentColor" stroke="none"/><circle cx="9.25" cy="13" r="1.3" fill="currentColor" stroke="none"/><path d="M5.2 7.05 L8.3 3.95 M5.2 8.95 L8.3 12.05"/>"#),
        icon("contact", .people, #"<path d="M5 13.25 V2.75 H11 L12.75 4.5 V13.25 Z"/><path d="M2.75 6 H5"/><path d="M2.75 10 H5"/>"#),
        icon("reply", .people, #"<path d="M6.5 5.25 L3.25 8.5 L6.5 11.75"/><path d="M3.25 8.5 H11 L13.25 10.75 V13"/>"#),
        icon("notify", .people, #"<path d="M4.25 10 V7.5 a3.75 3.75 0 0 1 7.5 0 V8.5 L10.25 10 Z"/><path d="M6.5 13 H9.5"/>"#),
        icon("thread", .people, #"<path d="M2.75 4.5 H13.25"/><path d="M6.25 8 H13.25"/><path d="M9.75 11.5 H13.25"/>"#)
    ]

    // MARK: - Media

    private static let media: [ClearframeIcon] = [
        icon("play", .media, #"<path d="M5.5 3.25 L10.25 8 L5.5 12.75 Z"/>"#),
        icon("music", .media, #"<circle cx="5.5" cy="11.25" r="1.75" fill="currentColor" stroke="none"/><path d="M7.25 11.25 V3.75 H11 L12.75 5.5"/>"#),
        icon("mic", .media, #"<path d="M6 6.25 V4.75 L7.75 3 H8.5 L10 4.5 V6.25 a2 2 0 0 1 -4 0 Z"/><path d="M8 8.25 V12.25"/><path d="M5.75 12.25 H10.25"/>"#),
        icon("photo", .media, #"<path d="M2.75 12.75 V3.25 H11.5 L13.25 5 V12.75 Z"/><path d="M2.75 9.75 L6 6.5 L9.25 9.75"/>"#),
        icon("video", .media, #"<path d="M2.5 12 V5.75 H8 L9.75 7.5 V12 Z"/><path d="M9.75 8.5 L13.25 5 V12 Z"/>"#),
        icon("podcast", .media, #"<circle cx="8" cy="8" r="1" fill="currentColor" stroke="none"/><path d="M10.3 5.7 A3.25 3.25 0 0 1 10.3 10.3"/><path d="M12.4 3.6 A6.25 6.25 0 0 1 12.4 12.4"/>"#),
        icon("levels", .media, #"<path d="M4.5 13 V4.5"/><path d="M8 13 V8"/><path d="M11.5 13 V11.5"/>"#),
        icon("queue", .media, #"<path d="M2.75 6 L4.75 8 L2.75 10"/><path d="M7.75 4.5 H13.25"/><path d="M7.75 8 H13.25"/><path d="M7.75 11.5 H13.25"/>"#),
        icon("volume", .media, #"<path d="M2.75 6.5 H5 L8 3.5 V12.5 L5 9.5 H2.75 Z"/><path d="M11 5 A4.25 4.25 0 0 1 11 11"/>"#),
        icon("vinyl", .media, #"<circle cx="8" cy="8" r="5.25"/><circle cx="8" cy="8" r="1.5"/><path d="M11 5 L13.5 2.5"/>"#)
    ]

    // MARK: - Home

    private static let home: [ClearframeIcon] = [
        icon("house", .home, #"<path d="M3 13.25 V8 L8 3 L13 8 V13.25 Z"/>"#),
        icon("plant", .home, #"<path d="M4.5 10.5 H11.5 L9.25 12.75 H6.75 Z"/><path d="M8 10.5 V5"/><path d="M8 8.5 L5.25 5.75 M8 7.25 L10.75 4.5"/>"#),
        icon("food", .home, #"<path d="M2.75 7.75 H13.25 a5.25 5.25 0 0 1 -10.5 0 Z"/><path d="M6 4.5 L7.5 3 M9 4.5 L10.5 3"/>"#),
        icon("health", .home, #"<path d="M6 13 V10 H3 V6 H6 V3 H8.25 L10 4.75 V6 H13 V10 H10 V13 Z"/>"#),
        icon("fitness", .home, #"<path d="M4.5 11.5 L11.5 4.5"/><path d="M3.1 10.1 L5.9 12.9"/><path d="M10.1 3.1 L12.9 5.9"/>"#),
        icon("pet", .home, #"<circle cx="8" cy="12.5" r="1.9"/><circle cx="4.5" cy="7" r="1.1" fill="currentColor" stroke="none"/><circle cx="8" cy="3.5" r="1.1" fill="currentColor" stroke="none"/><circle cx="11.5" cy="7" r="1.1" fill="currentColor" stroke="none"/>"#),
        icon("car", .home, #"<path d="M2.75 10 V7.75 L5.5 5 H10.5 L13.25 7.75 V10 Z"/><circle cx="5.5" cy="13.25" r="0.9" fill="currentColor" stroke="none"/><circle cx="10.5" cy="13.25" r="0.9" fill="currentColor" stroke="none"/>"#),
        icon("coffee", .home, #"<path d="M3.25 5.5 H10.25 V11 L8.75 12.5 H4.75 L3.25 11 Z"/><path d="M10.25 6.75 H12 L13.25 8 V9.5 L12 10.75 H10.25"/>"#),
        icon("umbrella", .home, #"<path d="M2.75 8.5 a5.25 5.25 0 0 1 10.5 0 Z"/><path d="M8 8.5 V11.5 L10.25 13.75"/>"#),
        icon("laundry", .home, #"<path d="M2.5 13.5 V2.5 H11.75 L13.5 4.25 V13.5 Z"/><circle cx="8" cy="8.5" r="2"/>"#)
    ]

    // MARK: - Markers

    private static let markers: [ClearframeIcon] = [
        icon("star", .markers, #"<path d="M8 2.5 L9.45 6.55 L13.5 8 L9.45 9.45 L8 13.5 L6.55 9.45 L2.5 8 L6.55 6.55 Z"/>"#),
        icon("flag", .markers, #"<path d="M4 13.25 V3.5"/><path d="M4 3.5 H13.25 L10.75 6 L13.25 8.5 H4 Z"/>"#),
        icon("heart", .markers, #"<path d="M8 13 L3.25 8.25 a3.4 3.4 0 0 1 4.75 -4.75 a3.4 3.4 0 0 1 4.75 4.75 Z"/>"#),
        icon("bolt", .markers, #"<path d="M10.75 3 L5.5 8.25 H8.5 L3.25 13.5"/>"#),
        icon("shield", .markers, #"<path d="M3 4 H11.25 L13 5.75 V8 L8 13 L3 8 Z"/>"#),
        icon("target", .markers, #"<circle cx="8" cy="8" r="4.5"/><circle cx="8" cy="8" r="1.4" fill="currentColor" stroke="none"/><path d="M8 1.75 V4 M8 12 V14.25 M1.75 8 H4 M12 8 H14.25"/>"#),
        icon("arrow", .markers, #"<path d="M3.5 12.5 L12.5 3.5"/><path d="M7.5 3.5 H12.5 V8.5"/>"#),
        icon("diamond", .markers, #"<path d="M8 3 L13 8 L8 13 L3 8 Z"/>"#),
        icon("square", .markers, #"<path d="M3.25 12.75 V3.25 H11 L12.75 5 V12.75 Z"/>"#),
        icon("dot", .markers, #"<circle cx="8" cy="8" r="3.25" fill="currentColor" stroke="none"/>"#)
    ]

    // MARK: - Nature

    private static let nature: [ClearframeIcon] = [
        icon("tree", .nature, #"<path d="M3.25 11.5 H12.75 L8 6.75 Z"/><path d="M8 11.5 V13.75"/>"#),
        icon("mountain", .nature, #"<path d="M2.5 10.5 L6 7 L8 9 L10.5 6.5 L13.5 9.5"/>"#),
        icon("wave", .nature, #"<path d="M2.75 6.5 q2.6 -2.6 5.25 0 t5.25 0"/><path d="M2.75 10.5 q2.6 -2.6 5.25 0 t5.25 0"/>"#),
        icon("moon", .nature, #"<path d="M5.25 5.25 a5.35 5.35 0 0 1 7.5 7.5 a10 10 0 0 0 -7.5 -7.5 Z"/>"#),
        icon("sun", .nature, #"<circle cx="8" cy="8" r="4.25"/><path d="M8 3.75 V1.5 M8 12.25 V14.5 M3.75 8 H1.5 M12.25 8 H14.5"/>"#),
        icon("leaf", .nature, #"<path d="M4.25 11.75 a6.5 6.5 0 0 1 7.5 -7.5 a6.5 6.5 0 0 1 -7.5 7.5 Z"/>"#),
        icon("fire", .nature, #"<path d="M8.5 3.25 L12.25 7 a3.75 3.75 0 1 1 -7.5 0 Z"/>"#),
        icon("wind", .nature, #"<path d="M2.75 5 H11.5 L13.25 6.75"/><path d="M2.75 8.5 H8 L9.75 10.25"/><path d="M2.75 12 H4.5 L6.25 13.75"/>"#)
    ]

    // MARK: - Objects

    private static let objects: [ClearframeIcon] = [
        icon("flask", .objects, #"<path d="M6.25 4.5 V8.5 L2.75 12 H13.25 L9.75 8.5 V4.5 Z"/>"#),
        icon("ruler", .objects, #"<path d="M6 13.5 V2.5 H10.25 L12 4.25 V13.5 Z"/><path d="M6 6.25 H8.5 M6 9.75 H8.5"/>"#),
        icon("scissors", .objects, #"<path d="M4 3.5 L11 10.5"/><path d="M12 3.5 L5 10.5"/><circle cx="11.9" cy="12.4" r="1.6"/><circle cx="4.1" cy="12.4" r="1.6"/>"#),
        icon("hourglass", .objects, #"<path d="M3.75 3.5 H12.25 L8 7.75 L12.25 12 H3.75 L8 7.75 Z"/>"#),
        icon("roller", .objects, #"<path d="M3.5 3.5 H11.5 L13.25 5.25 V7.5 H3.5 Z"/><path d="M8 7.5 V10 L10.25 12.25"/>"#),
        icon("medal", .objects, #"<path d="M4.75 5.25 V2.75 H10.25 L11.5 4 V5.25 Z"/><circle cx="8" cy="11.25" r="2.75"/>"#),
        icon("pill", .objects, #"<path d="M3.75 9.5 L9.5 3.75 a2.5 2.5 0 0 1 3.5 3.5 L7.25 13 a2.5 2.5 0 0 1 -3.5 -3.5 Z"/><path d="M6.6 10.1 L10.1 6.6"/>"#),
        icon("trophy", .objects, #"<path d="M4.75 3.5 H11.25 V7.5 L8 10.75 L4.75 7.5 Z"/><path d="M8 10.75 V12.75"/><path d="M5.75 12.75 H10.25"/>"#)
    ]

    // MARK: - Interface

    private static let interface: [ClearframeIcon] = [
        icon("lock", .interface, #"<path d="M2.75 13.25 V8.5 H11.5 L13.25 10.25 V13.25 Z"/><path d="M5.75 8.5 V5.5 a2.25 2.25 0 0 1 4.5 0 V8.5"/>"#),
        icon("grid", .interface, #"<path d="M6 2.75 V13.25 M10 2.75 V13.25 M2.75 6 H13.25 M2.75 10 H13.25"/>"#),
        icon("filter", .interface, #"<path d="M2.75 4.25 H13.25 L9.5 8 V12.5 H6.5 V8 Z"/>"#),
        icon("trash", .interface, #"<path d="M4.25 13.25 V6.25 H10.5 L12.25 8 V13.25 Z"/><path d="M2.75 6.25 H13.25"/>"#),
        icon("tabs", .interface, #"<path d="M2.5 12.75 V6 H5 L6.5 7.5 V12.75 Z"/><path d="M9.5 12.75 V4 H12.5 L14 5.5 V12.75 Z"/>"#),
        icon("sync", .interface, #"<path d="M8 3.5 A4.5 4.5 0 0 1 12.5 8"/><path d="M11.25 6.75 L12.5 8 L11.25 9.25"/><path d="M8 12.5 A4.5 4.5 0 0 1 3.5 8"/><path d="M4.75 9.25 L3.5 8 L4.75 6.75"/>"#)
    ]

    private static func icon(
        _ id: String,
        _ category: ClearframeIconCategory,
        _ markup: String
    ) -> ClearframeIcon {
        ClearframeIcon(id: id, category: category, markup: markup)
    }
}
