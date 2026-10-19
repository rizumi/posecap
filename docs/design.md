# Design decisions

Status: experimental MVP. Validated limits are recorded in the README.

## Scope

The Swift package provides a small CLI for capturing the currently displayed
iOS Simulator content under different device postures and orientations.
Application building, installation, navigation, taps, image comparison, and
layout assessment are outside its scope. Labels are optional annotations,
never scene names or unique identifiers. The project uses the MIT license.

An explicit static HTML report command is included in the MVP scope. Reports
consume saved capture results independently of Simulator control.

## Source organization

The package has one executable target, `posecap`, with an `@main` entry point
in `Sources/posecap/Posecap.swift`. Its internal types are tested directly by
`posecapTests`; a separate library target is not needed for the current CLI.

Directories group related responsibilities within that module:

- `CLI`: argument parsing, validation, command orchestration, and exit codes.
- `Capture`: capture planning, execution, manifests, and screenshot storage.
- `Simulator`: device models, discovery, simctl, and Device Hub control.
- `Report`: offline HTML generation and localization.
- `Support`: subprocess execution, file checks, and shared errors.
- `Resources`: the bundled Device Hub AppleScript adapter.

Argument Parser integration stays in `CLI`; capture planning operates on
device and posture types independently of command-line parsing. Tests follow
the same responsibility groups, with shared fixtures in `TestSupport`.
These directories do not impose module boundaries. Introduce another target
when reuse or enforced dependency boundaries justify an explicit API.

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
Legacy verified and unverified outcomes remain readable in existing manifests.

| Outcome | Meaning |
| --- | --- |
| Captured | Images were saved successfully; missing state readback does not prevent success. |
| Mismatched | An observed state differs from the requested condition. |
| Failed | An operation or image save failed. |

GUI selection proves only the state exposed by that GUI control. A successful
click alone does not prove selection or device posture. simctl UI Orientation
describes the reported display UI orientation; it is not an independent
measurement of physical device orientation. PNG dimensions describe the saved
raster only and do not verify folding, hinge angle, or application rotation.
Do not classify a black image as failed merely because it is black.

Save images even when state readback is unavailable. Diagnostic images for mismatched
conditions must not be presented as successful captures of the requested
condition. Reports always identify mismatched, failed, and incomplete results;
capture observations are included with `--details`. Retain already saved images
and metadata on partial failure.

Continue a batch only while the target and subsequent operations can still be
handled safely. Exit nonzero if any mismatched or failed conditions
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
display. For iPhone Duo with stable, recognized display roles, capture saves only
the outer display for closed posture and the inner display for half-open/open.
This selects a target from the requested posture; it does not verify which panel
is active. Current-state captures, unknown/ambiguous/changing role mappings, and
other models retain all built-in displays. Display IDs are resolved at runtime;
image brightness and power state do not drive selection. Both display inventories
remain in the manifest even when only one image is saved.

Consecutive successful conditions with the same requested posture retain the
previous posture instead of pressing its button and waiting again. This is
session-local dispatch reuse, not posture readback. Any failed condition clears
the reuse state. The manifest records reuse without claiming a new dispatch.

After posture changes, posecap reads Device > Orientation. A differing direction
after a posture dispatch, or unknown/face-up/face-down readback, permits one named
orientation request to reconcile the state. From fresh readback, posecap computes
the shortest sequence of Controls > Rotate Left / Rotate Right actions. A matching
orientation needs no action; other planar orientations need at most two turns.
Each turn settles and is read back before proceeding. A known unexpected result
stops the batch before images instead of continuing to rotate. If readback becomes
unknown, no further turns are attempted. Every dispatched action and its
before/after readback are recorded.

The Device menu is populated only while Device Hub is frontmost. The adapter
reads its checkmark before and after saving images. Agreement establishes the
Simulator orientation reported by Device Hub, with that source explicitly
recorded; it is not independent motion-sensor evidence or proof of app rotation.
Before capture, a known different selection must be corrected or the
condition fails without an image. Unknown readback permits capture. Missing
or changing readback after saving images is recorded without failing the capture;
a readback operation error fails the condition and stops the batch.
simctl UI Orientation never drives additional rotations. Fold state has no
GUI readback; the dispatched posture is assumed. Selecting a display from that
posture does not require active-display readback or populate `activeDisplayID`.

