# posecap

Capture iOS Simulator screenshots across device postures and orientations,
then compare them in an offline HTML report.

Open the app screen you want to capture; posecap handles the screenshots and
report. It does not build, install, or navigate apps.

**Experimental:** iPad capture and reports have been validated. iPhone Duo
posture verification and orientation changes have
[known limitations](#known-limitations).

[![DayTrip capture report on iPhone Duo](docs/images/daytrip-preview.png)](docs/example/index.html)

The [example report](docs/example) shows two screens in six posture/orientation
combinations on iPhone Duo. After cloning the repository, run
`open docs/example/index.html` to view it. GitHub displays the HTML source.

## Requirements

- macOS 26.0 or later and Xcode.
- A booted iPhone or iPad Simulator with the app screen ready to capture.
- For posture and orientation changes: Device Hub 27.1 from the selected Xcode,
  running with its device window and sidebar accessible. Other versions are
  rejected.

GUI control requires an interactive desktop and Accessibility and Automation
permissions for the launching terminal or app. In macOS Privacy & Security,
allow access to System Events and Device Hub when prompted. Do not interact
with Device Hub during capture.

`--current` captures without GUI control and does not require Device Hub 27.1
or those permissions.

Tested with macOS 26.6.2, Xcode 27.1 RC (27A9275), and Swift 6.4.

## Install

### mise

With [mise](https://mise.jdx.dev/getting-started.html) installed and activated
in your shell:

```sh
mise use -g github:rizumi/posecap@0.1.0
posecap --version
```

Release binaries support Apple Silicon Macs (arm64) and include the required
resource bundle. Xcode is still required for Simulator capture. Use
`mise ls-remote github:rizumi/posecap` to list available versions.

### Build from source

```sh
git clone https://github.com/rizumi/posecap.git
cd posecap
swift build -c release
.build/release/posecap --help
```

To use `posecap` directly in the current shell:

```sh
export PATH="$PWD/.build/release:$PATH"
```

Keep the executable beside its SwiftPM resource bundle; copying the executable
alone is not supported. There are no third-party package dependencies.

## Usage

### Capture the current screen

With one eligible Simulator booted:

```sh
posecap devices
posecap capture --current --label Home
posecap report --input ./output
open ./output/index.html
```

`--current` saves the screen without changing posture or orientation.

### Capture postures and orientations

Capture all six iPhone Duo combinations, or select a single condition:

```sh
posecap capture --model "iPhone Duo" --label Home
posecap capture --model "iPhone Duo" --posture closed --orientation portrait
```

Without condition filters, iPhone Duo captures all three postures in portrait
and landscape. Other iPhone/iPad models capture portrait and landscape only.

Select a Simulator by its exact model name with `--model`, or by a UUID from
`posecap devices` with `--udid`. These options are mutually exclusive. Without
one, exactly one eligible Simulator must be booted.

### Capture options

| Option | Description |
| --- | --- |
| `--model NAME` | Select a booted Simulator by exact device-type model name. |
| `--udid UUID` | Select a booted Simulator by UUID. |
| `--current` | Capture without GUI changes. Cannot be combined with posture or orientation filters. |
| `--posture closed\|half-open\|open` | Capture one posture (iPhone Duo only). |
| `--orientation portrait\|landscape` | Capture one orientation. Can be combined with `--posture`. |
| `--label TEXT` | Set the screen name shown in the report. Repeated labels remain separate runs. |
| `--output PATH` | Set the output directory (default: `./output`). |

Landscape means landscape-left. Half-open uses Device Hub's **Partially Open**
preset without assuming a hinge angle. The final posture and orientation are
left in place.

### Generate a report

```sh
posecap report --input ./output --title "My App" --language en
```

The report combines capture runs into `index.html`, with filters for screen
labels and orientations. Use `--language ja` for Japanese and `--details` to
include capture diagnostics. English is the default.

For iPhone Duo, the report shows the outer screen for Closed and the inner
screen for Partially folded / Fully open. This is a presentation default,
not verification of the active display. Both images remain saved; if the
posture or display mapping is unavailable, all saved displays are shown.
Failed, mismatched, and incomplete captures retain visible status messages.

Run `posecap --help` for the command reference.

## Output

Each capture creates a new directory under `--output` containing PNG files and
`manifest.json`. Saved files are retained if a capture stops partway through.
Generating a report replaces only `index.html`; images and manifests are kept.

Reports work offline. Keep the capture directories alongside `index.html` when
sharing. Without JavaScript, all captures remain visible. Results include
Simulator identifiers and display names, so review them before sharing.

The default output directory and logs are ignored by Git. Add custom output
directories to your own ignore rules.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | All capture conditions verified, or another command completed successfully. |
| `1` | GUI preparation failed, or capture contains unverified, mismatched, failed, interrupted, or unattempted conditions. |
| `2` | Argument, device selection, other setup, or report-generation error. |

Report generation can succeed with exit code `0` even when the report contains
failed captures.

## Known limitations

- **iPhone Duo verification:** posture and active-panel selection cannot
  currently be verified. Both built-in displays are saved and captures remain
  unverified, even when the images look correct. Unverified captures exit `1`.
- **Orientation changes:** with Xcode 27.1 RC, half-open and open iPhone Duo
  captures can report a different orientation after a named direction is
  selected. posecap checks GUI readback and tries up to three right rotations.
  If it cannot confirm the requested direction, it stops before taking that
  screenshot and records the reason.
- **App behavior:** verified orientation describes Device Hub's reported state,
  not whether the app rotated its layout. Apps may restrict rotation. posecap
  does not verify responsiveness; check the app before starting a capture.
- **Compatibility:** GUI control has been tested only with the Xcode build
  listed above and English control labels. Other builds, languages, and live
  capture on single-screen iPhones have not been verified.

## Development

Run the automated tests:

```sh
swift test
```

Build a release archive and SHA-256 checksum in `dist/` on an Apple Silicon Mac:

```sh
bash scripts/package-release.sh
```

The archive includes `bin/posecap`, the adjacent
`bin/posecap_CaptureCore.bundle`, and `LICENSE`.

See [design decisions](docs/design.md) for verification rules, storage details,
and timeouts.

## License

[MIT](LICENSE).
