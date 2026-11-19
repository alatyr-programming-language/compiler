## Issue #1746 / Declarations §7.1, Functions §2.2, Types §4.3 — module-level declarations are
## order-independent, so a call's argument is judged against its callee's declaration even when that
## declaration is written after the caller. `pick` takes a `u64` and is handed a struct `S`; no
## implicit conversion turns an aggregate into a scalar. PARENT (main 637366a9), native x86_64: check
## 0 and every backend ran it to a value read off the struct's bits (`alatyr run` 206, the built
## artifact 222 on IR and legacy, aarch64 38, riscv64 86, wasm 38), where the same call to a `pick`
## written above `main` was refused.
S := struct { a : u64, b : u64 }
mk := fn() -> S { S(a = 3, b = 4) }
main := fn() -> u64 { pick(mk()) + 38 }
pick := fn(x : u64) -> u64 { x }
## expect: reject "type mismatch" "at line 10"
