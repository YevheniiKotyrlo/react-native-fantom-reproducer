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

# Starts <count> testers at once on <bundle>, with the arguments yarn fantom gives a test without flags, <rounds> times,
# and prints each tester that exits non-zero, with how much it printed.
run_testers_at_once() {
  local bundle="$1" rounds="$2" count="$3" round slot status failures=0
  local output=/tmp/testers
  mkdir -p "$output"
  for ((round = 1; round <= rounds; round++)); do
    for ((slot = 1; slot <= count; slot++)); do
      (
        status=0
        private/react-native-fantom/build/tester/fantom_tester --bundlePath "$bundle" --featureFlags '{}' \
          --minLogLevel error > "$output/$slot.log" 2>&1 || status=$?
        echo "$status" > "$output/$slot.status"
      ) &
    done
    wait
    for ((slot = 1; slot <= count; slot++)); do
      status=$(cat "$output/$slot.status")
      if [[ $status != 0 ]]; then
        failures=$((failures + 1))
        echo "round $round, tester $slot: exit status $status, $(wc -c < "$output/$slot.log") bytes on stdout and stderr"
      fi
    done
  done
  echo "$((rounds * count)) testers, $failures exited non-zero"
}

# Prefixes each line read with the time it was read.
stamp_lines() {
  local line
  while IFS= read -r line; do
    echo "$(date +%T.%3N) $line"
  done
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
  concurrent-testers-null-runtime)
    # The stock Debug tester runs View-itest.js once through yarn fantom, which leaves the test's bundle in .out, then
    # 16 testers at a time on that bundle, as yarn fantom starts them; then the same with the inspector off.
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    build
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js
    bundle=$(ls private/react-native-fantom/.out/js-builds/run-*/*-View-itest.js.bundle.js | head -n 1)
    echo "bundle $bundle"
    echo "== the stock tester"
    run_testers_at_once "$bundle" 200 16
    git apply /reproducer/fantom/tester-inspector-off.patch
    build
    echo "== the tester with enableInspector = false"
    run_testers_at_once "$bundle" 200 16
    ;;
  jest-does-not-exit)
    # One stock Fantom test, each line of its output stamped with the time it was printed, then the same run with
    # Jest's --detectOpenHandles.
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    build
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js 2>&1 | stamp_lines
    echo "$(date +%T.%3N) yarn fantom exited"
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js --detectOpenHandles 2>&1 |
      stamp_lines
    echo "$(date +%T.%3N) yarn fantom --detectOpenHandles exited"
    ;;
  *)
    echo "unknown case $case_name" >&2
    exit 2
    ;;
esac
