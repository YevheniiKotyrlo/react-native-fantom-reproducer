# syntax=docker/dockerfile:1.7
# The image React Native's Fantom CI builds the tester in, with the latest LLVM release's Clang, LLD and sanitizer
# runtimes in place of the apt Clang the CI installs, and the OpenSSL headers the CI installs with apt:
# https://github.com/react/react-native/blob/main/.github/actions/build-fantom-runner/action.yml
FROM reactnativecommunity/react-native-android:v22.0@sha256:e817ea1959719c97c05adbc55348ebe21d286cec2caed1f18ad3c4b88c08cbf7 AS base
RUN apt-get update && apt-get install --yes --no-install-recommends libssl-dev xz-utils

FROM base AS llvm
ARG LLVM_VERSION=23.1.3
ADD --checksum=sha256:ca9fe385a5d9e2d88132dc0e23a00e9f87f38fa75f67207b5e457d208e71d013 \
    https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/LLVM-${LLVM_VERSION}-Linux-X64.tar.xz \
    /archives/llvm.tar.xz
RUN mkdir -p /opt/llvm && tar --extract --xz --file /archives/llvm.tar.xz --directory /opt/llvm --strip-components=1

FROM base
COPY --from=llvm /opt/llvm /opt/llvm
ENV PATH=/opt/llvm/bin:$PATH
ENV CC=clang CXX=clang++
# The image's GNU ld 2.38 cannot read the DWARF 5 that Clang 23 writes, so LLD links.
ENV LDFLAGS=-fuse-ld=lld
