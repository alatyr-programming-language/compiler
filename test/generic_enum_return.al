## ROADMAP §1/§4: a generic fn returning its type parameter applied to an ENUM (`id(Opt, o)`) — the
## enum dual of generic_struct_return. emit_enum_value's Var arm dereferences a by-ref enum param, and
## gen_ret_enum_span binds `o := id(Opt, …)` as the enum (disc/%rax + payload/%rdx delivery).
Opt := enum { None, Some(u64) }
id := fn(T : type, v : T) -> T { return v }
main := fn() -> u64 {
  o := id(Opt, Opt.Some(42))
  match o { Opt::None => { return 0 }; Opt::Some(x) => { return x } }
}
