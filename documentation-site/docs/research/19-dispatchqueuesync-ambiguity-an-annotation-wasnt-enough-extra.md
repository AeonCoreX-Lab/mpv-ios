---
id: 19-dispatchqueuesync-ambiguity-an-annotation-wasnt-enough-extra
title: "`DispatchQueue.sync` ambiguity: an annotation wasn't enough, extraction was"
sidebar_label: "19. DispatchQueue.sync ambiguity: an annotation wasn't enough, extraction was"
sidebar_position: 19
---

## 19. `DispatchQueue.sync` ambiguity: an annotation wasn't enough, extraction was

**What happened, round 1:** with entries 15–18 resolved, `MPVKit`
progressed further into real type-checking and hit:
```
MPVGLView.swift:97:21: error: ambiguous use of 'sync(execute:)'
        renderQueue.sync {
                    ^
Dispatch.DispatchQueue:74:17: note: found this candidate in module 'Dispatch'
    public func sync<T>(execute work: () throws -> T) rethrows -> T
Dispatch.DispatchQueue:3:17: note: found this candidate in module 'Dispatch'
    public func sync(execute block: () -> Void)
```

**Initial (incomplete) diagnosis:** `DispatchQueue` declares two
overloads of `sync` — a generic, `rethrows` version, and a plain
`() -> Void` version. The closure passed to `renderQueue.sync { ... }` in
`attachRenderContext()` contained **nested calls to
`withUnsafeMutablePointer(to:_:)`**, itself generic and `rethrows`. The
first fix attempt added an explicit closure signature —
`renderQueue.sync { () -> Void in ... }` — reasoning that telling the
compiler the outer closure's type explicitly would resolve which `sync`
overload was intended.

**Round 2 — the same error, in the same place, after that fix shipped:**
a later CI run showed the identical "ambiguous use of 'sync(execute:)'"
error, at the same line, **with the `() -> Void in` annotation visibly
already present** in the failing line the compiler quoted. This
conclusively demonstrated that the annotation alone was not sufficient —
the ambiguity wasn't coming from Swift being unable to infer the outer
closure's own signature, but from the *nested* generic/rethrows calls
inside it confusing overload resolution in a way an outer annotation
doesn't reach.

**Actual fix:** extracted the entire nested
`withUnsafeMutablePointer(to:_:)` pyramid out of the `sync` closure
entirely, into a new private, non-generic method
(`createRenderContext(core:) -> MPVError?`). The `sync` closure in
`attachRenderContext()` now contains only a single, flat statement —
`creationError = self.createRenderContext(core: core)` — with no nested
generic calls anywhere in its body. This is what actually resolved the
ambiguity: removing the nested generics from the closure passed to
`sync`, not describing that closure's own type more precisely.

**Lesson:** when an "ambiguous use of X" error persists after adding an
explicit type annotation at the call site the error points to, the
annotation may be treating a symptom rather than the cause — worth
checking whether *nested* generic/`rethrows` calls deeper inside that
same closure body are what's actually defeating overload resolution.
Extracting the nested generic structure into its own ordinary
(non-generic-call-containing) function is a more reliable fix than
trying to out-annotate the ambiguity from the outside, and is worth
trying first once an annotation demonstrably didn't work — as confirmed
here by the same error reappearing, unchanged, in the very next CI run
after the annotation was believed to have fixed it.
