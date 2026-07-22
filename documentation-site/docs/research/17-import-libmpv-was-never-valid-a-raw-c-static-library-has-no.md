---
id: 17-import-libmpv-was-never-valid-a-raw-c-static-library-has-no
title: "`import Libmpv` was never valid — a raw C static library has no Swift module"
sidebar_label: "17. import Libmpv was never valid — a raw C static library has no Swift module"
sidebar_position: 17
---

## 17. `import Libmpv` was never valid — a raw C static library has no Swift module

**What happened:** with entry 16's `xcodebuild` fix in place, CI got
further — `CMPV` compiled successfully (confirming entry 15's header
search paths worked) — but `MPVKit` itself then failed:
```
MPVCore.swift:3:19: error: no such module 'Libmpv'
@_exported import Libmpv
                  ^
```
Inspecting the full `swift-frontend` invocation in the log showed every
`-F` (framework search path) flag pointing at standard SDK/DerivedData
locations — **none of them referenced `Libmpv.xcframework` at all**, even
though `MPVKit`'s target explicitly listed `Libmpv` as a dependency in
`Package.swift`.

**Root cause:** `Libmpv` is a `.binaryTarget` wrapping a plain static
library (`libmpv-combined.a`) plus C headers — it was built by
`buildscripts/scripts/mpv-ios.sh` using `xcodebuild -create-xcframework
-library ... -headers ...`, the form intended for exposing a C/C++
static library, not a Swift framework. Multiple independent reports
(Swift Forums threads, an Apple Developer Forums thread, and a detailed
engineering writeup — all describing the identical "no such module"
symptom against completely unrelated XCFrameworks) confirm the same
underlying fact: a `.binaryTarget`/XCFramework only behaves as an
*importable Swift module* if it actually contains a compiled
`.swiftmodule` inside it. Ours never did and structurally couldn't — it
wraps mpv's C library, which has no Swift code or Swift module to begin
with. `@_exported import Libmpv` (and the plain `import Libmpv` in two
other files) was therefore never a valid statement — it was attempting
to import something that was never a Swift module and never could be one
built this way, and it likely only ever appeared to "work" during
earlier, more limited local testing that didn't exercise this exact
compilation path.

The fix in entry 15 (adding explicit header search paths to `CMPV`) was
real and necessary, but solved a different problem: it let the `CMPV` *C
target* find libmpv's C headers via `#include`. It never addressed (and
couldn't have addressed) `MPVKit`'s Swift files trying to `import Libmpv`
as if it were a Swift module.

**Actual fix:** removed `@_exported import Libmpv` from `MPVCore.swift`
and the plain `import Libmpv` from `MPVGLView.swift` and
`MPVProperty.swift`. This required no functional change beyond deleting
those lines — every mpv C symbol these files use (`mpv_create`,
`mpv_command`, `mpv_render_context_create`, `MPV_FORMAT_STRING`, etc.) is
already declared in `cmpv_shim.h` (which `#include`s `<mpv/client.h>`,
`<mpv/render.h>`, and `<mpv/render_gl.h>`), and is already exposed to
Swift via the existing `import CMPV` each of these files already had.
`Libmpv` remains listed in `MPVKit`'s target `dependencies` in
`Package.swift` — that part was and is correct, since the actual
`.a` binary still needs to be *linked* against, even though it's never
*imported* as a module.

**Lesson:** `@_exported import` (or any `import`) of a binaryTarget only
makes sense if that binary target is itself a Swift framework/module — a
binaryTarget wrapping a plain C static library should only ever be
consumed indirectly, through a C target (like `CMPV` here) that
`#include`s its headers and is itself imported from Swift. Writing
`import Libmpv` "because it's listed as a dependency" conflates two
different relationships SwiftPM's `dependencies:` array can express —
"this target needs to be able to import that module" is not the same
guarantee as "this target needs to link against that binary" — and only
one of those was ever true here.
