## Issue #1753 / Functions §1.4 (FN-7), Modules §2 (MOD-3), §3, §5 — the conforming control of the two
## `issue1753_method_recv_reject*` packages: the same pair, the root's `get(u64)` and module `m`'s
## `get(W)`, each reached by UFCS from its OWN module. The root's `x.get()` on a `u64` names the root's
## `get` (1 + 1), and `m::probe`'s `w.get()` on a `W` names `m`'s (40): 2 + 40 = 42. Guards the
## refusal against over-reach: a call whose own module declares a matching `get` stays valid.
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
      output = "issue1753-method-recv-scoped",
    ),
  ],
)
## expect: run 42
