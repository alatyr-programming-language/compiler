## ROADMAP §4: a value-match over an ENUM scrutinee yielding a STRUCT into a local
## (`p := match o { Some(v) => P(v, …) }`). emit_val_match_to_local dispatched with `am.lit` (0 for
## enum patterns) so it never matched and the aggregate stayed unwritten; now it detects an enum
## scrutinee, dispatches on the discriminant with variant indices, binds the arm's payload, and
## stores each arm's struct via emit_arm_val_store. Some(40) → P(x = 40, y = 2) → 42.
P := struct { x : u64, y : u64 }
Opt := enum { None, Some(u64) }
main := fn() -> u64 {
  o := Opt.Some(40)
  p := match o { Opt::None => { P(x = 0, y = 0) }; Opt::Some(v) => { P(x = v, y = 2) } }
  return p.x + p.y
}
