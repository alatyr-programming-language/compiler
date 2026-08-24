## FN-6 CAPTURE of an enclosing-PARAM aggregate — a lambda capturing a multi-word struct PARAM `s : Rec`
## of the ENCLOSING fn. The capture's type is not a body `:=` binding, so `d_local_type_span` (which only
## scans body Assigns) could not type it → the capture got an untyped WORD slot holding the struct's
## address. Copying the capture to a local and reading BOTH fields (`t := s; t.a + t.b`) then read 0 —
## the address was treated as the struct value — a Priority-1 SILENT MISCOMPILE. The driver now resolves
## the type from the enclosing param list (`d_param_type_span`) and gives the capture a TYPED by-ref
## param (as a literal-bound local already gets), so every captured field survives. a=12,b=30 → 42.
Rec := struct { a : u64, b : u64 }
outer := fn(s : Rec) -> u64 {
  f := fn(n : u64) -> u64 { t := s
    return n + t.a + t.b }
  return f(0)
}
main := fn() -> u64 {
  return outer(Rec(a = 12, b = 30))
}
