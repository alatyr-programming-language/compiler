## e2e — a str-returning call passed DIRECTLY as an argument (the str dual of struct/enum-returning call
## args). `trim_end(trim_start(s))` composes two str-returning calls; `takes(trim(s))` passes a
## str-returning call straight into a str-consuming fn. Both previously crashed (the call fell to the
## scalar path → the data pointer became the by-ref pointer, len read from garbage) and needed a bind-to-
## a-local workaround. emit_arg now materializes the {ptr,len} into an agg-temp and passes it by-ref.
sm := base::str

takes := fn(t : str) -> bool { t == "hi" }

main := fn() -> u64 {
  r := sm::trim_end(sm::trim_start("  world  "))   ## nested str-ret-call arg
  if r.len != 5 { return 1 }                        ## "world"
  if not takes(sm::trim("   hi   ")) { return 2 }    ## str-ret-call straight into a consumer
  return 42
}
