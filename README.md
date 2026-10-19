# posecap

A Swift CLI for capturing the currently displayed iOS Simulator screen across
device postures and orientations, with a static HTML report for visual review.
You open the screen to inspect; posecap handles capture and reporting. It does
not build, install, or navigate apps.

**Status:** experimental. iPad capture and reports have been validated.
iPhone Duo posture verification and orientation changes remain limited;
see [Known limitations](#known-limitations).

[![DayTrip capture report on iPhone Duo](docs/images/daytrip-preview.png)](docs/example/index.html)

The [example report](docs/example) contains two screens captured in six
posture/orientation combinations each on iPhone Duo. After cloning the
repository, run `open docs/example/index.html` to view it and filter by screen
or Portrait / Landscape. GitHub displays the HTML source rather than the report.

## Requirements

- macOS 26.0 or later and Xcode. Tested with macOS 26.6.2,
  Xcode 27.1 RC (27A9275), and Swift 6.4.
- A booted iPhone or iPad Simulator with the desired app screen already open.
- Posture and orientation changes require Device Hub 27.1 from the selected
  Xcode; other Device Hub versions are rejected. It must be running with its
  device window and sidebar accessible. Allow the launching terminal or app
  Accessibility access and Automation access to System Events and Device Hub
  in macOS Privacy & Security settings. GUI control requires an interactive
  desktop; do not interact with Device Hub during a capture.

`--current` captures without GUI control and does not require Device Hub 27.1
or those permissions.

## Install with mise

The release archive supports Apple Silicon Macs (arm64) and includes the
Device Hub resource bundle. Xcode is still required for Simulator capture.
Install [mise](https://mise.jdx.dev/getting-started.html) and activate it in your
shell, then install posecap:

```sh
mise use -g github:rizumi/posecap@0.1.0
posecap --version
```

To list available releases:

```sh
mise ls-remote github:rizumi/posecap
```

## Use

With exactly one eligible Simulator booted, capture its current screen and
create a report:

```sh
posecap devices
posecap capture --current --label Home
posecap report --input ./output
open ./output/index.html
```

To capture across iPhone Duo postures and orientations, or select one condition:

```sh
posecap capture --model "iPhone Duo" --label Home
posecap capture --model "iPhone Duo" --posture closed --orientation portrait
```

Select a device with `--model` (an exact device-type model name) or `--udid`
(a UUID from `devices`), but not both. Without either, exactly one eligible
Simulator must be booted. posecap never boots devices or launches apps.

## Capture options

| Option | Behavior |
| --- | --- |
| No condition filters | All three postures on iPhone Duo; portrait and landscape for each. Other iPhone/iPad models use portrait and landscape only. |
| `--posture closed\|half-open\|open` | Limit to one posture (iPhone Duo only). |
| `--orientation portrait\|landscape` | Limit to one orientation. Combine with `--posture` for one condition. |
| `--current` | Capture without changing posture or orientation; cannot be combined with condition filters. |
| `--label TEXT` | Screen name used by the report filter; repeated labels remain separate runs. |
| `--output PATH` | Save results under this directory (default: `./output`). |

Landscape means landscape-left. Half-open uses Device Hub's **Partially Open**
preset, without assuming a hinge angle. The final posture and orientation are
left in place; there is no automatic restoration.

## Results and reports

Each capture creates a new directory containing PNGs and `manifest.json`.
Partial captures retain saved files. For iPhone Duo posture captures, the
report defaults to the outer screen for Closed and the inner screen for
Partially folded / Fully open; the other saved display is omitted. If the display mapping
or requested posture is unavailable, it shows all saved displays. Failed,
mismatched, and incomplete captures remain visible. Capture diagnostics are
hidden by default; add `--details` when generating a report to include them.

`report --input ./output` combines the capture directories into `index.html`.
Add `--language ja` for Japanese or `--language en` for English (the default).
Use `--title "My App"` for the app name; capture `--label` values identify
screens in the filter. For example:
`posecap report --input ./output --title "My App" --language ja`.
Only the generated HTML is replaced; images and manifests are retained. Open
it locally and keep the capture directories alongside it when sharing. The
report works offline, with a small embedded script for instant screen and
orientation filters. With JavaScript disabled, all captures remain visible.
Results include Simulator identifiers and display names, so review them before
sharing. The bundled example uses an anonymized Simulator ID and readable
directory names (`spot-detail` and `itinerary`).

| Exit code | Meaning |
| --- | --- |
| 0 | All capture conditions verified, or another command completed successfully |
| 1 | GUI preparation failed, or capture has unverified, mismatched, failed, interrupted, or unattempted conditions |
| 2 | Argument, device selection, other setup, or report-generation error |

A successfully generated report can describe failed captures and still exit 0.
Generated results and logs are excluded from version control at the default
paths; exclude custom output directories yourself.

## Known limitations

- iPhone Duo posture and active-panel selection cannot currently be verified.
  Multiple built-in displays are all saved and marked unverified, even when
  the images look correct. Unverified captures exit nonzero.
- With Xcode 27.1 RC, half-open and open iPhone Duo captures can report an
  orientation mismatch after a named direction is selected. posecap checks the
  GUI readback and tries up to three right rotations to reach the requested
  direction. If it cannot confirm the direction, it stops before taking that
  screenshot and records the reason.
- Verified orientation describes Device Hub's reported state, not whether the
  app rotated its layout. Apps may restrict rotation.
- Capture does not verify app responsiveness. Open the intended screen and
  confirm it responds before starting a capture.
- The GUI adapter has been tested only with the Xcode build above and English
  control labels. Other builds, languages, and live capture on single-screen
  iPhones have not been verified.

See [design decisions](docs/design.md) for verification rules, storage details,
timeouts, and validation results.

## Build from source

Build from the repository using the selected Xcode toolchain:

```sh
swift build -c release
.build/release/posecap --help
swift test
```

The executable needs the adjacent SwiftPM resource bundle; copying the executable
alone is not supported. There are no third-party package dependencies.

Maintainers can run `bash scripts/package-release.sh` on an Apple Silicon Mac
to build an archive and SHA-256 checksum in `dist/`. The archive keeps
`bin/posecap` beside `bin/posecap_CaptureCore.bundle` and includes the license.

## License

[MIT](LICENSE).
