## MOD §6.6 regression: value-position @export attributes still participate in
## duplicate linker-symbol diagnostics.
a := @export("dup_value_sym") fn() -> u64 { return 1 }

b := @export("dup_value_sym") fn() -> u64 { return 2 }

main := fn() -> u64 {
  return a() + b()
}
