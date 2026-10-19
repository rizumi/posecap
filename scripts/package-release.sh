#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "Release packaging currently requires an Apple Silicon Mac." >&2
    exit 1
fi

# Extra arguments, such as --scratch-path, are forwarded to SwiftPM.
swift build -c release "$@"
bin_dir="$(swift build -c release --show-bin-path "$@")"
version="$("$bin_dir/posecap" --version)"
version="${version#posecap }"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a release version from posecap --version, got: $version" >&2
    exit 1
fi
if [[ "$(lipo -archs "$bin_dir/posecap")" != arm64 ]]; then
    echo "Expected an arm64 executable." >&2
    exit 1
fi

archive="posecap-${version}-macos-arm64.tar.gz"
mkdir -p dist
stage="$(mktemp -d "${TMPDIR:-/tmp}/posecap-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/bin"
cp "$bin_dir/posecap" "$stage/bin/posecap"
cp -R "$bin_dir/posecap_posecap.bundle" "$stage/bin/"
cp LICENSE "$stage/LICENSE"

# Accept both SwiftPM bundle layouts (native SwiftPM and Xcode build engines).
resource="$stage/bin/posecap_posecap.bundle/Contents/Resources/DeviceHub.applescript"
if [[ ! -f "$resource" ]]; then
    resource="$stage/bin/posecap_posecap.bundle/DeviceHub.applescript"
fi
cmp Sources/posecap/Resources/DeviceHub.applescript "$resource"
"$stage/bin/posecap" --version
"$stage/bin/posecap" --help > /dev/null
COPYFILE_DISABLE=1 tar -czf "dist/$archive" -C "$stage" bin LICENSE
(cd dist && shasum -a 256 "$archive" > "${archive}.sha256")
echo "Created dist/$archive and dist/${archive}.sha256"
