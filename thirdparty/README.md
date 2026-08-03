# Third-Party Dependencies

Place vendored or locally staged native dependencies here.

## CI and cross-platform layout

GitHub Actions builds/stages SQLite3, xxHash, and USearch into:

```text
thirdparty/native/include/sqlite3.h
thirdparty/native/include/xxhash.h
thirdparty/native/include/usearch.h
thirdparty/native/lib/
thirdparty/native/bin/              # Windows runtime DLLs
```

`thirdparty/native/` is generated and ignored by Git. USearch is pinned to
`v2.26.0` in the CI workflow and compiled with its C99 interface enabled.

On macOS and Linux, SQLite3 and xxHash are resolved through `pkg-config` when
available. On Windows, their vcpkg import libraries and headers are staged into
the layout above.

## Legacy macOS bundle

The current USearch layout is:

```text
thirdparty/usearch/macos_arm64/include/usearch.h
thirdparty/usearch/macos_arm64/lib/libusearch_c.dylib
```

The older vendored arm64 bundle remains for reference. The active optional V
backend is guarded by `-d usearch` and uses `thirdparty/native/`. If you copy the
legacy dylib into that layout and it has quarantine metadata, remove it before
running tests:

```sh
xattr -d com.apple.quarantine thirdparty/native/lib/libusearch_c.dylib
```
