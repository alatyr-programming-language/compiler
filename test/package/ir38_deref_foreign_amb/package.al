## IR-38 (#1786 cause 4) — the refused counterpart of `test/package/ir38_deref_foreign_same`.
## Module `m` writes `H := struct { p : ptr(S), k : u64 }` but neither declares nor imports `S`; two
## siblings `a` and `b` each declare a `pub S`. A sibling's declarations are not in scope without an
## import (Modules §3), so the bare `S` in `m` names nothing and the package is ill-formed: due a reject.
## `check` accepts it and x86_64 answers 41, `b::S` picked silently (#1797).
## The shared-IR builder never lays out `deref(h.p)` in `main::rd` from a guess: `type_span_resolves_alike`
## finds `S` ambiguous and the read is refused `EDerefForeign` (docs/ir.md §3.8 item 8; e2e
## `ir38_deref_foreign_test`).
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
      output = "ir38-deref-foreign-amb",
    ),
  ],
)
## expect: reject
