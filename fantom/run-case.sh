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

# Prints the summary line and exits with the verdict: 1 while the defect shows, 0 once it is gone, 2 for anything else.
verdict() {
  echo "SUMMARY: $2"
  exit "$1"
}

# Clang 23 declares no __builtin_ia32_vcvtph2ps256, which the AVX2 path of the skcms in the tester's pinned Skia calls.
skip_skcms_runtime_cpu_detection() {
  local skia=private/react-native-fantom/tester/third-party/skia/CMakeLists.txt
  [ -f "$skia" ] || return 0
  sed -i 's#\\"-ffp-contract=off\\"#&,\\"-DSKCMS_NO_RUNTIME_CPU_DETECTION\\"#' "$skia"
  grep -q SKCMS_NO_RUNTIME_CPU_DETECTION "$skia" || verdict 2 "the Skia build arguments changed, so skcms keeps its AVX2 path"
}

# Gradle writes the tester's compiler output to its reports, so a failed build prints the errors there.
build() {
  skip_skcms_runtime_cpu_detection
  if ! yarn workspace @react-native/fantom build; then
    grep --no-filename --extended-regexp 'error:|undefined (symbol|reference)' private/react-native-fantom/build/reports/*.log | head -n 40
    return 1
  fi
}

# Runs one Fantom test, printing its output into fantom_output and its exit status into fantom_status.
run_fantom() {
  fantom_status=0
  fantom_output=$(yarn fantom "$1" 2>&1) || fantom_status=$?
  echo "$fantom_output"
  echo "yarn fantom exited with status $fantom_status"
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
    build || exit 1
    ;;
  hermes-source-tarball)
    # Hermes's source tarball downloaded, unpacked and configured as Fantom's build does before it builds Hermes from
    # source; enableHermesBuild is the task through which Fantom's build turns the Hermes tasks on.
    trap 'verdict 2 "a step failed: $BASH_COMMAND"' ERR
    hermes_task=:packages:react-native:ReactAndroid:hermes-engine:configureBuildForHermesWithDebugger
    hermes_status=0
    hermes_output=$(./gradlew --console=plain :private:react-native-fantom:enableHermesBuild "$hermes_task" 2>&1) ||
      hermes_status=$?
    grep -E '^> Task :packages:react-native:ReactAndroid:hermes-engine:|CMake Error|^BUILD (SUCCESSFUL|FAILED)' <<<"$hermes_output" || true
    hermes_dir=packages/react-native/sdks/hermes
    echo "== the CMakeLists.txt files in $hermes_dir, two levels deep"
    find "$hermes_dir" -maxdepth 2 -name CMakeLists.txt
    [ "$hermes_status" -eq 0 ] && verdict 0 "configureBuildForHermesWithDebugger finds Hermes's CMakeLists.txt in $hermes_dir"
    if grep -q 'does not appear to contain CMakeLists.txt' <<<"$hermes_output"; then
      nested=$(find "$hermes_dir" -mindepth 2 -maxdepth 2 -name CMakeLists.txt)
      verdict 1 "configureBuildForHermesWithDebugger finds no CMakeLists.txt in $hermes_dir: the tarball's top folder was not stripped, so the sources are in ${nested%/CMakeLists.txt}"
    fi
    tail -n 30 <<<"$hermes_output"
    verdict 2 "configureBuildForHermesWithDebugger failed another way"
    ;;
  asan-folly-sanitize-leak)
    # The same build under AddressSanitizer, with nlohmann_json's warning kept from being an error.
    export "${asan_flags[@]}"
    build || exit 1
    ;;
  asan-jsi-twice)
    # The AddressSanitizer build of Hermes and the tester, with folly's SanitizeLeak.cpp added, then one stock Fantom test.
    add_folly_sanitize_leak
    export "${asan_flags[@]}"
    build || verdict 2 "the tester did not build"
    run_fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js
    [ "$fantom_status" -eq 0 ] && verdict 0 "View-itest.js passes under AddressSanitizer: one copy of jsi"
    if grep -q 'AddressSanitizer: odr-violation' <<<"$fantom_output" && grep -q 'jsi\.cpp in .*/libhermesvm\.so' <<<"$fantom_output" &&
      grep -q 'jsi\.cpp in .*/ReactCommon/jsi/libjsi\.so' <<<"$fantom_output"; then
      verdict 1 "odr-violation: libhermesvm.so and the tester's libjsi.so each define jsi's globals"
    fi
    verdict 2 "View-itest.js failed another way"
    ;;
  asan-jsi-duplicates-folly)
    # Hermes built first without the sanitizer, then the tester under AddressSanitizer with folly's SanitizeLeak.cpp
    # added, then one stock Fantom test.
    add_folly_sanitize_leak
    ./gradlew --quiet :private:react-native-fantom:prepareHermesDependencies || verdict 2 "Hermes did not build"
    export "${asan_flags[@]}"
    build || verdict 2 "the tester did not build"
    run_fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js
    [ "$fantom_status" -eq 0 ] && verdict 0 "View-itest.js passes under AddressSanitizer: one copy of folly and double-conversion"
    if grep -q 'AddressSanitizer: odr-violation' <<<"$fantom_output" &&
      grep -Eq "'(double_conversion|folly)::.* in .*/fantom_tester$" <<<"$fantom_output" &&
      grep -Eq "'(double_conversion|folly)::.* in .*/ReactCommon/jsi/libjsi\.so$" <<<"$fantom_output"; then
      verdict 1 "odr-violation: fantom_tester and libjsi.so each define folly's or double-conversion's globals"
    fi
    verdict 2 "View-itest.js failed another way"
    ;;
  tsan-mount-inside-locked-commit)
    # The ThreadSanitizer build of Hermes and the tester, the tester with a commit hook that lands a commit of the same
    # tree from a thread of its own inside each of the first attempts of a commit that mounts synchronously, then a test
    # that stops a surface under preventShadowTreeCommitExhaustion.
    git apply /reproducer/fantom/contending-commit-hook.patch
    cp /reproducer/fantom/LockedCommitMount-itest.js packages/react-native/Libraries/Components/View/__tests__/
    export "CFLAGS=-fsanitize=thread" "CXXFLAGS=-fsanitize=thread -Wno-error=deprecated-literal-operator" \
      "LDFLAGS=-fuse-ld=lld -fsanitize=thread"
    build || verdict 2 "the tester did not build"
    run_fantom packages/react-native/Libraries/Components/View/__tests__/LockedCommitMount-itest.js
    if grep -q 'ThreadSanitizer: lock-order-inversion' <<<"$fantom_output" && grep -q 'UIManager::reportMount' <<<"$fantom_output"; then
      verdict 1 "lock-order-inversion: the tester reports the mount, taking ShadowTreeRegistry's lock, inside the locked commit"
    fi
    [ "$fantom_status" -eq 0 ] && ! grep -q 'WARNING: ThreadSanitizer' <<<"$fantom_output" &&
      verdict 0 "LockedCommitMount-itest.js passes with no ThreadSanitizer report"
    verdict 2 "LockedCommitMount-itest.js failed another way"
    ;;
  skia-clang-23)
    # Fantom's CI build with Clang 23 and the Skia revision the tester pins, nlohmann_json's warning kept from being an
    # error (#59667); no SKCMS_NO_RUNTIME_CPU_DETECTION here.
    skia=private/react-native-fantom/tester/third-party/skia/CMakeLists.txt
    [ -f "$skia" ] || verdict 2 "this React Native builds no Skia into the tester"
    skia_version=$(grep --only-matching --perl-regexp '(?<=val skiaVersion = ")[0-9a-f]+' private/react-native-fantom/build.gradle.kts || true)
    echo "Skia $skia_version"
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    yarn workspace @react-native/fantom build && verdict 0 "the tester builds with Clang 23, its Skia included"
    errors=$(grep --no-filename 'error:' private/react-native-fantom/build/reports/*.log || true)
    head -n 20 <<<"$errors"
    if grep -q "skcms/src/Transform_inl.h:[0-9]*:[0-9]*: error: use of undeclared identifier '__builtin_ia32_vcvtph2ps256'" <<<"$errors"; then
      verdict 1 "the skcms of the tester's Skia calls __builtin_ia32_vcvtph2ps256, which Clang 23 does not declare"
    fi
    verdict 2 "the tester failed to build another way"
    ;;
  cxx-turbomodule-per-lookup)
    # A Fantom test that looks one TurboModule up twice.
    mkdir -p packages/react-native/Libraries/TurboModule/__tests__
    cp /reproducer/fantom/TurboModuleLookup-itest.js packages/react-native/Libraries/TurboModule/__tests__/
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    build || verdict 2 "the tester did not build"
    run_fantom packages/react-native/Libraries/TurboModule/__tests__/TurboModuleLookup-itest.js
    [ "$fantom_status" -eq 0 ] && verdict 0 "both lookups of SourceCode answer the one module"
    if grep -q 'answers the same module for every lookup of one name' <<<"$fantom_output" &&
      grep -q 'Expected true but received false' <<<"$fantom_output"; then
      verdict 1 "two lookups of SourceCode answer two different modules on the cxx platform"
    fi
    verdict 2 "TurboModuleLookup-itest.js failed another way"
    ;;
  concurrent-testers-null-runtime)
    # The stock Debug tester runs View-itest.js once through yarn fantom, which leaves the test's bundle in .out, then
    # 16 testers at a time on that bundle, as yarn fantom starts them; then the same with the inspector off.
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    build || exit 1
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js
    bundle=$(ls private/react-native-fantom/.out/js-builds/run-*/*-View-itest.js.bundle.js | head -n 1)
    echo "bundle $bundle"
    echo "== the stock tester"
    run_testers_at_once "$bundle" 200 16
    git apply /reproducer/fantom/tester-inspector-off.patch
    build || exit 1
    echo "== the tester with enableInspector = false"
    run_testers_at_once "$bundle" 200 16
    ;;
  jest-does-not-exit)
    # One stock Fantom test, each line of its output stamped with the time it was printed, then the same run with
    # Jest's --detectOpenHandles.
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    build || exit 1
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js 2>&1 | stamp_lines
    echo "$(date +%T.%3N) yarn fantom exited"
    yarn fantom packages/react-native/Libraries/Components/View/__tests__/View-itest.js --detectOpenHandles 2>&1 |
      stamp_lines
    echo "$(date +%T.%3N) yarn fantom --detectOpenHandles exited"
    ;;
  crash-prints-no-stack)
    # A Fantom test whose native call writes through a null pointer in faultOnNullWrite, run on the stock tester, then
    # with InstallFailureSignalHandler in main, then with HAVE_SIGACTION defined in glog's config.h, then with OS_LINUX
    # kept there as well. The verdict reads the stock tester's report.
    trap 'verdict 2 "a step failed: $BASH_COMMAND"' ERR
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    git apply /reproducer/fantom/null-write-in-clear-all-images.patch
    cp /reproducer/fantom/NativeCrash-itest.js private/react-native-fantom/src/__tests__/
    crash_test=private/react-native-fantom/src/__tests__/NativeCrash-itest.js
    # buildFantomTester's only input is the tester's CMake build tree, so Gradle calls it up to date after a change to
    # glog's config.h; --rerun has CMake decide what to rebuild.
    stage() {
      build || verdict 2 "the tester did not build"
      ./gradlew --quiet :private:react-native-fantom:buildFantomTester --rerun
      echo "== $1"
      run_fantom "$crash_test"
    }
    stage "the stock tester"
    stock_output=$fantom_output
    git apply /reproducer/fantom/install-failure-signal-handler.patch
    stage "InstallFailureSignalHandler in main"
    git apply /reproducer/fantom/glog-config-sigaction.patch
    stage "and HAVE_SIGACTION in glog's config.h"
    git apply /reproducer/fantom/glog-config-keep-os-linux.patch
    stage "and OS_LINUX kept in glog's config.h"
    patched_names_frame=no
    grep -q 'faultOnNullWrite()' <<<"$fantom_output" && patched_names_frame=yes
    grep -q 'faultOnNullWrite()' <<<"$stock_output" && verdict 0 "the stock tester's crash report names faultOnNullWrite()"
    if grep -q 'signal: SIGSEGV' <<<"$stock_output" && ! grep -qF '*** SIGSEGV' <<<"$stock_output"; then
      verdict 1 "the stock tester dies of SIGSEGV and prints no stack; with the three patches, the report names faultOnNullWrite(): $patched_names_frame"
    fi
    verdict 2 "the stock tester's run ended another way"
    ;;
  stale-tester-after-react-common-change)
    # View-itest.js on the stock tester; then a write through a null pointer added to ReactInstance::loadScript in
    # ReactCommon, the tester built again as CI builds it, and View-itest.js again; then buildFantomTester rerun and
    # View-itest.js once more.
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    view_test=packages/react-native/Libraries/Components/View/__tests__/View-itest.js
    build || exit 1
    echo "== the stock tester"
    sha256sum private/react-native-fantom/build/tester/fantom_tester
    yarn fantom "$view_test" 2>&1 | grep --extended-regexp '^(PASS|FAIL)|Command failed|^Tests:' || true
    git apply /reproducer/fantom/null-write-in-load-script.patch
    echo "== ReactInstance::loadScript writes through a null pointer; yarn workspace @react-native/fantom build"
    yarn workspace @react-native/fantom build 2>&1 | grep --extended-regexp 'FantomTester|BUILD' || true
    sha256sum private/react-native-fantom/build/tester/fantom_tester
    yarn fantom "$view_test" 2>&1 | grep --extended-regexp '^(PASS|FAIL)|Command failed|^Tests:' || true
    echo "== ./gradlew :private:react-native-fantom:buildFantomTester --rerun"
    ./gradlew :private:react-native-fantom:buildFantomTester --rerun 2>&1 | grep --extended-regexp 'FantomTester|BUILD' || true
    sha256sum private/react-native-fantom/build/tester/fantom_tester
    yarn fantom "$view_test" 2>&1 | grep --extended-regexp '^(PASS|FAIL)|Command failed|^Tests:' || true
    ;;
  raw-props-out-of-order-read)
    # fantom/RawPropsOrder.cpp, built in the tester's CMake tree against the tester's libraries, with
    # raw-props-parser-compared-keys.patch counting what RawPropsParser::at does: it parses one set of raw props through
    # View's props alone, through a props struct that reads a key of its own after them and through one that reads
    # width again after them.
    export CXXFLAGS=-Wno-error=deprecated-literal-operator
    git apply /reproducer/fantom/raw-props-parser-compared-keys.patch
    cat >> private/react-native-fantom/tester/CMakeLists.txt <<'CMAKE'

add_executable(raw_props_order /reproducer/fantom/RawPropsOrder.cpp)
get_target_property(fantom_tester_libraries fantom_tester LINK_LIBRARIES)
target_link_libraries(raw_props_order PRIVATE ${fantom_tester_libraries})
CMAKE
    build || exit 1
    tree=$(dirname "$(grep -l '^CMAKE_PROJECT_NAME:STATIC=fantom_tester$' $(find private/react-native-fantom/build -name CMakeCache.txt))")
    if ! cmake --build "$tree" --target raw_props_order > /tmp/raw_props_order-build.log 2>&1; then
      grep --extended-regexp 'error:|undefined' /tmp/raw_props_order-build.log | head -n 40
      tail -n 20 /tmp/raw_props_order-build.log
      exit 1
    fi
    "$tree/raw_props_order"
    ;;
  *)
    echo "unknown case $case_name" >&2
    exit 2
    ;;
esac
