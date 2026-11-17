## e2e — #1711: a Some-FIRST `Option` over a NON-pointer (`Option(u64)`) is NOT niche-folded (Types
## §6.2: `u64` provides no niche) and keeps the ordinary tag + payload layout, `Some` at discriminant
## 0. Accepting the folded shape in either variant order must not reach it: a parameter, a result, a
## local and a `match` in each arm order, with a payload of 0 (which a folded reading would take for
## the absent case) and a non-zero one, across IR-built functions.
## A guard, not a moved value: the parent built all four functions too and every backend answered 42
## (measured); the head must keep that. 42 when every check held; otherwise the failed check's own
## code, 101 upward.
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
      output = "ir1711-u64",
    ),
  ],
)
## expect: run 42
