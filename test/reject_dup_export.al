## MOD §6.6: two declarations emitting the SAME exact linker symbol are a compile error (a located
## duplicate-name diagnostic, earlier than the assembler's symbol clash). Both `a` and `b` carry
## `@export("dup_sym")` → rejected at the later one.
@export("dup_sym") a := fn() -> u64 { return 1 }

@export("dup_sym") b := fn() -> u64 { return 2 }

main := fn() -> u64 {
  return a() + b()
}
