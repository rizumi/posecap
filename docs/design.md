# Design decisions

Status: experimental MVP implemented and validated within the limits recorded in README.

## Scope

The Swift package provides a small CLI for capturing the currently displayed
iOS Simulator content under different device postures and orientations.
Application building, installation, navigation, taps, image comparison, and
layout assessment are outside its scope. Labels are optional annotations,
never scene names or unique identifiers. The project uses the MIT license.

An explicit static HTML report command is included in the MVP scope. Reports
consume saved capture results independently of Simulator control.

## Simulator control

Use simctl for Simulator discovery, display enumeration, and PNG
capture. Device Hub GUI automation handles rotation and folding.
Keep GUI control separate so it can later be replaced without changing capture
storage and report generation.

Fail closed if the selected Simulator or GUI control cannot be identified
unambiguously. Use semantic control labels and discover display IDs at runtime;
avoid positional button selectors and hard-coded screen IDs.

Document macOS Accessibility and Automation permissions, Device Hub availability,
UI-language requirements, and tested Xcode versions. GUI automation is subject
to Xcode UI changes; capability discovery must not claim unknown support as
supported or unsupported.

## Evidence and outcomes

Preserve requested conditions separately from observations and their sources.

| Outcome | Meaning |
| --- | --- |
| Verified | Available evidence establishes agreement with the requested condition. |
| Unverified | The change was dispatched, but evidence is insufficient to establish agreement. |
| Mismatched | An observed state differs from the requested condition. |
| Failed | An operation or image save failed. |

GUI selection proves only the state exposed by that GUI control. A successful
click alone does not prove selection or device posture. simctl UI Orientation
describes the reported display UI orientation; it is not an independent
measurement of physical device orientation. PNG dimensions describe the saved
raster only and do not verify folding, hinge angle, or application rotation.
Do not classify a black image as failed merely because it is black.

Save images for unverified conditions. Diagnostic images for mismatched
conditions must not be presented as successful captures of the requested
condition. Reports explicitly identify unverified, mismatched, and failed
results. Retain already saved images and metadata on partial failure.

Continue a batch only while the target and subsequent operations can still be
handled safely. Exit nonzero if any unverified, mismatched, or failed conditions
remain. Stop GUI mutations when target or control identity becomes uncertain.

## Capture contract

No boot command or automatic boot is included. Capture requires an available,
booted iPhone/iPad. Model selectors use device-type model names, not custom
Simulator names. An omitted selector requires exactly one eligible booted device.
GUI identity also requires a unique display-name/OS pairing across the full
inventory, including shutdown devices, and a matching selected GUI row and title.

The default matrix is closed/portrait, closed/landscape, half-open/portrait,
half-open/landscape, open/portrait, open/landscape for iPhone Duo; other iPhone/iPad
models use portrait and landscape. Landscape is left. Posture/orientation filters
narrow this matrix. `--current` captures without mutations and excludes filters.
Half-open refers to the GUI preset, not a measured angle. No restoration occurs.

Only built-in displays are captured. When one is listed it is the sole eligible
display. Multiple built-in displays are all retained; no active panel is inferred
from a requested posture, a fixed display ID, power state, or image brightness.
Orientation is first requested through Device > Orientation. If GUI readback
reports a different planar orientation, posecap uses the semantically identified
Rotate Right control up to three times, waiting and reading the menu after each
turn. It stops as soon as the requested orientation matches. Unknown or face-up/
face-down readback does not trigger blind rotations; target identity or control
failures stop the batch. If the requested orientation still cannot be confirmed,
the condition fails before any screenshot and the batch stops. Every corrective
action is recorded.
The menu is dynamically available only when Device Hub is frontmost. The adapter
reads its checkmark before and after saving images. Agreement establishes the
Simulator orientation reported by Device Hub, with that source explicitly
recorded; it is not independent motion-sensor evidence or proof of app rotation.
Before capture, a different or unknown selection must be corrected or the
condition fails without an image. Missing or changing readback after saving
images remains unverified. simctl UI Orientation never drives additional rotations. Fold state
has no GUI readback in the observed version and stays unverified. iPhone Duo also
retains an unverified active-display status when both panels are enumerated.

Each invocation gets a new UTC timestamp plus UUID capture directory. It contains
PNGs and a schema-versioned manifest updated after every image. Labels annotate
runs; they do not merge or replace them. `report` includes all immediate capture
subdirectories, sorts them by time, and replaces only generated `index.html`.
Images remain external files. Text is HTML-escaped, image paths are restricted
to regular PNG basenames within the run, and unknown schemas are rejected.

The manifest uses `schemaVersion: 1` and records requested conditions,
observations and their sources, per-display dimensions, and unattempted
conditions. Reports use a two-column card grid, ordered by posture then orientation; omitted filter
combinations appear as **Not requested**. Malformed manifests, missing images,
unsafe paths, and unknown schemas fail report generation without replacing an
existing report. User-created symlinks in result paths are rejected. Use
directories you control; concurrent hostile filesystem changes are outside
this implementation's scope. Capture is not atomic across displays.