Each invocation gets a new UTC timestamp plus UUID capture directory. It contains
PNGs and a schema-versioned manifest updated after every image. Labels annotate
runs; they do not merge or replace them. `report` includes all immediate capture
subdirectories, sorts them by time, and replaces only generated `index.html`.
Images remain external files. Text is HTML-escaped, image paths are restricted
to regular PNG basenames within the run, and unknown schemas are rejected.

The manifest uses `schemaVersion: 1` and records requested conditions,
observations and their sources, per-display dimensions, and unattempted
conditions. Reports use a two-column card grid, ordered by posture then
orientation; omitted filter combinations appear as **Not requested**. Malformed
manifests, missing images, unsafe paths, and unknown schemas fail report
generation without replacing an existing report. User-created symlinks in result
paths are rejected. Use directories you control; concurrent hostile filesystem
changes are outside this implementation's scope. Capture is not atomic across
displays.

## Implementation boundaries

`Inventory` and `Options` select targets and plan conditions. `Simulator` wraps
simctl. `DeviceControlling` isolates Device Hub and its AppleScript resource.
`CaptureEngine` sequences operations and checkpoints metadata. `CaptureStore`
owns output creation and PNG decoding. `Report` only reads saved artifacts.
`ProcessRunner` uses argument arrays, bounded output files, cancellation, and
deadlines; it never constructs shell commands from labels or device names.

GUI operations validate the running Device Hub and Simulator inventory, then
check the selected target inside the operation's AppleScript. They do not run
an additional standalone AX target-check subprocess immediately beforehand.
Explicit checks before capture and the adapter's checks around mutations remain
in place. After capture, orientation readback also checks target identity, so a
separate target-check subprocess is needed only for posture-only conditions.
Each AppleScript operation resolves a unique sidebar row once, then rechecks
that row and the window title around actions. Row references never survive an
operation. Display enumeration records the state before changes, immediately
before images, and after images; current-state capture reuses the initial
enumeration for the pre-image state.

## Timing, failures, and exit codes

External commands have 30-second deadlines, with a 25-second Apple-event timeout.
GUI mutations settle for at least four seconds. Each orientation uses at most
two left/right turns driven only by GUI menu readback, with one named request
allowed first when no planar orientation is available or a posture dispatch leaves
a differing direction. Each turn uses the same settling delay and target checks.
Image dimensions and simctl UI Orientation never drive
correction. Screenshots are not retried. Fixed waiting does not prove
application readiness or animation completion; posecap does not launch apps or
verify application responsiveness.

Completed conditions print elapsed seconds. `POSECAP_TRACE_TIMING=1` writes
per-command durations to stderr, including failed commands, without device UUIDs
or output paths. This separates GUI and simctl overhead from settling waits.
Controls exposes both Rotate Left and Rotate Right even though the observed
toolbar exposes only Rotate Right. Both menu items are checked during preparation.
Rotation opens the Controls menu before selecting its item. A successful click
was observed without a corresponding orientation change immediately after folding,
including with the menu open. The named request after a posture change reconciles
that transition; the readback check catches a failed turn before screenshots.

Exit codes are 0 for complete captures or successful non-capture commands,
1 for GUI preparation failures or incomplete/mismatched/failed captures,
and 2 for selection, argument, other setup, or report failures. During capture,
SIGINT/SIGTERM terminate the active child process and retain checkpointed results.
An uncatchable termination or storage failure can leave a
running/pending manifest; the report shows it as incomplete, never successful.

## Device Hub observations (Xcode 27.1)

These observations describe the Device Hub build named in the README. They are
adapter assumptions, not Simulator API guarantees.

- simctl lists iPhone Duo and iPad simulators, documents per-display
  screenshots, and enumerates displays. Both iPhone Duo internal framebuffer
  ports can report power On, so that field alone cannot identify the active
  panel.
- The posture buttons expose semantic AXHelp labels `Closed`, `Partially Open`,
  and `Open`, but no value or selected state. Dispatching them cannot by itself
  provide fold-state readback.
- The selected sidebar row exposes a display name, OS version, and `Simulator`
  label, but no UDID. Name/version reconciliation must reject duplicates in both
  the Simulator inventory and the GUI.
- With Device Hub frontmost, Device > Orientation lists Portrait, Portrait
  Upside Down, Landscape Left, Landscape Right, Face Up, and Face Down, and
  `AXMenuItemMarkChar` exposes a checkmark for the selected item. This readback
  replaces any UI-Orientation-driven rotation loop.
