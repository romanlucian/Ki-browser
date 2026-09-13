# Limeghost for iPhone — your own assistant

**Status:** designed with the founder on September 13, 2026.
- **Approved in conversation:** where the button lives, how much to build, the approach, and §2 with its design canvas.
- **Written from the recommendations that went with them:** the three calls in §3, which the founder took by approving the canvas ("it looks good, everything"), and §4–§7.
- **Judgment calls:** §9 lists the ones made while writing, so any of them can be reversed cheaply.

- The overall iOS design is [2026-09-03-ios-pocket-browser-design.md](2026-09-03-ios-pocket-browser-design.md). Its §5 designed the assistant on a phone, and this step builds it, with the amendments in §8.
- The mockups are a design canvas: [Limeghost iPhone Assistant](https://claude.ai/code/artifact/10064466-e76d-488a-9008-f782bd8217cf), private to the founder's account. They show eleven static screens at iPhone 13 Pro Max and iPhone SE sizes, with the bar measured from the founder's own screenshot. They are a visual draft, not a pixel contract.
- It follows [Bookmarks and History](2026-09-13-ios-bookmarks-history-design.md) and the [page menu](2026-09-12-ios-page-menu-design.md).

## 1. What this step adds

- **An assistant button** in the bottom bar. It opens the person's own ChatGPT, Claude, Gemini, Le Chat or Grok, on their own account.
- **The assistant over the page.** It fills everything above the bar, with a grabber, a header and the provider's own website.
- **Sign-in windows** that a provider's page opens appear over the assistant rather than as a tab hidden behind it, and go away when they close themselves.
- **Recovery.** A provider page that iOS ended in the background reloads its conversation instead of going blank.
- **Typing room.** The bar hides while the keyboard is up.
- **A copy confirmation** that never covers the provider's message box.
- **An honest Safari version.** The phone tells websites the Safari version its own iOS carries, instead of a number that stands in for a Mac's.

**Not in this step:**

| Left out | Why |
|---|---|
| Compare, Fill the Window | A phone is always filled, and Compare needs two readable columns. |
| Docking beside the page on a wide iPad | The phone's layer always fills. An iPad fills too, for now. |
| Reopening the exact thread after the app is fully quit | The provider's home opens instead, where recent chats sit in its sidebar. The September 3 spec's persistence is later work. |
| Early eviction on memory warnings, and the device memory instrument | Later, and "two assistants kept loaded" is not yet measured on a phone. |
| Passkeys inside the assistant | They wait on the Apple Developer Program, as they did on the Mac. |
| A "send to your assistant" action of any kind | Never. See §7. |

## 2. What the person sees and does (approved)

- **The button** sits immediately left of the tab count, the place `BottomBar.swift` reserved for it.
  - It shows two speech bubbles (`bubble.left.and.bubble.right`), the idea behind the Mac's own mark.
  - While the assistant is open it is lit: an accent-filled square with the glyph in `onAccent`, the Mac's active toolbar style.
  - Unlit, it takes the bar's current system tint, like its neighbours, until step 5 restyles the bar.
- **Opening:** the assistant slides up over the page and fills everything above the bar. It has a rounded top (`radius14`) and a grabber.
  - The header is on `bg2`. It holds the site's icon, the assistant's name with a chevron (a menu of `AICompanion.choices`, with a checkmark on the current one), "your own account", and × in a 30-point `bg3` circle inside a 44-point target. Its anatomy is Reader's touch header.
  - Below the header is the provider's own website.
- **Closing:** ×, a swipe down on the header, or the lit button again. It stays closed until it is opened.
- **Stepping aside.** Every door makes the assistant leave, because the phone never has room for both:
  - typing an address;
  - a bookmark or a history visit;
  - a link;
  - New Tab;
  - back or forward;
  - a link tapped inside the assistant, which opens in a tab as on the Mac.

  The button brings it back, and the conversation is still loaded.
- **Reader and Find in Page** from the menu also make it step aside, because both show the page it covers. Every other menu row acts on the page underneath, so **Copy for AI → the button → paste** takes two taps.
- **Which assistant** is the shared choice, remembered in the phone's own store.

## 3. The three calls taken with the canvas

1. **Typing.** The bar hides while the software keyboard is up, as Safari's does. The one exception is Find in Page, whose bar needs the keyboard, and it stays. The conversation keeps 54 points it would otherwise lose: 463 instead of 409 on the founder's iPhone, and 317 instead of 263 on an iPhone SE.
2. **The lit button** is Limeghost's accent, as on the Mac.
3. **The copy confirmation while the assistant is open.** The canvas showed the banner landing exactly on the provider's message box, the one place a person taps to paste.
   - While the assistant is open, the page notice sits in its own strip directly above the bar and pushes the assistant up for as long as it shows. It covers nothing of the provider's page.
   - While the assistant is closed, the notice floats over the page as it does today.
   - It is never placed under the provider's header, where "Copied 812 words." could read as "ChatGPT received 812 words."

## 4. Sign-in windows and recovery (shared)

**Sign-in windows.**
- Today a window a provider's page opens (`window.open`, which is how OAuth sign-in works) becomes a tab. On a phone that tab sits invisibly behind a full-screen assistant.
- `BrowserWorkspace.init` gains `assistantPopups: AssistantPopupPlacement = .tab`, with `.tab` and `.overAssistant`. The Mac passes nothing and keeps tabs. The phone passes `.overAssistant`.
  - That is a platform difference supplied by the host, like `pageSharing`, not a conditional in the shared layer.
- With `.overAssistant`, the popup's session is built from WebKit's own configuration, which keeps `window.opener` alive, and held as `AICompanion.popup`.
  - The phone draws it as a second layer over the assistant.
  - Its header shows the popup page's title, with its host beside it, and ×.
  - A link inside it opens a tab, like any link from the assistant.
- `BrowserSession` answers `webViewDidClose(_:)` with a new `onRequestClose`. A popup that closes itself after signing in dismisses its layer.
  - Nothing on the Mac sets `onRequestClose`, so a Mac tab is unaffected.
- The popup follows the assistant: hiding the assistant, for any reason, dismisses and tears down its popup.

**Recovery.**
- Today, when WebKit ends a page's process, the session records "This page stopped responding". Inside the assistant that shows as a blank frame, and iOS ends background processes routinely.
- `BrowserSession` gains `onWebContentProcessTerminated`, and `AICompanion` answers it for its own sessions:
  - An assistant **on screen** reopens its conversation's address at once, through `load(_:)`, the same way a parked conversation is reopened.
  - A **hidden** one is marked, and reopens when it is next shown.
  - A page that ends again within 30 seconds of an automatic reopen is **not** reopened again. Its failure stays on screen, so a page that dies as it loads cannot reload forever.
- The phone's assistant draws a session's failure over the web view, not instead of it, so the web view stays mounted. It shows the failure's own title and message, and a Reload button when the failure is retryable.
- The Mac's assistant gains the same automatic reopen, because it lives in the shared companion. Its panel draws no failure state, so a page that ends twice within 30 seconds still shows blank there, as it does today.

**The Safari version.**
- `BrowserUserAgent` reads Safari's version from `/Applications/Safari.app`, which a phone does not have, so the phone has been claiming a fixed "26.5" on any iOS version.
- The fallback becomes the operating system's own version (`ProcessInfo.operatingSystemVersion`, major and minor). On iOS that is the version of the Safari it carries.
- The Mac still reads its installed Safari first.
- Whether this is what Google's sign-in checks has not been tested. It is right either way.

## 5. Architecture

**Shared** (`LimeghostShared`; tested on macOS and the iPhone simulator)
- `AssistantPopupPlacement` and the `assistantPopups` parameter, used in the companion wiring in `BrowserWorkspace`.
- `AICompanion`:
  - `popup`, `presentPopup(_:)` and `dismissPopup()`;
  - the popup dismissed from `hide()`, from `makeRoomForPage()` when it leaves, and from `teardown()`;
  - the recovery bookkeeping (awaiting reload, last automatic reload), with the clock injected, defaulting to `Date.init`.
- `BrowserSession`: `onRequestClose` via `webViewDidClose(_:)`, and `onWebContentProcessTerminated`. Both are cleared in `teardown()`.
- `BrowserUserAgent`: the operating-system fallback.

**Phone** (`ios/Sources`)
- `WorkspaceHost`:
  - passes `.overAssistant`;
  - tells the companion once that this screen never shares (`setCanShareWindow(false)`), because the phone's layer never docks. Without it, a door would only un-expand an assistant still covering the page.
  - forwards the companion's changes, as it already forwards the workspace's.
- `AssistantLayer.swift` (new):
  - `AssistantLayer`, always in the same place in the view tree; it draws nothing while hidden.
  - `AssistantHeader`.
  - `AssistantPageView`: the web view keyed on `session.instanceID`, with the failure drawn over it.
  - `AssistantPopupLayer`.
  - `AssistantDismissal`: the pure swipe-to-close rule.
- `KeyboardObserver.swift` (new): whether the software keyboard is up, from `UIResponder`'s show and hide notifications.
- `BottomBar`: the button, and `BottomBarModel.isAssistantOpen`.
- `BrowserScreen`:
  - the page and the assistant in one `ZStack`;
  - `BottomChrome` deciding between the find bar, the bar, or nothing (a pure `BottomChromeContent`);
  - the notice either over the page or in the strip above the bar (a pure `NoticePlacement`).
- `PageMenuActions`: Reader (when opening) and Find in Page call `aiCompanion.makeRoomForPage()` first.

## 6. Testing

**Shared** (`CompanionBehaviorTests`, both destinations)
- A popup from the assistant still opens a tab by default: the Mac's behaviour, pinned.
- With `.overAssistant`, it becomes the companion's popup, adds no tab, and WebKit gets back the popup's own web view.
- A popup that closes itself (`webViewDidClose`) dismisses; hiding the assistant dismisses its popup.
- An assistant on screen whose page process ended reopens its conversation's address.
- A hidden one reopens when shown, and not before.
- A second ending within 30 seconds of an automatic reopen is left showing its failure; one after 30 seconds reopens again.
- `BrowserUserAgent`'s fallback is the operating system's own version.

**Phone** (`AssistantOnThePhoneTests`, new, and `PageMenuTests`)
- Opening a page while the assistant is open makes it leave: the phone never shares the screen.
- The host forwards the assistant's changes.
- Reader and Find in Page from the menu uncover the page.
- The bar button's model is lit while the assistant is open.
- `BottomChromeContent`: the find bar while finding, nothing while typing, the bar otherwise.
- `NoticePlacement`: over the page while the assistant is closed, above the bar while it is open.
- `AssistantDismissal`: a short drag stays, a long or fast one closes.

Every new test is watched failing before its code exists, and each task breaks its fix once on purpose.

**By hand, on the founder's iPhone** (listed, not yet run)
- Open, close, swipe down, choose another assistant.
- Sign in to ChatGPT, Claude and Gemini:
  - by email;
  - with "Continue with Google";
  - with "Continue with Apple".

  Record exactly which ones work.
- A link from the assistant opens a tab, and the button brings the assistant back.
- Copy for AI with the assistant open: the strip, then pasting.
- Typing: the bar hides, and returns when the keyboard goes.
- Background the app for a long while, come back, and see the conversation reload.
- Check it at iPhone SE size in the Simulator.

## 7. Unchanged, and still forbidden

Limeghost never types into the assistant, never presses its send button and never reads what it says. The clipboard is the deliberate gap between this app and a service it has no agreement with, and on iOS it stays a gap. There is no Shortcuts action, share-sheet target or button that "sends to your assistant", and no page action appears in the assistant's header. Assistants are ranked by which stayed on screen, never by what was read. "your own account" stays in the header.

## 8. Amending the September 3 spec

- **§5.1** said the phone's assistant would be the Mac's own `AICompanionPanel`. That panel uses macOS-only menu styles and the Mac's web view wrapper. The phone draws a thin phone-shaped layer over the same shared `AICompanion`, which keeps the spec's actual concern: one layer, in one place in the tree, never a sheet.
- **§5.2's docked iPad** is deferred: the phone's layer always fills.
- **§5.4** is built as written, with the popup's own close handled.
- **§5.5** is built in part (recovery), and its persistence and memory-warning eviction are deferred.
- **§4's accent ring** grouping Reader with the assistant toggle does not carry: on the phone, Reader lives in the menu.

## 9. Judgment calls

Made while writing this, without asking the founder. Each is small to reverse.

1. The bar hides whenever the keyboard is up, on pages as well as in the assistant. The exception is Find in Page.
2. A popup's header shows its page's title and host, not the word "Sign in": `window.open` is not always a sign-in.
3. A popup is dismissed whenever the assistant hides, including when a door makes it leave mid-sign-in.
4. The automatic reopen is limited to once per 30 seconds per assistant.
5. The failure state shows the shared wording, "WebKit ended the page process…". It names an engine ordinary people do not know, and changing it is a wording pass for both platforms.
6. The Safari version fix is in this step, because sign-in may depend on it.
7. Unlit, the button takes the bar's system tint until step 5.
8. On an iPad the assistant fills the screen, as on a phone.

## 10. Honesty

- Nothing here has been validated with an observed user.
- **Whether each provider's sign-in works inside the phone's web view has not been tested.** Passkeys will not work under free provisioning. Google may refuse sign-in in an in-app web view.
- The phone's bookmarks, history and assistant choice are the phone's own. Conversations live in the provider's account and appear after one sign-in.
- "Two assistants kept loaded" (`maximumLiveSessions`) was measured on a Mac, not on a phone.
