# Repository guidance

## Project context

- posecap is a Swift CLI for capturing iOS Simulator screenshots across device postures and orientations and generating offline HTML reports.
- See [README.md](README.md) for usage, environment requirements, and known limitations; see [docs/design.md](docs/design.md) for architecture and behavioral details.
- Keep capture orchestration, Simulator/Device Hub control, artifact storage, and report generation in their existing layers. Update the relevant documentation when user-visible behavior changes.

## Validation

- Run `swift test` for code changes. Add regression coverage for changed behavior where useful; documentation-only changes need content and diff checks rather than a test run.
- When changing GUI control, distinguish automated tests with fake controllers from live Simulator verification. Report what was actually checked and any live verification that remains unperformed.

## Behavior to preserve

- Preserve report compatibility with existing supported manifests and captures. Reject unsupported schemas explicitly.
- Keep unrelated files and older images when recapturing. Replace matching PNGs only after successful decoding, using atomic writes; replace the manifest with the current run's results.
- Generate reports from manifest-referenced images only. Preserve path validation, symlink rejection, HTML escaping, and the existing report when generation fails.
- Keep requested conditions distinct from observed state. A dispatched GUI action or saved screenshot does not prove app rotation or active-display state.

## Change workflow

- Make changes on a working branch; do not push directly to `main`.
- Create a pull request, then have a sub-agent review it.
- Evaluate review findings, fix actionable issues, and explain any findings not adopted. Have a sub-agent re-review fixes that change behavior or address correctness/safety findings; repeat until no blocking findings remain.
- Merge only after the latest changes have passed relevant checks and review, with no unresolved blocking findings. Report the PR, validation results, and material limitations.
