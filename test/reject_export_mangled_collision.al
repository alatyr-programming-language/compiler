## MOD §6.7: an explicit `@export` symbol must not collide with a path-derived symbol emitted for
## another declaration. In a single-file build this file's stem is the module prefix, so `helper`
## naturally emits `reject_export_mangled_collision__helper`; exporting that same exact linker name
## would otherwise reach GAS as a duplicate label.
@export("reject_export_mangled_collision__helper") exported := fn() -> u64 {
  return 1
}

helper := fn() -> u64 {
  return 2
}

main := fn() -> u64 {
  return exported() + helper()
}
