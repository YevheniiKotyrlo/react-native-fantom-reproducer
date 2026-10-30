#!/usr/bin/env bash
# Clones React Native at <ref>, builds Fantom's tester as its CI does, and runs one case inside the image the
# Dockerfile beside this script defines. Usage: run-case.sh <case> <ref>
set -euo pipefail
case_name="$1"
ref="$2"

git clone --quiet --depth 1 --branch "$ref" https://github.com/react/react-native /react-native
cd /react-native
echo "react-native $(git rev-parse HEAD), committed $(git log -1 --format=%cI)"
clang --version | head -n 1
yarn install --frozen-lockfile --non-interactive --silent

# Gradle writes the tester's compiler output to its reports, so a failed build prints the errors there.
build() {
  if ! yarn workspace @react-native/fantom build; then
    grep --no-filename --extended-regexp 'error:|undefined (symbol|reference)' private/react-native-fantom/build/reports/*.log | head -n 40
    exit 1
  fi
}

# folly's leak annotations, which AddressSanitizer builds of folly call, are defined in SanitizeLeak.cpp.
add_folly_sanitize_leak() {
  sed -i 's#^\( *\)folly/memory/SanitizeAddress.cpp$#&\n\1folly/memory/SanitizeLeak.cpp#' \
    private/react-native-fantom/tester/third-party/folly/CMakeLists.txt
}

asan_flags=(
  "CFLAGS=-fsanitize=address -fno-omit-frame-pointer"
  "CXXFLAGS=-fsanitize=address -fno-omit-frame-pointer -Wno-error=deprecated-literal-operator"
  "LDFLAGS=-fuse-ld=lld -fsanitize=address"
)

case "$case_name" in
  build)
    # Fantom's CI build, with the latest Clang.
    build
    ;;
  asan-folly-sanitize-leak)
    # The same build under AddressSanitizer, with nlohmann_json's warning kept from being an error.
    export "${asan_flags[@]}"
    build
    ;;
  asan-jsi-twice)
    # The AddressSanitizer build of Hermes and the tester, with folly's SanitizeLeak.cpp added, then one stock Fantom test.
    add_folly_sanitize_leak
    export "${asan_flags[@]}"
    build
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js
    ;;
  asan-jsi-duplicates-folly)
    # Hermes built first without the sanitizer, then the tester under AddressSanitizer with folly's SanitizeLeak.cpp
    # added, then one stock Fantom test.
    add_folly_sanitize_leak
    ./gradlew --quiet :private:react-native-fantom:prepareHermesDependencies
    export "${asan_flags[@]}"
    build
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js
    ;;
  tsan-mount-inside-locked-commit)
    # The ThreadSanitizer build of Hermes and the tester, the tester with a commit hook that lands a commit of the same
    # tree from a thread of its own inside each of the first attempts of a commit that mounts synchronously, then a test
    # that stops a surface under preventShadowTreeCommitExhaustion.
    git apply /reproducer/fantom/contending-commit-hook.patch
    cp /reproducer/fantom/LockedCommitMount-itest.js packages/react-native/Libraries/Components/View/__tests__/
    export "CFLAGS=-fsanitize=thread" "CXXFLAGS=-fsanitize=thread -Wno-error=deprecated-literal-operator" \
      "LDFLAGS=-fuse-ld=lld -fsanitize=thread"
    build
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/LockedCommitMount-itest.js
    ;;
  cxx-turbomodule-per-lookup)
    # A Fantom test that looks one TurboModule up twice.
    mkdir -p packages/react-native/Libraries/TurboModule/__tests__
    cp /reproducer/fantom/TurboModuleLookup-itest.js packages/react-native/Libraries/TurboModule/__tests__/
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    build
    yarn fantom packages/react-native/Libraries/TurboModule/__tests__/TurboModuleLookup-itest.js
    ;;
  *)
    echo "unknown case $case_name" >&2
    exit 2
    ;;
esac
