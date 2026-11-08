## Issue #364 — the IR path: a checked `char(n)` built by the shared IR builder reaches `to_char`'s
## code-point guard too.
##
## Types §4.6 (v1.8.0, l.341): "So `char(n)` — `char` being a brand over `u32` with the prelude's
## `@convert` in scope — runs that conversion, whose code-point validity check is library code under
## `comptime if verify.checked`". Sema reads `char` as the kernel `u32`, so the IR builder took `char(n)`
## for a scalar-name conversion and built a narrow to `u32`: the guard never ran when `alatyr x86-ir`
## selected `main`. This `main` is small enough for the builder to take, which `issue364_char_convert_guard`
## is not, so the row is the IR path's.
##
## 1114112 is one above 0x10FFFF, so the guard fires and the `42` is never reached. It fails through
## `panic` (exit 1), not the specified `trap()` (#1427), so the row is x86_64-scoped as the guard row is.
ch := base::char

main := fn() -> u64 {
  n : u32 = 1114112
  c := char(n)
  if u32(c) == 1114112 { return 42 }
  7
}
## expect(x86_64): run 1
