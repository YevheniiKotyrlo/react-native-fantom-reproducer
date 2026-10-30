# React Native's Fantom tester, built on Linux

This repository was made from React Native's reproducer template. The reproductions are in `fantom/`; the template's `ReproducerApp` is unchanged and none of them use it.

Each reproduction builds Fantom's tester (`private/react-native-fantom`) from a fresh clone of `react/react-native`, as React Native's Fantom CI job builds it: in the `reactnativecommunity/react-native-android` image, with `yarn workspace @react-native/fantom build`, but with Clang and LLD from the LLVM 23.1.3 release in place of the apt Clang the CI installs.

```sh
./fantom/reproduce.sh <case> [<react-native branch or tag, main by default>]
```

It needs Docker and nothing else. The image is defined by `fantom/Dockerfile`, the steps of each case are in `fantom/run-case.sh`, and a named volume, `react-native-fantom-reproducer-cache`, keeps Gradle's and Yarn's downloads between runs.

| Case | What it runs | What it shows |
| --- | --- | --- |
| `build` | Fantom's CI build | on `main`, `nlohmann/json.hpp` 3.11.2 fails `-Wdeprecated-literal-operator` under `-Werror`; on `0.88-stable`, Hermes's source build finds no `CMakeLists.txt` in the unpacked tarball |
| `asan-folly-sanitize-leak` | the build under AddressSanitizer | the tester's link misses `folly::detail::annotate_object_collected_impl` and `annotate_object_leaked_impl`, since Fantom's folly omits `SanitizeLeak.cpp` |
| `asan-jsi-twice` | Hermes and the tester under AddressSanitizer, `SanitizeLeak.cpp` added, then `View-itest.js` | an odr-violation: `libhermesvm.so` and the tester's `libjsi.so` each define jsi's globals |
| `asan-jsi-duplicates-folly` | Hermes built plain, the tester under AddressSanitizer, `SanitizeLeak.cpp` added, then `View-itest.js` | an odr-violation: `libjsi.so` carries its own copy of folly and double-conversion beside the tester's |
| `cxx-turbomodule-per-lookup` | `fantom/TurboModuleLookup-itest.js` | two lookups of one TurboModule name answer two different modules on the `cxx` platform |
| `tsan-mount-inside-locked-commit` | Hermes and the tester under ThreadSanitizer, the tester with `fantom/contending-commit-hook.patch`, which lands a commit of the same tree inside each of the first attempts of a commit that mounts synchronously, then `fantom/LockedCommitMount-itest.js`, which stops a surface under `preventShadowTreeCommitExhaustion` | a lock-order inversion between `ShadowTreeRegistry`'s lock and the shadow tree's revision lock: the empty-tree commit's locked attempt mounts, and the tester reports the mount, taking the registry's lock, inside it |
| `concurrent-testers-null-runtime` | the stock Debug tester, `View-itest.js` once through `yarn fantom` to bundle it, then 200 rounds of 16 testers at once on that bundle, with the arguments `yarn fantom` gives them; then the same with `fantom/tester-inspector-off.patch` | testers that die of SIGSEGV with nothing on stdout or stderr: the inspector a Debug build starts by default has not posted the runtime's first task when `loadScript` drains the queue; none with the inspector off |
| `jest-does-not-exit` | `View-itest.js` through `yarn fantom`, each line stamped with the time it was printed, then again with `--detectOpenHandles` | Jest prints "Jest did not exit one second after the test run has completed" and the process ends about 5 seconds after the last test; `--detectOpenHandles` names no handle |

The AddressSanitizer and ThreadSanitizer cases pass `-Wno-error=deprecated-literal-operator`, so the `build` case's failure does not stop them.
