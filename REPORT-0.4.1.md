# REPORT 0.4.1: the split view, and the page it lives on, at every size

Version `0.4.1+17`, branch `main`. Baseline: `0.4.0` (a491181, "two sheets side by side").

Evidence rule: every PASS below comes from a screenshot of a real Chrome running the
0.4.1 web build (or, where it says so, from a `flutter test` run). Nothing is
"should work".

## The layout rules, per device

| width | rule | device used | result |
|---|---|---|---|
| >= 1000px | side by side, equal `Expanded`, 1px `Palette.hairline` divider | desktop 1440x900, 1920x1080; tablet landscape 1180x820 | PASS |
| 700-999px | side by side when each pane still gets its 340px, otherwise stacked | tablet portrait 820x1180, sidebar **collapsed** (each pane 409) -> side by side | PASS |
| < 700px | stacked, pane A on top, pane B below, hairline divider, each scrolls alone | phone 390x844, phone 360x780 | PASS |

| device | viewport | layout | verdict |
|---|---|---|---|
| Phone (iPhone 14 class, DPR 3, touch) | 390x844 | stacked | PASS |
| Phone (Android) | 360x780 | stacked | PASS (browser shot + widget test) |
| Tablet portrait (iPad Air class) | 820x1180 | stacked with the sidebar open, side by side once it is collapsed | PASS |
| Tablet landscape | 1180x820 | side by side | PASS |
| Desktop | 1440x900 | side by side | PASS |
| Desktop | 1920x1080 | side by side | PASS |

