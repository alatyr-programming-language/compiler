## #1755 review B1 / Modules §3, §5; Functions §1.4 (FN-7) — an unqualified call names the fns of the
## caller's own module, else its nearest declaring ancestor; a same-named `pick` of the unrelated
## module `zed` is reached only by a path. `main`'s `pick` takes a `u64` and is handed a struct `S`, so
## the call is ill-formed (Types §4.3). #1755's first head (e43bebee, native x86_64 on omen) counted
## `zed::pick` into an overload set, skipped the argument check and answered 206; the parent refused.
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
      output = "issue1746-bare-call-foreign-module-reject",
    ),
  ],
)
## expect: reject "type mismatch" "at line 4"
