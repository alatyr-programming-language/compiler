## Modules §3/§2 + Memory §2.2 — a `pub` module-level global reached from a module that is NOT a
## descendant, through the qualified path `geo::NAME`. §3 opens a `pub` declaration upward, and `::`
## navigates to it; the bare spelling would not resolve there (no glob import, §4.5), which is what
## `module_global_bare_nonancestor_reject` locks. Every reference must be addressed through the MOD-6
## mangled `.data` symbol `geo__<NAME>(%rip)`.
##
## Covers, all qualified: a scalar write, a compound assignment, an ARRAY-ELEMENT write, a scalar
## read, a `str` (§7 view) read, a folded const scalar and a const ARRAY element. 7+12+3+5+15 = 42.
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      kind = Kind.executable,
      output = "module-global-qualified",
    ),
  ],
)