Screenshots (all under `C:\HermesHub\profiles\it-dog\projects\tallynote-responsive\`):

- `phone-split-on.png` — 390x844, real typing through the Flutter text area, both panes answering
- `phone-split-on-final.png` — 390x844, final build, both panes answering
- `phone-single-pane.png` — 390x844, split off, single pane unchanged
- `phone-settings.jpg` — 390x844, settings sheet (four tabs, Done button, nothing clipped)
- `phone-360-split-on.png` — 360x780 Android width
- `tablet-portrait-split-on.png` — 820x1180, sidebar open: stacked
- `tablet-portrait-split-side.png` — 820x1180, sidebar collapsed: side by side
- `tablet-landscape-split-on.png` — 1180x820: side by side
- `desktop-split-on.png` — 1440x900: side by side, sidebar open
- `desktop-1920-split-on.jpg` — 1920x1080: side by side
- `phone-0.4.0-*.png` — the pre-change baseline at 390x844 (single pane, settings, cheat sheet, file menu, drawer), kept for the before/after

## What was actually broken, and what changed

**1. The answer column ate the phone.** In 0.4.0 the column was a fixed 212px, so a
390px pane gave the text `390 - 212 - 54 - 48 = 76px`: the hint text broke into
five fragments (`phone-0.4.0-single.png`). `editorMetrics()` in `lib/ui/editor_view.dart`
now clamps the column so the text keeps 200px (`390 - 32 - 24 - 200 = 134` for the
answers), thins the gutter 54 -> 32 and the padding 24 -> 12 under 560px, and drops the
30px step-chevron gutter there (the whole answer cell already opens the steps). Desktop
is untouched: 1440 still gets exactly 212px and the 54/24 chrome.

**2. The breakpoint measured the window, not the editor.** `0.4.0` stacked when the
*window* was under 1000px. With the sidebar open on an 820px tablet the editor is only
569px, so two side-by-side panes were 284px each: the answer column collapsed to 28px and
the answers ran back over the text (that is what `tablet-portrait-split-on.png` looked like
before the fix). `_panesView(width)` now takes the editor area from a `LayoutBuilder` and
needs each pane >= 340px, so 820 with the sidebar open stacks, and stacks back into a row
the moment the sidebar is collapsed.

**3. The caret could sit under the keyboard.** Each pane now owns a `FocusNode`, and after
a keystroke, a focus change, or a change in the pane's height (keyboard, rotation, URL bar)
the pane scrolls the caret's line into view. Only the focused pane does it, so the other
sheet keeps its scroll position (`tapping one pane does not scroll the other`).
Offline proof: with `viewInsets.bottom = 300` the format bar's bottom edge is above the
keyboard (`the format bar stays above the keyboard on a phone`).

**4. `viewport-fit=cover` was missing.** Declared in `web/index.html` — and re-applied on
`flutter-first-frame`, because the engine *overwrites* the viewport tag at boot and drops
the flag. Verified in the browser: `document.querySelector('meta[name=viewport]').content`
is `width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover` at
runtime, not just in the file.

**5. Everything else in the list was checked on the live build and left alone**: the header
(menu, file, split, settings all fit at 390; titles ellipsise), the drawer, the tabs, the
status bar, the settings sheet (560px tall, fits a 844px screen, Done visible), the cheat
sheet table (no overflow at 342px of dialog), the file menu (7 items, on screen).
`100vh` is not used: Flutter sizes its own view from the visual viewport.

One thing that looked broken and was not: in an early phone screenshot the 繁/简 language
buttons and `乘` rendered as tofu. That is a font-download race in a headless browser —
the same dialog renders them once the Noto fallback arrives (`phone-0.4.0-cheatsheet2.png`).
No code change.

## The currency words (same push)

`5000 usd to hkd` already worked. Now:

- `->`, `→` and `=>` are conversion words (`Parser._arrowLength`). The two ASCII forms must
  be adjacent, so `5 - > 3` stays nonsense.
- `兌`, `換`, `換成`, `換算`, `轉`, `轉成`, `换算`, `转` are conversion words
  (`isConversionWord`), and they are in `_reserved` so a number in front of one is not read
  as a unit named after it.
- **A conversion word the parser cannot use leaves the line unanswered**: `parse()` throws
  `UnresolvedConversion`, and `SheetEngine` turns that into a line with no answer and no
  error text. `5000 usd 兌 hkd` used to print `$5,000.00`; it now prints `HK$39,000.00`,
  and `5000 usd 兌 znx` prints nothing at all instead of $5,000.00.

`test/engine_test.dart` covers usd/hkd in all thirteen spellings, cny and jpy in both
directions, and the no-answer direction. One existing expectation changed on purpose:
`test/accuracy_test.dart` used to assert `10500 in sci` = `10,500`. That is the same bug
in English (a trailing conversion word silently dropped), so it now asserts no answer.
It is the only behaviour change outside the listed words, and it is the README's
"no answer beats a wrong answer" rule.

## Gate

```
$ flutter analyze
No issues found! (ran in 5.6s)

$ flutter test
00:03 +143: All tests passed!
```

`test/responsive_test.dart` is new: 390 stacks, 820 with the sidebar open stacks and with
it closed sits side by side, 1440 sits side by side, both panes answer at 390/360/820/1180/1440
with no leak between them, `editorMetrics` keeps 200px of text at 390/360/320 and leaves
desktop alone, the format bar clears a 300px keyboard, and one pane's typing does not
scroll the other.

## Deployed build

See the block below (filled in after CI).

## Not tested

- **A real iPhone or iPad.** No iOS Safari here, so: the notch and home-indicator insets are
  implemented (`viewport-fit=cover` + the app's existing `SafeArea`) but not seen on glass;
  the software keyboard is proven by a widget test with `viewInsets` and by a real Chrome
  resize, not by a real keyboard. `Emulation.setDeviceMetricsOverride` with `mobile=true`
  is *not* iOS Safari.
- **PWA standalone mode.** Installing the app was out of scope for this run; the
  `viewport-fit=cover` path is the same code the standalone window uses.
- **Firefox and desktop Safari.**
- **Safari's dynamic toolbar.** Chrome's URL bar is fixed in emulation, so `dvh`-style
  resize behaviour on iOS was reasoned about, not observed.