- For half-open and open iPhone Duo, a direct named orientation request can be
  followed by checkmark readback that differs from the request, even after long
  settling waits or a repeated selection. Relative Controls-menu rotations correct
  the reported state after that request. They are used directly between conditions
  with the same posture; no model-specific offset is hard-coded. Rotate Right
  advances Portrait → Landscape Right → Portrait Upside Down → Landscape Left;
  Rotate Left reverses that order.
- A full per-element attribute walk is too slow for routine use. Prefer bounded,
  scoped reads with deadlines on both inspection and action subprocesses.

Reference implementations provide useful context without being dependencies:

- [Appium iPhone Duo support](https://appium.github.io/appium-xcuitest-driver/latest/guides/duo/)
- [agent-device commands](https://github.com/callstack/agent-device/blob/main/website/docs/docs/commands.md)
- [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/)

## Apple references

- [Interacting with your app in Device Hub](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub)
- [Prepare your app for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)

## Report display defaults

For the observed iPhone Duo configuration, capture and report share the rule
that selects the outer screen for closed posture and the inner for half-open/open.
It resolves runtime display IDs from the recorded `deviceName` roles:
`primary` (outer) and `primary-1` (inner), as observed with Xcode 27.1.
These names are an observed convention for this adapter, not a universal
Simulator API guarantee. Display IDs such as 1 and 3 are never hard-coded.

New posture-based captures save only the selected display. Existing captures
with both images remain readable and show the same preferred image. No
alternate-display viewer or dual-display mode is implemented. Unknown
or ambiguous roles, changing role mappings, a missing preferred image, other
models, or a current-state capture without requested posture fall back to
showing all saved images. Labels are never parsed to infer posture.

Report generation does not establish the active display, modify the manifest,
or change capture exit codes. Capture details, technical captions, and run IDs are
hidden by default. `report --details` includes diagnostic information, but does
not enable alternate-display presentation. Failed, mismatched, and incomplete
captures always keep visible status messages. Original evidence remains in the
manifest. Report generation uses saved files without recapturing or processing
image pixels; capture and report latency are product priorities.

## Future: simultaneous dual-display use

Consider workflows where an app presents content on both iPhone Duo displays
at once. Determine what runtime evidence identifies such use and how the report
should offer synchronized comparison, display selection, and explicit overrides.
The current posture-based default targets single-display review; it must not
be treated as proof that the other screen is inactive. Simultaneous dual-display
capture and comparison are roadmap items with no committed release timeline.
Captures that saved only one display cannot recover the other panel later;
dual-display review will require a new capture with that future mode enabled.

## Report languages

`report --language en|ja` selects English (default) or Japanese for report
headings, conditions, statuses, and evidence labels. The HTML `lang` attribute
follows that selection. Posture names use **Closed / Partially folded / Fully
opened** in both languages. All posture
cards share the same border style. CLI and manifest values remain `closed`,
`half-open`, and `open`.

Orientation headings and filters use **Portrait / Landscape** in both languages.
Landscape capture remains Landscape Left; exact Left/Right readback appears in
diagnostics and mismatch messages. A mismatch includes the requested and
observed orientation/posture, so readers can identify the discrepancy instead
of interpreting a status word. User labels, original diagnostic messages,
command/control names, and raw external error text retain their original
language. Generating another language changes only `index.html`; capture
metadata and PNGs remain unchanged.

## Report title and filters

`report --title` supplies an app-level heading independently of capture labels.
Without it the localized heading is “Capture report.” Capture labels identify
screens; repeated labels share one filter option but retain separate runs.
The initial view includes every screen, posture, and orientation. Native select
controls combine all three filters on the saved cards. The posture filter appears
when at least one run requests a posture and includes Closed, Partially folded,
and Fully opened. Mixed reports include a Current / unspecified posture option;
current captures also have an unspecified orientation option. Unrequested cards
carry the same posture and orientation fields as captured cards. No posture or
orientation is inferred from image dimensions.

Filtering uses a fixed embedded script authorized by its SHA-256 CSP hash.
Labels and titles are HTML-escaped and never interpolated into JavaScript.
No network requests, external scripts, image processing, or recapture are
needed. Without JavaScript the controls stay hidden and all report content
remains visible. Failed/incomplete status remains attached to the relevant
screen and conditions when filtering. posecap branding appears only in the
footer.