## Implementation boundaries

`Inventory` and `Options` select targets and plan conditions. `Simulator` wraps
simctl. `DeviceControlling` isolates Device Hub and its AppleScript resource.
`CaptureEngine` sequences operations and checkpoints metadata. `CaptureStore`
owns output creation and PNG decoding. `Report` only reads saved artifacts.
`ProcessRunner` uses argument arrays, bounded output files, cancellation, and
deadlines; it never constructs shell commands from labels or device names.

## Timing, failures, and exit codes

External commands have 30-second deadlines, with a 25-second Apple-event timeout.
GUI mutations settle for at least four seconds. Each orientation is requested
once through its named menu item, followed by at most three corrective right
turns driven only by GUI menu readback. Each turn uses the same settling delay
and target checks. Image dimensions and simctl UI Orientation never drive
correction. Screenshots are not retried.
Fixed waiting does not prove application readiness or animation completion.

Exit codes are 0 for complete verified captures, 1 for incomplete/unverified/
mismatched/failed captures, and 2 for pre-capture selection/argument/setup errors
or report failures. SIGINT/SIGTERM terminate the active child process and retain
checkpointed results. An uncatchable termination or storage failure can leave a
running/pending manifest; the report shows it as incomplete, never successful.

## Initial observations

On macOS 26.6.2 with Xcode 27.1 RC (27A9275) and Swift 6.4, simctl lists
iPhone Duo and iPad simulators. Its regular IO help documents per-display
screenshots and display enumeration. Both iPhone Duo internal framebuffer ports can
report power On, so that field alone cannot identify the active panel.
These are discovery observations, not end-to-end capture verification.

Read-only Device Hub Accessibility inspection found semantic AXHelp labels
`Closed`, `Partially Open`, and `Open` on the relevant buttons.
Their reported values and selected states were absent. Dispatching these
buttons therefore cannot by itself produce a verified fold result. The
selected sidebar row exposes a display name, OS version, and `Simulator` label;
the inspected row did not expose a UDID. Any name/version reconciliation must
also reject duplicates in both Simulator inventory and the GUI.

A full per-element attribute walk was too slow for routine use. Prefer bounded,
scoped reads, with deadlines on both inspection and action subprocesses.

Reference implementations provide useful context without being dependencies:

