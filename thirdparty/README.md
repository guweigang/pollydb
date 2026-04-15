# Third-Party Dependencies

Place vendored native dependencies here.

The current USearch layout is:

```text
thirdparty/usearch/macos_arm64/include/usearch.h
thirdparty/usearch/macos_arm64/lib/libusearch_c.dylib
```

The optional V backend is guarded by `-d usearch`. On macOS, if the downloaded
dylib has quarantine metadata, remove it before running tests:

```sh
xattr -d com.apple.quarantine thirdparty/usearch/macos_arm64/lib/libusearch_c.dylib
```
