## Modules §1/§5 + §3 (#871) — two CHILD modules with one stem, `src/a/x.al` and `src/b/x.al`, are two
## modules (`a::x`, `b::x`), and `x` written in `a` is `a`'s own child: a file under `a/` puts `x`
## into `a`'s scope. The resolver matched a module head by its LAST segment and let the last candidate
## win, so both `(f) := x` projections bound `b::x::f` and the program returned 2 + 2. A root `src/x.al`
## is a third `x`, the one the ROOT names. 40 (a::x) + 2 (b::x) + 0 (x) = 42.
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
      output = "issue871-same-stem-children",
    ),
  ],
)