- [Appium iPhone Duo support](https://appium.github.io/appium-xcuitest-driver/latest/guides/duo/)
- [agent-device commands](https://github.com/callstack/agent-device/blob/main/website/docs/docs/commands.md)
- [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/)

A later inspection with Device Hub frontmost found Device > Orientation with
Portrait, Portrait Upside Down, Landscape Left, Landscape Right, Face Up, and
Face Down. AXMenuItemMarkChar exposes a checkmark for the selected orientation.
This replaced the provisional UI-Orientation-driven relative-rotation loop.

Live research also reproduced half-open and open iPhone Duo mismatches between a direct menu
request and subsequent checkmark readback, including after a 16-second settling
wait for half-open. Repeating the same named selection and explicitly expanding the menu did
not remove it. Relative toolbar rotations changed the reported state but did not
establish a consistently reliable correction sequence in the initial research.
The current implementation adds a bounded GUI-readback correction loop rather
than a hard-coded model offset. If orientation is still different or unknown after correction, capture stops
without saving an image for that condition. Older mismatched results remain
readable in reports; requested conditions are never relabeled.

## Validation outcome

Initial validation used macOS 26.6.2, Xcode 27.1 RC (27A9275), and Swift 6.4.
Debug/release builds and 17 unit tests passed during that validation.
Live iPhone Duo matrix capture retained 12 images across all six conditions, reporting unverified closed conditions and
mismatched half-open/open orientations. Live iPad portrait/landscape and a separate
UDID-selected current capture completed with matching GUI readback where requested.
A prior interrupted iPhone Duo run remains distinguishable from the completed run.
The iPad test used an iPad Pro 13-inch (M5) on iOS 27.0; the iPhone Duo
used iOS 27.1. Saved PNGs were visually inspected, and static HTML was rendered
from a local file in headless Chrome. These observations do not establish
compatibility with every application's rotation behavior.

Automated tests cover selection, condition planning, evidence classification,
partial failure, cancellation, safe paths, HTML escaping, metadata validation,
and subprocess deadlines. Mock tests do not establish GUI compatibility.
Replacement/overwrite behavior remains deferred.

The correction/report update passes 24 unit tests and a release build. After
restarting Device Hub and the iPhone Duo Simulator, a half-open landscape capture
reached Landscape Left after three corrective right rotations, with matching
menu readback before and after capture. Its inner PNG was 2853 × 2007. DayTrip's
Save/Unsave action was checked before and after that capture to confirm UI
responsiveness. An earlier session showed a dimmed retained screen and a stalled
app-launch request; a running process alone was not sufficient evidence of app
readiness. posecap does not launch apps or verify application responsiveness.

The subsequent full DayTrip matrix completed all six conditions with 12 PNGs.
All six had matching requested/before/after orientation readback, and each
report's default PNG had the expected portrait/landscape dimensions. Closed
conditions needed no correction; half-open/open conditions each used three
right rotations. There were no mismatched or failed conditions in this run.
Posture and active-panel evidence remain unverified. The public Japanese report
uses this new run; it does not reclassify the earlier mismatched captures.

## Apple references

- [Interacting with your app in Device Hub](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub)
- [Prepare your app for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)

## Report display defaults

For the observed iPhone Duo configuration, the report presents the outer
screen for a requested closed posture and the inner screen for half-open/open.
It resolves runtime display IDs from the recorded `deviceName` roles:
`primary` (outer) and `primary-1` (inner), as observed with Xcode 27.1 RC.
These names are a presentation convention for this adapter, not a universal
Simulator API guarantee. Display IDs such as 1 and 3 are never hard-coded.

Both images remain saved, but only the preferred image is included in the
report. No alternate-display viewer or dual-display mode is implemented. Unknown or
ambiguous roles, changing role mappings, a missing preferred image, other
models, or a current-state capture without requested posture fall back to
showing all saved images. Labels are never parsed to infer posture.

This default does not establish the active display, modify the manifest, or
change capture exit codes. Capture details, technical captions, and run IDs are
hidden by default. `report --details` includes diagnostic information, but does
not enable alternate-display presentation. Failed, mismatched, and incomplete
captures always keep visible status messages. Original evidence remains in the
manifest. Report generation uses saved files without recapturing or processing
image pixels; capture and report latency are product priorities.

GUI operations validate the running Device Hub and Simulator inventory, then
check the selected target inside the operation's AppleScript. They do not run
an additional standalone AX target-check subprocess immediately beforehand.
The explicit checks around capture and the adapter's checks around mutations
remain in place. Settling intervals are unchanged until shorter waits can be
validated against actual app rendering.

## Future: simultaneous dual-display use

Consider workflows where an app presents content on both iPhone Duo displays
at once. Determine what runtime evidence identifies such use and how the report
should offer synchronized comparison, display selection, and explicit overrides.
The current posture-based default targets single-display review; it must not
be treated as proof that the other screen is inactive. Keeping both original
images preserves the material needed for future dual-display presentation.

## Report languages

`report --language en|ja` selects English (default) or Japanese for report headings,
conditions, statuses, and evidence labels. The HTML `lang` attribute follows that
selection. Posture names use **Closed / Partially folded / Fully open** in both languages,
following the HIG figure terminology. All posture cards share the same border
style. CLI and manifest values remain `closed`, `half-open`, and `open`.
Orientation headings and filters use **Portrait / Landscape** in
both languages. Landscape capture remains Landscape Left; exact Left/Right
readback appears in diagnostics and mismatch messages. A mismatch includes the
requested and observed orientation/posture,
so readers can identify the discrepancy instead of interpreting a status word.
User labels, original diagnostic messages, command/control names, and raw external
error text retain their original language. Generating another language changes
only `index.html`; capture metadata and PNGs remain unchanged.

## Report title and filters

`report --title` supplies an app-level heading independently of capture labels.
Without it the localized heading is “Capture report.” Capture labels identify
screens; repeated labels share one filter option but retain separate runs.
The initial view includes every screen and orientation. Native select controls
filter the saved cards in place. Current captures have an explicit unspecified
orientation option; no orientation is inferred from image dimensions.

Filtering uses a fixed embedded script authorized by its SHA-256 CSP hash.
Labels and titles are HTML-escaped and never interpolated into JavaScript.
No network requests, external scripts, image processing, or recapture are needed.
Without JavaScript the controls stay hidden and all report content remains visible.
Failed/incomplete status remains attached to the relevant screen and conditions
when filtering. posecap branding appears only in the footer.

The title/filter update passed 25 unit tests. Headless Chrome checks exercised
both sample labels, combined portrait/landscape filters, restoring all captures,
a 390-pixel viewport, and the JavaScript-disabled fallback without browser
errors. The eight-condition sample report generated in approximately 0.49
seconds on the development machine; this is a single-run observation, not a
cross-machine performance guarantee.

The itinerary sample was subsequently expanded to the same six conditions as
the detail screen, giving 12 visible cards. Returning to a list in the original
split view exposed its empty detail pane after some fold/orientation changes.
DayTrip now presents its unselected itinerary as a native NavigationStack and
returns to the adaptive split view when a stop is selected. The replacement
itinerary run completed all six conditions with matching before/after requested
orientation readback. Its default images were inspected for actual list content.
The browser filter checks now cover 12 cards, six per screen and three per
screen/orientation combination. Portrait/Landscape labels are English in both
report languages; the captured landscape direction remains Left.
