## IR-38 (#1786 cause 4) — `deref(h.p)` where `h : m::H` and `H.p : ptr(S)` is spelled in module `m`;
## the root declares a different `S`. The pointee the builder lays out is the type sema recorded for the
## `deref` node, resolved in the module whose text writes it (Modules §3, §4.1): `m::S`, three words.
## The builder accepts the record only after `type_span_resolves_alike` proves the spelling names the
## same type there and here (docs/ir.md §3.8 item 8). The ambiguous counterpart is
## `test/package/ir38_deref_foreign_amb`.
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
      output = "ir38-deref-foreign-same",
    ),
  ],
)
## Due 42 everywhere.
## expect: run 42
