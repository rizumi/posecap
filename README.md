# posecap

> [!WARNING]
> **Experimental** — posecap is under active development and has known limitations.
> Review the [known limitations](#known-limitations) before use.

Capture iOS Simulator screenshots across device postures and orientations,
then compare them in an offline HTML report.

Open the app screen you want to capture; posecap handles the screenshots and
report. It does not build, install, or navigate apps.

[![DayTrip capture report on iPhone Duo](docs/images/daytrip-preview.png)](docs/example/index.html)

To view the [example report](docs/example), clone the repository and run
`open docs/example/index.html`. GitHub displays the HTML source.

## Requirements

- An Apple Silicon Mac with macOS 26.0 or later and Xcode. Intel Macs are not supported.
- A booted iPhone or iPad Simulator with the app screen ready to capture.
- Device Hub 27.1 from the selected Xcode,
  with its device window and sidebar accessible, plus Accessibility and
  Automation permissions for the launching terminal or app.

Capture requires an interactive desktop; do not interact with Device Hub during capture.

Tested with macOS 26.6.2, Xcode 27.1 (27A9275), and Swift 6.4.

## Install

### mise

With [mise](https://mise.jdx.dev/getting-started.html) installed and activated:

```sh
mise use -g github:rizumi/posecap
```

To pin a version for a project instead, run
`mise use github:rizumi/posecap@<version>` in that project; mise records it in
the project's `mise.toml`.

### Build from source

```sh
git clone https://github.com/rizumi/posecap.git
cd posecap
swift build -c release
export PATH="$PWD/.build/release:$PATH"
```

Keep the executable beside its SwiftPM resource bundle; copying the executable
alone is not supported.

## Usage

With one Simulator booted, capture the prepared app across postures and
orientations, then open the report:

```sh
posecap devices
posecap capture --label Home
posecap report --input ./output
open ./output/index.html
```

Without `--output`, each capture creates a timestamped directory under `./output`.

Specify `--output` to save directly to a reusable directory:

```sh
posecap capture --label Home --output ./screenshots/home
posecap report --input ./screenshots/home
open ./screenshots/home/index.html
```

Repeating a capture in the same directory replaces matching images. Other files
remain, but the regenerated report includes only the latest run in that directory.
Regenerate the report after recapturing; use a different directory to keep history.

`report --input` accepts a single capture directory or a parent directory to
combine multiple captures. If the input is itself a capture, only that capture
is reported.

To capture across iPhone Duo postures and orientations:

```sh
posecap capture --model "iPhone Duo" --label Home
```

For iPhone Duo, capture saves the outer display when closed and the inner
display when partially folded or fully opened: one image per condition.
With an unknown display mapping, it saves all built-in displays.

Use `--posture` and `--orientation` to select a single condition:

```sh
posecap capture --model "iPhone Duo" --posture closed --orientation portrait
```

When multiple Simulators are booted, select one with `--model` or `--udid`.
The final posture and orientation are left in place.

GUI changes wait four seconds for settling. Each completed condition prints its
elapsed time; use `POSECAP_TRACE_TIMING=1 posecap capture ...` for command timings.

Reports work offline and can be filtered by screen, posture, and orientation.
Keep the images and capture directories alongside `index.html` when sharing.
Run `posecap --help` for commands or `posecap capture --help` and
`posecap report --help` for their options.

## Known limitations

- Captures succeed when images are saved. Missing posture or active-display
  readback does not cause an error.
- Simultaneous use of both iPhone Duo displays is not supported. The current
  capture and report workflow targets one display per posture.
- Orientation changes can fail on iPhone Duo. App rotation and responsiveness
  are not verified.
- GUI control has only been tested with the Xcode build above and English
  control labels; single-screen iPhone capture has not been verified.

## Roadmap

- [ ] Support apps that use both iPhone Duo displays simultaneously, with explicit
  display selection and side-by-side comparison in reports.

This is a future direction, with no release timeline yet.

## Development

Run the tests:

```sh
swift test
```

Build a release archive in `dist/` on an Apple Silicon Mac:

```sh
bash scripts/package-release.sh
```

See [design decisions](docs/design.md) for implementation details.

## License

[MIT](LICENSE).
