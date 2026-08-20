#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
configuration="${BFISH_CONFIGURATION:-release}"
identity="${BFISH_CODESIGN_IDENTITY:--}"
bundle_path="$project_root/.build/artifacts/bfish.app"
contents_path="$bundle_path/Contents"
binary_path="$(cd "$project_root" && swift build -c "$configuration" --show-bin-path)/bfish"

cd "$project_root"
swift build -c "$configuration"

mkdir -p "$contents_path/MacOS"
cp "$binary_path" "$contents_path/MacOS/bfish"
cp "$project_root/Resources/bfish-Info.plist" "$contents_path/Info.plist"
/usr/bin/codesign --force --options runtime --sign "$identity" "$bundle_path"

echo "$bundle_path"
if [[ "$identity" == "-" ]]; then
    echo "warning: ad-hoc signing is suitable for scaffolding but may not preserve TCC grants across rebuilds" >&2
fi
