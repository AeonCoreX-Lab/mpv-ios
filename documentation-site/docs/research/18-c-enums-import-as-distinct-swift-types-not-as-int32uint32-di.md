---
id: 18-c-enums-import-as-distinct-swift-types-not-as-int32uint32-di
title: "C enums import as distinct Swift types, not as `Int32`/`UInt32` directly"
sidebar_label: "18. C enums import as distinct Swift types, not as Int32/UInt32 directly"
sidebar_position: 18
---

## 18. C enums import as distinct Swift types, not as `Int32`/`UInt32` directly

**What happened:** with entries 15–17 resolved, `MPVKit` finally reached
real type-checking, and failed with a cluster of errors like:
```
MPVProperty.swift:60:44: error: cannot convert value of type 'mpv_error' to specified type 'Int32'
MPVCore.swift:235:55: error: cannot convert value of type 'UInt32' to expected argument type 'Int32'
```

**Root cause:** libmpv's C headers declare several plain enums —
`mpv_error`, `mpv_format`, `mpv_event_id`, `mpv_end_file_reason` — as
`typedef enum mpv_error { ... } mpv_error;`, no fixed underlying type
annotation. When Swift's Clang Importer bridges a plain C enum like this,
it creates a **distinct Swift type** (e.g. `mpv_error`, itself
`RawRepresentable` with some integer `.rawValue`), not a transparent
alias for `Int32`/`UInt32`. This project's code had, in several places,
mixed two things that only *look* interchangeable:
- The real return type of libmpv's C functions themselves (`mpv_command`,
  `mpv_set_property`, etc. are declared to literally return `int`, which
  bridges cleanly to Swift's `Int32`).
- Named error/format/event constants (`MPV_ERROR_UNINITIALIZED`,
  `event.event_id`, `endFile.reason`), which are typed as their *enum*
  (`mpv_error`, `mpv_event_id`, `mpv_end_file_reason` respectively), not
  as bare integers.

A function declared to return plain `Int32` (matching the real C
function signature) can't also directly `return
MPV_ERROR_UNINITIALIZED` (an `mpv_error` value) without an explicit
`.rawValue` — and the reverse direction (passing our own `Int32`-backed
`MPVFormat` enum's `.rawValue` into something expecting the real
`mpv_format` C enum) hit the identical mismatch from the other side.

**Fix, in three parts:**
1. Every `return MPV_ERROR_UNINITIALIZED` (nine occurrences across
   `MPVCore.swift` and `MPVProperty.swift`) became `return
   MPV_ERROR_UNINITIALIZED.rawValue`, matching the `Int32` these
   functions actually return (mirroring the real C functions' `int`
   return type).
2. `event.event_id.rawValue`, `endFile.reason.rawValue`, and
   `prop.format.rawValue` (all `UInt32` as bridged) were wrapped in
   explicit `Int32(...)` where the surrounding Swift code (this
   project's own `MPVEvent`/`MPVFormat` types) expects `Int32`.
3. The reverse direction — constructing a real `mpv_format` C enum value
   from our own `MPVFormat` Swift enum, needed by
   `mpv_observe_property` — was **not** fixed with a raw
   `mpv_format(rawValue: UInt32(format.rawValue))` conversion, because a
   plain C enum's Swift-generated `init(rawValue:)` is failable (Swift
   can't know every raw integer maps to a defined case), which would
   have required an unsafe force-unwrap or an unreachable-but-mandatory
   fallback. Instead, `MPVFormat` gained an explicit `var mpvFormat:
   mpv_format` computed property, mapping each of its five cases to the
   corresponding real `MPV_FORMAT_*` constant by name — compile-time
   exhaustive, no optional involved at all.

**Lesson:** when a C header exposes a plain (non-fixed-underlying-type)
enum, assume it will import into Swift as its own named type, not as a
convenient alias for whatever integer type "feels right." Every point
where a value crosses between "the real C function's declared int return
type" and "one of that C API's own named enum constants" is a place this
kind of mismatch can hide — and it can hide differently in each
direction (missing `.rawValue` one way, a needlessly-failable
`init(rawValue:)` the other way), so each conversion site is worth
checking on its own rather than assuming one fix pattern covers every
occurrence.
