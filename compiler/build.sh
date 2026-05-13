#!/usr/bin/env bash
set -euo pipefail

CRATE=compiler
TARGET=aarch64-apple-darwin
LIB=target/${TARGET}/release/lib${CRATE}.a
XCF=Compiler.xcframework

cargo build --release --target "$TARGET"
cbindgen --config cbindgen.toml --crate "$CRATE" --output include/compiler.h

rm -rf "$XCF"
xcodebuild -create-xcframework \
    -library "$LIB" \
    -headers include/ \
    -output "$XCF"
