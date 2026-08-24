## OVER-REJECT GUARD, cross-backend half. `trunc_guard_signature_forms` covers the same requirements
## more widely but is x86_64-only; this file is deliberately restricted to constructs that run on all
## four backends, because a fixture that agrees across two independent backends is worth more than any
## single-backend green.
##
## What it guards — each is legitimate code that one of the new parser requirements could have rejected:
##   * a multi-token PARAMETERIZED return type. The scan that walks from a function's signature to its
##     body now STOPS at the `:=` that begins the next declaration (that scan running past it is how a
##     mid-file truncation swallowed `main` and took its brace as its own body), so a return type
##     spanning several tokens must still find its brace;
##   * a `::` path in a bare alias declaration — the declaration-level path lookahead now requires a
##     segment name after each `::`;
##   * an expression `if`, including a nested one in the else position — its branch brace is now
##     required rather than skipped;
##   * a `match` expression over an enum — its arm-list brace is now required rather than skipped;
##   * member access whose name is present, including a chained one.
##
## THREE constructs that belong to this list are NOT here, because they trap on the non-x86 backends
## ALREADY: a tuple return type `-> (u64, u64)`, a local lambda bound to a name and called, and a
## `match` over integer literals with a `_` arm — each measured at 133 under qemu-aarch64 and
## qemu-riscv64, with BYTE-IDENTICAL emission from the compiler at 495e842, so they are pre-existing
## backend gaps rather than anything the truncation rejects caused. All three are covered on x86_64 by
## `trunc_guard_signature_forms`.
##
## Measured identical on the pre-fix compiler at 495e842 and on the post-fix one: exit 42 on x86_64,
## aarch64, riscv64 and wasm.
vec := alloc::vec

Pair := struct { a : u64, b : u64 }
Outer := struct { p : Pair }

res := fn(x : u64) -> Result(u64, u64) {
  Result(u64, u64).Ok(x)
}

main := fn() -> u64 {
  o := Outer(p = Pair(a = 18, b = 19))
  q := res(2)
  mut acc := 0
  acc = acc + o.p.a + o.p.b                    ## chained struct fields: 18 + 19
  acc = acc + match q {                        ## a parameterized return type, matched
    Result::Ok(v) => { v }
    Result::Err(e) => { 0 }
  }                                            ## 2
  acc = acc + if acc > 0 { 1 } else { if acc == 0 { 5 } else { 9 } }
  acc + 2
}
