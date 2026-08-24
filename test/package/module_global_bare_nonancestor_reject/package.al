## Modules §3/§4 — a BARE name reaches only this module's own and its ANCESTORS' declarations. `main`
## and `mod` are siblings under the anonymous package root, so `mod::child` is NOT a descendant of
## `main`: the bare `G` in it names nothing, `pub` or not. There is no glob import (§4.5), so the only
## spellings that reach it are the qualified `main::G` and an explicit binding `G := main::G`. Before
## this the bare name compiled to `movq -8(%rbp), %rax` — an uninitialised frame slot returning 0.
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
      output = "module-global-bare-nonancestor-reject",
    ),
  ],
)
