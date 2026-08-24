## e2e — Comptime §9.2 / Tooling §2.7: `target.os` / `target.env` / `target.container` are comptime
## facts a `comptime if` folds, exactly like `target.arch`. The x86 lower folded ONLY `arch`; the other
## three were unfoldable, and an unfoldable `comptime if` used to emit NEITHER branch — so BOTH arms'
## effects were silently deleted (`x` kept its prior value, with no diagnostic at all). This build's
## target is x86_64 / linux / gnu / elf (package.al's single `Target`).
main := fn() -> u64 {
  mut x : u64 = 0
  comptime if target.os == Os.linux { x = x + 1 } else { x = x + 100 }
  comptime if target.os == Os.windows { x = x + 100 } else { x = x + 2 }
  comptime if target.env == Env.gnu { x = x + 4 } else { x = x + 100 }
  comptime if target.container == Container.elf { x = x + 8 } else { x = x + 100 }
  comptime if target.os != Os.linux { x = x + 100 } else { x = x + 16 }
  comptime if not (target.env == Env.musl) { x = x + 11 } else { x = x + 100 }
  return x
}
