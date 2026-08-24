## e2e — IMPLICIT type-argument inference for a generic call. `id(T : type, v : T)` is called as
## `id(k)` with the leading type-arg OMITTED; the lower infers `T` from the value argument's type
## (`k : u64` → `id__u64`) at BOTH the mono pre-pass (instantiates `id__u64`) and the emit call label,
## rather than mis-reading the value `k` as the type-arg (which produced a bogus `id__k` with the value
## erased). `useit` passes its param, `main` gets 42 back.
id := fn(T : type, v : T) -> T { return v }
useit := fn(k : u64) -> u64 { return id(k) }
main := fn() -> u64 { return useit(42) }
