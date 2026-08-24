## e2e (COMPTIME TYPE DISPATCH — a REMAINING `TypeInfo` kind, appendix §4.1). Extends the
## `comptime match typeinfo(T)` statement fold (driven by `comptime_type_kind` /
## `comptime_kind_of_name`) past Scalar/Struct/Enum/Array/Brand/Tuple to detect `Str` (`str`) — and,
## in the compiler, `Pointer` (`ptr(T)`) and `Function` (`fn(…) -> …`). Previously `str` collapsed to
## `Scalar`, so a `Str` arm could never fire. Here `kindof(str, …)` MUST select the `Str` arm (42); if
## `str` were still mis-read as `Scalar` it would take the `Scalar` arm (100) and the total would be
## 100, not 42. The `u64` call is a `Scalar` control (100), subtracted back out: 42 + 100 - 100 = 42.
## (Pointer/Function/Union are wired in `comptime_type_kind`/`comptime_kind_of_name` but NOT exercised
## here — a `ptr(…)`/`fn(…)->…` type-ARGUMENT's source span is not recovered by the mono machinery
## (only bare-ident, tuple, and array type-args are), and union types have no self-host surface, so no
## such instance-type spelling reaches the fold. See the report.)
kindof := fn(T : type, v : T) -> u64 {
  comptime match typeinfo(T) {
    Str => { return 42 }
    Pointer(_) => { return 10 }
    Scalar(b, k) => { return 100 }
    _ => { return 99 }
  }
}
main := fn() -> u64 {
  s := kindof(str, "hi")
  n := kindof(u64, 7)
  s + n - 100
}
