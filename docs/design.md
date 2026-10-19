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
condition. Reports always identify mismatched, failed, and incomplete results;
unverified status is included with `--details`. Retain already saved images
and metadata on partial failure.

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

The Device menu is populated only while Device Hub is frontmost. The adapter
reads its checkmark before and after saving images. Agreement establishes the
Simulator orientation reported by Device Hub, with that source explicitly
recorded; it is not independent motion-sensor evidence or proof of app rotation.
Before capture, a different or unknown selection must be corrected or the
condition fails without an image. Missing or changing readback after saving
images remains unverified when readback returns an unknown or changed value;
a readback operation error fails the condition and stops the batch.
simctl UI Orientation never drives additional rotations. Fold state has no
GUI readback and stays unverified. iPhone Duo also
retains an unverified active-display status when both panels are enumerated.

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
Explicit checks around capture and the adapter's checks around mutations remain
in place.

## Timing, failures, and exit codes

External commands have 30-second deadlines, with a 25-second Apple-event timeout.
GUI mutations settle for at least four seconds. Each orientation is requested
once through its named menu item, followed by at most three corrective right
turns driven only by GUI menu readback. Each turn uses the same settling delay
and target checks. Image dimensions and simctl UI Orientation never drive
correction. Screenshots are not retried. Fixed waiting does not prove
application readiness or animation completion; posecap does not launch apps or
verify application responsiveness.

Exit codes are 0 for complete verified captures or successful non-capture commands,
1 for GUI preparation failures or incomplete/unverified/mismatched/failed captures,
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
  produce a verified fold result.
- The selected sidebar row exposes a display name, OS version, and `Simulator`
  label, but no UDID. Name/version reconciliation must reject duplicates in both
  the Simulator inventory and the GUI.
- With Device Hub frontmost, Device > Orientation lists Portrait, Portrait
  Upside Down, Landscape Left, Landscape Right, Face Up, and Face Down, and
  `AXMenuItemMarkChar` exposes a checkmark for the selected item. This readback
  replaces any UI-Orientation-driven rotation loop.
- For half-open and open iPhone Duo, a direct named orientation request can be
  followed by checkmark readback that differs from the request, even after long
  settling waits or a repeated selection. Relative toolbar rotations change the
  reported state. The bounded GUI-readback correction loop exists for this;
  no model-specific offset is hard-coded.
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

For the observed iPhone Duo configuration, the report presents the outer
screen for a requested closed posture and the inner screen for half-open/open.
It resolves runtime display IDs from the recorded `deviceName` roles:
`primary` (outer) and `primary-1` (inner), as observed with Xcode 27.1.
These names are a presentation convention for this adapter, not a universal
Simulator API guarantee. Display IDs such as 1 and 3 are never hard-coded.

Both images remain saved, but only the preferred image is included in the
report. No alternate-display viewer or dual-display mode is implemented. Unknown
or ambiguous roles, changing role mappings, a missing preferred image, other
models, or a current-state capture without requested posture fall back to
showing all saved images. Labels are never parsed to infer posture.

This default does not establish the active display, modify the manifest, or
change capture exit codes. Capture details, technical captions, and run IDs are
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
be treated as proof that the other screen is inactive. Keeping both original
images preserves the material needed for future dual-display presentation.

## Report languages

`report --language en|ja` selects English (default) or Japanese for report
headings, conditions, statuses, and evidence labels. The HTML `lang` attribute
follows that selection. Posture names use **Closed / Partially folded / Fully
open** in both languages, following the HIG figure terminology. All posture
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
The initial view includes every screen and orientation. Native select controls
filter the saved cards in place. Current captures have an explicit unspecified
orientation option; no orientation is inferred from image dimensions.

Filtering uses a fixed embedded script authorized by its SHA-256 CSP hash.
Labels and titles are HTML-escaped and never interpolated into JavaScript.
No network requests, external scripts, image processing, or recapture are
needed. Without JavaScript the controls stay hidden and all report content
remains visible. Failed/incomplete status remains attached to the relevant
screen and conditions when filtering. posecap branding appears only in the
footer.
