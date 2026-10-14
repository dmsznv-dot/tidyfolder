#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
action="${1:-test}"
if [ "$#" -gt 0 ]; then shift; fi
flags=(--disable-sandbox --scratch-path .build-working --cache-path .build/cache --config-path .build/config --security-path .build/security)
developer="$(xcode-select -p)"
if [[ "$developer" == *CommandLineTools ]]; then
  framework_dir="$developer/Library/Developer/Frameworks"
  flags+=(-Xswiftc -F -Xswiftc "$framework_dir" -Xlinker -F -Xlinker "$framework_dir" -Xlinker -rpath -Xlinker "$framework_dir")
  if [ "$action" = test ]; then
    flags+=(--disable-xctest --enable-swift-testing --no-parallel -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
  fi
fi
exec swift "$action" "${flags[@]}" "$@"
