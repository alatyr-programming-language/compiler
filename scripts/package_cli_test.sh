#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="${ALATYR:-$ROOT/target/debug/alatyr}"
PKG="$ROOT/test/package/profile_cli"

if [ ! -x "$CC" ]; then
  echo "FAIL package_cli: compiler not found at $CC" >&2
  echo "build it first with: seed/alatyr build package.al" >&2
  exit 1
fi

fail=0

run_noarg_help() {
  out=$(mktemp)
  err=$(mktemp)
  (cd "$PKG" && "$CC") >"$out" 2>"$err"
  got=$?
  if [ "$got" = "40" ] && grep -q '^Usage: run$' "$out" && [ ! -s "$err" ]; then
    echo "ok   noarg_help: usage on stdout, rc 40"
  else
    echo "FAIL noarg_help: rc $got, expected 40 with usage-only stdout"
    fail=1
  fi
  rm -f "$out" "$err"
}

run_new_scaffold() {
  tmp=$(mktemp -d)
  new_out=$(mktemp)
  new_err=$(mktemp)
  run_out=$(mktemp)
  run_err=$(mktemp)
  want_out=$(mktemp)
  (cd "$tmp" && "$CC" new demo) >"$new_out" 2>"$new_err"
  new_rc=$?
  run_rc=99
  if [ "$new_rc" = "0" ] && [ -f "$tmp/demo/package.al" ] && [ -f "$tmp/demo/src/main.al" ]; then
    (cd "$tmp" && "$CC" run demo/package.al) >"$run_out" 2>"$run_err"
    run_rc=$?
  fi
  printf 'Alatyr package ready\n' >"$want_out"
  if [ "$new_rc" = "0" ] \
    && [ ! -s "$new_out" ] && [ ! -s "$new_err" ] \
    && [ -f "$tmp/demo/package.al" ] && [ -f "$tmp/demo/src/main.al" ] \
    && grep -qF 'std::io::print("Alatyr package ready\n")' "$tmp/demo/src/main.al" \
    && [ "$run_rc" = "0" ] && cmp -s "$run_out" "$want_out" && [ ! -s "$run_err" ]; then
    echo "ok   new_scaffold: generated package runs with success text"
  else
    echo "FAIL new_scaffold: rc new=$new_rc run=$run_rc or generated package/output mismatch"
    fail=1
  fi
  rm -f "$new_out" "$new_err" "$run_out" "$run_err" "$want_out"
  rm -rf "$tmp"
}

run_zero_tests() {
  tmp=$(mktemp -d)
  out=$(mktemp)
  err=$(mktemp)
  want=$(mktemp)
  (cd "$tmp" && "$CC" new zero) >/dev/null 2>&1
  setup_rc=$?
  test_rc=99
  if [ "$setup_rc" = "0" ]; then
    (cd "$tmp" && "$CC" test zero/package.al) >"$out" 2>"$err"
    test_rc=$?
  fi
  printf 'alatyr test: 0 tests\n' >"$want"
  if [ "$test_rc" = "0" ] && cmp -s "$out" "$want" && [ ! -s "$err" ]; then
    echo "ok   zero_tests: rc 0 with explicit count"
  else
    echo "FAIL zero_tests: rc $test_rc or zero-test output mismatch"
    fail=1
  fi
  rm -f "$out" "$err" "$want"
  rm -rf "$tmp"
}

run_cross_target_test() {
  tmp=$(mktemp -d)
  mkdir -p "$tmp/src"
  cat >"$tmp/package.al" <<'EOF'
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  targets = [
    Target(name = "cross", arch = Arch.aarch64, os = Os.linux, env = Env.gnu, container = Container.elf,
           entry = "_start", output = "cross-target"),
    Target(name = "rv", arch = Arch.riscv64, os = Os.linux, env = Env.gnu, container = Container.elf,
           entry = "_start", output = "cross-target"),
  ]
)
EOF
  cat >"$tmp/src/main.al" <<'EOF'
main := fn() -> u64 { return 42 }

_start := fn() -> u64 { return 7 }

@test("cross target test")
fn() -> Result(usize, str) {
  return Result.Ok(0)
}
EOF
  (cd "$tmp" && "$CC" test --target cross package.al) >"$tmp/a64.out" 2>"$tmp/a64.err"
  a64_rc=$?
  a64_artifact="$tmp/target/cross/debug/cross-target.test"
  if [ "$a64_rc" = 0 ] && grep -qF 'test cross target test: ok' "$tmp/a64.out" \
    && [ ! -s "$tmp/a64.err" ] && [ -x "$a64_artifact" ]; then
    echo "ok   cross_target_test: AArch64 target assembles, runs under QEMU, and reports the test"
  else
    echo "FAIL cross_target_test: AArch64 rc=$a64_rc output=$(cat "$tmp/a64.out" 2>/dev/null) stderr=$(cat "$tmp/a64.err" 2>/dev/null)"
    fail=1
  fi
  (cd "$tmp" && "$CC" test --target rv package.al cross) >"$tmp/rv.out" 2>"$tmp/rv.err"
  rv_rc=$?
  rv_artifact="$tmp/target/rv/debug/cross-target.test"
  if [ "$rv_rc" = 0 ] && grep -qF 'test cross target test: ok' "$tmp/rv.out" \
    && [ ! -s "$tmp/rv.err" ] && [ -x "$rv_artifact" ]; then
    echo "ok   cross_target_test: RISC-V target and description filter work under QEMU"
  else
    echo "FAIL cross_target_test: RISC-V rc=$rv_rc output=$(cat "$tmp/rv.out" 2>/dev/null) stderr=$(cat "$tmp/rv.err" 2>/dev/null)"
    fail=1
  fi
  rm -rf "$tmp/target"
  (cd "$tmp" && "$CC" build --target cross package.al) >"$tmp/build.out" 2>"$tmp/build.err"
  build_rc=$?
  if [ "$build_rc" = 1 ] && grep -qF 'config: non-x86 targets are supported only by `test`' "$tmp/build.err" \
    && [ ! -e "$tmp/target" ]; then
    echo "ok   cross_target_test: non-test non-x86 command fails closed without an x86 impostor"
  else
    echo "FAIL cross_target_test: non-x86 build rc=$build_rc output=$(cat "$tmp/build.out" 2>/dev/null) stderr=$(cat "$tmp/build.err" 2>/dev/null)"
    fail=1
  fi
  rm -rf "$tmp"
}

run_expect() {
  name="$1"
  want="$2"
  shift 2
  (cd "$PKG" && "$CC" "$@") >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "ok   $name: rc $got"
  else
    echo "FAIL $name: rc $got want $want"
    fail=1
  fi
}

# Tooling §4 / Stdlib §7 — compiler profile selectors stop at the `run` program-argument separator.
# The temporary package returns a distinct value for each exact argv shape and selected profile, so a
# profile-looking token cannot pass by merely preserving argv length or by selecting the wrong profile.
run_profile_program_args() {
  local tmp="$ROOT/target/profile-program-args"
  rm -rf "$tmp"
  mkdir -p "$tmp/src"
  cat >"$tmp/package.al" <<'EOF'
app := Package(
  version = "0.1.0",
  source_dir = "src",
  target_dir = "target",
  profile_flags = [
    FlagDecl(name = "release_path", type = bool, default = false),
  ],
  profiles = [
    Profile(
      name = "release",
      flags = [FlagSet(name = "release_path", value = true)],
    ),
  ],
  targets = [
    Target(
      arch = Arch.x86_64,
      os = Os.linux,
      env = Env.gnu,
      container = Container.elf,
      entry = "_start",
      output = "profile-program-args",
    ),
  ],
)
EOF
  cat >"$tmp/src/main.al" <<'EOF'
main := fn() -> u64 {
  own := std::os::arena(131072)
  mut ar := std::os::region(ptr(own))
  av := std::os::args(ptr(mut ar))
  mut ok : u64 = 0
  if av.len == 2 {
    arg := av[1]
    if arg == "--release" {
      comptime if build.release_path { ok = 42 } else { ok = 7 }
    } else if arg == "neutral-arg" {
      comptime if build.release_path { ok = 43 } else { ok = 41 }
    }
  } else if av.len == 3 {
    if av[1] == "--profile" and av[2] == "release" {
      comptime if build.release_path { ok = 42 } else { ok = 7 }
    }
  }
  std::os::free(own)
  return ok
}
EOF

  profile_case() {
    local name="$1" want="$2"
    shift 2
    (cd "$tmp" && "$CC" "$@") >/dev/null 2>&1
    local got=$?
    if [ "$got" = "$want" ]; then
      echo "ok   $name: rc $got"
    else
      echo "FAIL $name: rc $got want $want"
      fail=1
    fi
  }

  profile_case profile_arg_default_release 7 run package.al -- --release
  profile_case profile_arg_default_named 7 run package.al -- --profile release
  profile_case profile_arg_default_neutral 41 run package.al -- neutral-arg
  profile_case profile_arg_explicit_release 42 run --release package.al -- --release
  profile_case profile_arg_explicit_named 42 run --profile release package.al -- --profile release
  profile_case profile_arg_explicit_neutral 43 run --release package.al -- neutral-arg
  rm -rf "$tmp"
}

# Modules §8 / Tooling §2.4 — PATH DEPENDENCIES.
#
# (1) DECLARING a dependency must not move the root package's own emission. Adding a `dependencies`
#     field alone used to make discovery return an EMPTY module list, fall back to compiling
#     `package.al` (the manifest) as a single-file program, and fail at link on an undefined `main`.
# (2) USING one through its ALIAS namespace (`d::math::answer()`) must resolve: a dependency's items
#     live under `<alias>::<module>::…`, so the dependency's module is named `d__math` and the call
#     mangles onto `d__math__answer` — not onto a flat `math__answer`.
# Both are driven through `check`, `run` and the built artifact, which must agree on 42.
run_path_dep() {
  d="$1"; want_sym="$2"
  p="$ROOT/test/package/$d"
  [ -f "$p/package.al" ] || { echo "FAIL path_dep($d): no $p/package.al"; fail=1; return; }
  rm -rf "$p/target"
  (cd "$p" && "$CC" check package.al) >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "ok   path_dep($d): check 0"; else echo "FAIL path_dep($d): check rc $got want 0"; fail=1; fi
  (cd "$p" && "$CC" run package.al) >/dev/null 2>&1; got=$?
  if [ "$got" = 42 ]; then echo "ok   path_dep($d): run 42"; else echo "FAIL path_dep($d): run rc $got want 42"; fail=1; fi
  (cd "$p" && "$CC" build package.al) >/dev/null 2>&1
  exe=$(find "$p/target/debug" -maxdepth 1 -type f ! -name '*.s' ! -name '*.o' 2>/dev/null | head -1)
  if [ -x "${exe:-/nonexistent}" ]; then
    "$exe" >/dev/null 2>&1; got=$?
    if [ "$got" = 42 ]; then echo "ok   path_dep($d): artifact 42"; else echo "FAIL path_dep($d): artifact rc $got want 42"; fail=1; fi
    if nm "$exe" | grep -qE " T $want_sym\$"; then
      echo "ok   path_dep($d): symbol $want_sym"
    else
      echo "FAIL path_dep($d): symbol $want_sym missing"; fail=1
    fi
  else
    echo "FAIL path_dep($d): build produced no artifact"; fail=1
  fi
  rm -rf "$p/target"
}

# Modules §8 / Tooling §2.4 — an unsupported or unresolvable dependency DECLARATION is a LOCATED
# Config diagnostic for every package command, never a silently different artifact: a `DepSource.Git`
# source is not resolved in this slice, and a path dependency with no `package.al` cannot be honoured.
run_dep_config_diag() {
  tmp=$(mktemp -d)
  mkdir -p "$tmp/git/src" "$tmp/miss/src"
  printf 'main := fn() -> u64 { return 1 }\n' > "$tmp/git/src/main.al"
  cp "$tmp/git/src/main.al" "$tmp/miss/src/main.al"
  cat > "$tmp/git/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  dependencies = [
    Dependency(name = "g", source = DepSource.Git("https://example.invalid/g.git", GitRef.Branch("main"))),
  ],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "g")])
EOF
  cat > "$tmp/miss/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  dependencies = [
    Dependency(name = "absent", alias = "a", source = DepSource.Path("../absent")),
  ],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "m")])
EOF
  for case in git miss; do
    case "$case" in
      git)  want="config: a git dependency source is not supported yet" ;;
      miss) want="config: a path dependency has no package manifest" ;;
    esac
    for cmd in check build run; do
      out=$( cd "$tmp/$case" && "$CC" "$cmd" package.al 2>&1 >/dev/null ); got=$?
      if [ "$got" = 1 ] && printf '%s' "$out" | grep -qF "$want" && printf '%s' "$out" | grep -qE 'at line [0-9]+ in '; then
        echo "ok   dep_config_diag($case/$cmd): rc 1 + located diagnostic"
      else
        echo "FAIL dep_config_diag($case/$cmd): rc=$got out=$out"; fail=1
      fi
    done
    [ -e "$tmp/$case/target" ] && { echo "FAIL dep_config_diag($case): a rejected configuration still produced target/"; fail=1; }
  done
  rm -rf "$tmp"
}

# Tooling §2.4 / Manifest appendix §3 — the manifest scanner must follow the STRUCTURE of the
# Package/Dependency values, not spellings in a raw byte search. A qualified DepSource variant may
# contain trivia before its call, a misspelled variant is an explicit configuration error, and an
# unknown field must not disappear merely because the manifest checker has not evaluated that value.
run_manifest_structural_config() {
  tmp=$(mktemp -d)
  mkdir -p "$tmp"/{lower,spaced_git,spaced_path,unknown_package,unknown_dependency,comments_strings,spaced_alias}/src
  for case in lower spaced_git spaced_path unknown_package unknown_dependency comments_strings; do
    printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/$case/src/main.al"
  done
  cat > "$tmp/lower/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  dependencies = [Dependency(name = "g", source = DepSource.git("https://example.invalid/g.git", GitRef.Branch("main")))],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "lower")])
EOF
  cat > "$tmp/spaced_git/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  dependencies = [Dependency(name = "g", source = DepSource.Git ("https://example.invalid/g.git", GitRef.Branch("main")))],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "spaced-git")])
EOF
  cat > "$tmp/spaced_path/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  dependencies = [Dependency(name = "absent", source = DepSource.Path ("../absent"))],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "spaced-path")])
EOF
  cat > "$tmp/unknown_package/package.al" <<'EOF'
app := Package(version = "0.1.0", mystery = "ignored", source_dir = "src", target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "unknown-package")])
EOF
  cat > "$tmp/unknown_dependency/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  dependencies = [Dependency(name = "absent", mystery = "ignored", source = DepSource.Path ("../absent"))],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "unknown-dependency")])
EOF
  cat > "$tmp/comments_strings/package.al" <<'EOF'
# DepSource.Path ("../missing") and Dependency (mystery = "ignored") are comments, not declarations.
app := Package(version = "0.1.0", description = "DepSource.Git (https://example.invalid/ghost.git) # literal",
  source_dir = "src", target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "comments-strings")])
EOF
  for case in lower spaced_git spaced_path unknown_package unknown_dependency; do
    out=$(cd "$tmp/$case" && "$CC" check package.al 2>&1); got=$?
    case "$case" in
      lower)           want='unknown DepSource variant git' ;;
      spaced_git)     want='a git dependency source is not supported yet' ;;
      spaced_path)    want='a path dependency has no package manifest' ;;
      unknown_package) want='Package field mystery' ;;
      unknown_dependency) want='Dependency field mystery' ;;
    esac
    if [ "$got" = 1 ] && printf '%s' "$out" | grep -qF "$want" && printf '%s' "$out" | grep -qE 'at line [0-9]+ in '; then
      echo "ok   manifest_structural_config($case): rc 1 + located diagnostic"
    else
      echo "FAIL manifest_structural_config($case): rc=$got out=$out (want $want)"; fail=1
    fi
  done
  out=$(cd "$tmp/comments_strings" && "$CC" check package.al 2>&1); got=$?
  if [ "$got" = 0 ] && [ -z "$out" ]; then
    echo "ok   manifest_structural_config(comments_strings): comments and string contents ignored"
  else
    echo "FAIL manifest_structural_config(comments_strings): rc=$got out=$out"; fail=1
  fi

  # `Dependency (` plus a source field before a later alias exercises the association boundary: the
  # alias must come from the same complete record, not from bytes before the source expression.
  mkdir -p "$tmp/spaced_alias/dep/src"
  printf 'main := fn() -> u64 { return d::math::answer() }\n' > "$tmp/spaced_alias/src/main.al"
  printf 'pub answer := fn() -> u64 { return 42 }\n' > "$tmp/spaced_alias/dep/src/math.al"
  cat > "$tmp/spaced_alias/dep/package.al" <<'EOF'
depapp := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "dep")])
EOF
  cat > "$tmp/spaced_alias/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  dependencies = [Dependency (
    source = DepSource.Path ("dep"), alias = "d", name = "dep"
  )],
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "spaced-alias")])
EOF
  out=$(cd "$tmp/spaced_alias" && "$CC" check package.al 2>&1); got=$?
  if [ "$got" = 0 ] && [ -z "$out" ]; then
    echo "ok   manifest_structural_config(spaced_alias): trivia and post-source alias preserved"
  else
    echo "FAIL manifest_structural_config(spaced_alias): rc=$got out=$out"; fail=1
  fi
  rm -rf "$tmp"
}

# MOD-11 (Modules §8, Tooling §2.4) — THE DEPENDENCY GRAPH IS ACYCLIC. A chain that returns to a
# package already on it is a Config diagnostic PRINTING THE CLOSING CHAIN of sources, never a silently
# deduplicated edge: a package is compiled against its dependencies' finished interfaces, so a cycle
# has no valid build order, and accepting one makes the artifact depend on traversal order. Before this
# slice a two- or three-package cycle BUILT (rc 0, an artifact on disk) because the BFS seen-set
# swallowed the closing edge, and `DepSource.Path(".")` — a package depending on itself — was reported
# as a MISSING MANIFEST at `/package.al`, because normalizing `./.` produced the empty string and the
# dependency path came out absolute.
#
# The fourth case is the one that keeps the rule honest: a DIAMOND (two parents depending on one child)
# is NOT a cycle. It must keep building, run to 42, and emit the child's symbol exactly ONCE — a cycle
# check built on the traversal path rather than the edge set gets this wrong in one direction or the
# other. All three commands are asserted, so `check` cannot accept a graph `build` rejects.
run_dep_cycle_diag() {
  tmp=$(mktemp -d)
  mkpkg() { # dir, output, dependency lines
    mkdir -p "$tmp/$1/src"
    printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/$1/src/main.al"
    { printf 'app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",\n'
      printf '  dependencies = [\n%s\n  ],\n' "$3"
      printf '  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "%s")])\n' "$2"
    } > "$tmp/$1/package.al"
  }
  dep() { printf '    Dependency(name = "%s", alias = "%s", source = DepSource.Path("%s")),' "$1" "$1" "$2"; }
  # (1) a package that depends on ITSELF
  mkpkg self s "$(dep me '.')"
  # (2) a -> b -> a
  mkpkg two/a a "$(dep b '../b')"
  mkpkg two/b b "$(dep a '../a')"
  # (3) a -> b -> c -> a
  mkpkg three/a a "$(dep b '../b')"
  mkpkg three/b b "$(dep c '../c')"
  mkpkg three/c c "$(dep a '../a')"
  for case in self two/a three/a; do
    for cmd in check build run; do
      out=$( cd "$tmp/$case" && "$CC" "$cmd" package.al 2>&1 >/dev/null ); got=$?
      if [ "$got" = 1 ] \
        && printf '%s' "$out" | grep -qF 'config: the package dependency graph has a cycle' \
        && printf '%s' "$out" | grep -qF ' -> ' \
        && printf '%s' "$out" | grep -qE 'at line [0-9]+ in '; then
        echo "ok   dep_cycle($case/$cmd): rc 1 + located closing chain"
      else
        echo "FAIL dep_cycle($case/$cmd): rc=$got out=$out"; fail=1
      fi
    done
    [ -e "$tmp/$case/target" ] && { echo "FAIL dep_cycle($case): a rejected configuration still produced target/"; fail=1; }
  done
  # (4) THE NEGATIVE: a diamond. root depends on a, b and c; a and b each depend on c. One child, two
  # parents, no cycle — and exactly one copy of the child's module in the program.
  mkdir -p "$tmp/dia/c/src"
  printf 'pub answer := fn() -> u64 { return 35 }\n' > "$tmp/dia/c/src/math.al"
  printf 'lib := Package(version = "0.1.0", source_dir = "src", target_dir = "target",\n  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "c")])\n' > "$tmp/dia/c/package.al"
  mkpkg dia/root root "$(dep a '../a')
$(dep b '../b')
$(dep c '../c')"
  printf 'main := fn() -> u64 { return 7 + c::math::answer() }\n' > "$tmp/dia/root/src/main.al"
  mkpkg dia/a a "$(dep c '../c')"
  mkpkg dia/b b "$(dep c '../c')"
  out=$( cd "$tmp/dia/root" && "$CC" check package.al 2>&1 ); got=$?
  if [ "$got" = 0 ] && [ -z "$out" ]; then
    echo "ok   dep_cycle(diamond/check): rc 0, no diagnostic"
  else
    echo "FAIL dep_cycle(diamond/check): rc=$got out=$out"; fail=1
  fi
  out=$( cd "$tmp/dia/root" && "$CC" build package.al 2>&1 ); got=$?
  if [ "$got" = 0 ] && [ -x "$tmp/dia/root/target/debug/root" ]; then
    "$tmp/dia/root/target/debug/root" >/dev/null 2>&1; arc=$?
    nsym=$(nm "$tmp/dia/root/target/debug/root" | grep -cE ' T c__math__answer')
    if [ "$arc" = 42 ] && [ "$nsym" = 1 ]; then
      echo "ok   dep_cycle(diamond/build): 42, the shared child emitted once"
    else
      echo "FAIL dep_cycle(diamond/build): artifact rc=$arc c__math__answer x$nsym (want 42, x1)"; fail=1
    fi
  else
    echo "FAIL dep_cycle(diamond/build): rc=$got out=$out"; fail=1
  fi
  unset -f mkpkg dep
  rm -rf "$tmp"
}

# MOD-10 (Modules §8, Tooling §2.4) — IDENTITY IN THE GRAPH IS THE SOURCE, NORMALIZED. An alias is
# package-local naming and never identifies a package; a path dependency is identified by its
# LEXICALLY-NORMALIZED ABSOLUTE path. Keying the graph by the relative spelling instead split ONE
# dependency into two whenever two parents spelled it differently: the same package was walked twice,
# its modules compiled twice under the same alias, and the build died on `c__math__answer' is already
# defined (rc 13) while `check` still returned 0. The same hole showed in the MOD-11 chain: an `a -> b`
# cycle printed `../b -> ../a -> ../b`, naming the ROOT package by the `../a` spelling `b`'s manifest
# used for it rather than as itself — the root was a THIRD node in the graph, distinct from its own
# dependency. So the chain being absolute is a direct witness that identity, not spelling, keys it.
#
# Normalization stays LEXICAL (no realpath): `..` pops a segment as text. Only the base is the
# kernel's resolved cwd, so two spellings differing by a symlink below it remain two sources — the
# same deliberate choice MOD-10 makes for two spellings of one git URL.
run_dep_spelling_identity() {
  tmp=$(mktemp -d)
  mkpkg() { # dir, output, dependency lines
    mkdir -p "$tmp/$1/src"
    printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/$1/src/main.al"
    { printf 'app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",\n'
      printf '  dependencies = [\n%s\n  ],\n' "$3"
      printf '  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "%s")])\n' "$2"
    } > "$tmp/$1/package.al"
  }
  dep() { printf '    Dependency(name = "%s", alias = "%s", source = DepSource.Path("%s")),' "$1" "$1" "$2"; }
  # A diamond over ONE child spelled TWO ways: `a` reaches it as `../c`, `b` as `../../sp/c`. Both
  # lexically normalize to the same absolute directory, so this is one package, not two.
  mkdir -p "$tmp/sp/c/src"
  printf 'pub answer := fn() -> u64 { return 35 }\n' > "$tmp/sp/c/src/math.al"
  printf 'lib := Package(version = "0.1.0", source_dir = "src", target_dir = "target",\n  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, entry = "_start", output = "c")])\n' > "$tmp/sp/c/package.al"
  mkpkg sp/root root "$(dep a '../a')
$(dep b '../b')
$(dep c '../c')"
  printf 'main := fn() -> u64 { return 7 + c::math::answer() }\n' > "$tmp/sp/root/src/main.al"
  mkpkg sp/a a "$(dep c '../c')"
  mkpkg sp/b b "$(dep c '../../sp/c')"
  out=$( cd "$tmp/sp/root" && "$CC" check package.al 2>&1 ); got=$?
  if [ "$got" = 0 ] && [ -z "$out" ]; then
    echo "ok   dep_spelling(check): rc 0, no diagnostic"
  else
    echo "FAIL dep_spelling(check): rc=$got out=$out"; fail=1
  fi
  out=$( cd "$tmp/sp/root" && "$CC" build package.al 2>&1 ); got=$?
  if [ "$got" = 0 ] && [ -x "$tmp/sp/root/target/debug/root" ]; then
    "$tmp/sp/root/target/debug/root" >/dev/null 2>&1; arc=$?
    nsym=$(nm "$tmp/sp/root/target/debug/root" | grep -cE ' T c__math__answer')
    if [ "$arc" = 42 ] && [ "$nsym" = 1 ]; then
      echo "ok   dep_spelling(build): two spellings resolved to ONE package"
    else
      echo "FAIL dep_spelling(build): artifact rc=$arc c__math__answer x$nsym (want 42, x1)"; fail=1
    fi
  else
    echo "FAIL dep_spelling(build): rc=$got out=$out"; fail=1
  fi
  # The cycle chain is now keyed by identity too: `a -> b -> a` names TWO sources, each by its absolute
  # path — the root is the same node as the `../a` its dependency reaches back through, not a third.
  mkpkg cyc/a a "$(dep b '../b')"
  mkpkg cyc/b b "$(dep a '../a')"
  out=$( cd "$tmp/cyc/a" && "$CC" check package.al 2>&1 >/dev/null ); got=$?
  chain=$(printf '%s' "$out" | sed -n 's/.*cycle (\(.*\)) at line.*/\1/p')
  narr=$(printf '%s' "$chain" | grep -o ' -> ' | grep -c .)
  head=${chain%% *}
  if [ "$got" = 1 ] && [ "$narr" = 2 ] && [ "${head#/}" != "$head" ]; then
    echo "ok   dep_spelling(cycle): 2 sources in the chain, keyed absolute"
  else
    echo "FAIL dep_spelling(cycle): rc=$got arrows=$narr chain=$chain"; fail=1
  fi
  unset -f mkpkg dep
  rm -rf "$tmp"
}

# Tooling §2.2 / §4 / §5 — `check` validates configuration, parsing and semantics without requiring an
# artifact-producing target. `Kind.source` is therefore a deliberate exception to build/run/test
# parity: `check` accepts it (rc 0, no artifact), while the artifact-producing commands keep the
# located unsupported-kind reject (rc 42). Other unhonourable kinds remain rejected by every command.
#
# The assertion is deliberately a COMPARISON for the rejected shapes, not a table of expected strings:
# the commands must agree on the exit code AND print the same located diagnostic, byte for byte. The
# one intentional exception is checked explicitly so a future change cannot accidentally turn source
# validation back into an artifact-kind reject. Dependency-shape rejects are included because they
# must STAY shared — they run through one resolver today (`build_paths`, whose Config latch aborts every
# command), and this pins that they do.
run_check_build_parity() {
  tmp=$(mktemp -d)
  tgt() { printf 'targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf, %sentry = "_start", output = "p")])' "$1"; }
  mkcase() { # name, manifest body after `source_dir`/`target_dir`
    mkdir -p "$tmp/$1/src"
    printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/$1/src/main.al"
    printf 'app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",\n  %s\n' "$2" > "$tmp/$1/package.al"
  }
  mkcase kind_shared "$(tgt 'kind = Kind.shared_lib, ')"
  mkcase kind_source "$(tgt 'kind = Kind.source, ')"
  mkcase kind_bogus  "$(tgt 'kind = Kind.no_such_kind, ')"
  mkcase dep_git "dependencies = [Dependency(name = \"g\", source = DepSource.Git(\"https://example.invalid/g.git\", GitRef.Commit(\"0123456789abcdef0123456789abcdef01234567\")))],
  $(tgt '')"
  mkcase dep_missing "dependencies = [Dependency(name = \"absent\", alias = \"a\", source = DepSource.Path(\"../absent\"))],
  $(tgt '')"
  mkcase dep_selfcycle "dependencies = [Dependency(name = \"me\", alias = \"m\", source = DepSource.Path(\".\"))],
  $(tgt '')"
  # `run` and `test` compile the package too, so the parity spans all FOUR verbs, not just check/build:
  # a `Kind.shared_lib` target cannot produce something to run, and an unrecognized `Kind.…` is a Config
  # error whatever the verb. Measured before this: `run` and `test` returned 0 on every kind case.
  for case in kind_shared kind_source kind_bogus dep_git dep_missing dep_selfcycle; do
    cerr=$(mktemp); berr=$(mktemp); rerr=$(mktemp); terr=$(mktemp)
    ( cd "$tmp/$case" && rm -rf target && "$CC" check package.al >/dev/null 2>"$cerr" ); crc=$?
    cleft=0; [ -e "$tmp/$case/target" ] && cleft=1
    ( cd "$tmp/$case" && rm -rf target && "$CC" build package.al >/dev/null 2>"$berr" ); brc=$?
    bleft=0; [ -e "$tmp/$case/target" ] && bleft=1
    ( cd "$tmp/$case" && rm -rf target && "$CC" run package.al >/dev/null 2>"$rerr" ); rrc=$?
    ( cd "$tmp/$case" && rm -rf target && "$CC" test package.al >/dev/null 2>"$terr" ); trc=$?
    if [ "$case" = kind_source ]; then
      if [ "$crc" = 0 ] && [ ! -s "$cerr" ] && [ "$cleft" = 0 ] \
        && [ "$brc" = 42 ] && [ "$bleft" = 0 ] \
        && [ "$rrc" = 42 ] && [ "$trc" = 42 ] \
        && cmp -s "$berr" "$rerr" && cmp -s "$berr" "$terr" \
        && grep -qF 'config: Target.kind = Kind.source is not implemented yet' "$berr"; then
        echo "ok   check_build_parity(kind_source): check accepts source without target/, build/run/test keep located reject"
      else
        echo "FAIL check_build_parity(kind_source): check rc=$crc stderr=$(cat "$cerr") build=$brc run=$rrc test=$trc target(check=$cleft build=$bleft)"
        echo "     build: $(cat "$berr")"
        fail=1
      fi
      rm -f "$cerr" "$berr" "$rerr" "$terr"
      continue
    fi
    if [ "$rrc" != "$crc" ] || ! cmp -s "$cerr" "$rerr"; then
      echo "FAIL check_build_parity($case): run rc=$rrc want $crc (same diagnostic)"; fail=1; continue
    fi
    if [ "$trc" != "$crc" ] || ! cmp -s "$cerr" "$terr"; then
      echo "FAIL check_build_parity($case): test rc=$trc want $crc (same diagnostic)"; fail=1; continue
    fi
    if [ "$crc" = "$brc" ] && [ "$crc" != 0 ] && cmp -s "$cerr" "$berr" \
      && grep -qE 'at line [0-9]+ in ' "$cerr" && [ "$cleft" = 0 ] && [ "$bleft" = 0 ]; then
      echo "ok   check_build_parity($case): all four verbs rc $crc, same located diagnostic, no target/"
    else
      echo "FAIL check_build_parity($case): check rc=$crc build rc=$brc target(check=$cleft build=$bleft)"
      echo "     check: $(cat "$cerr")"
      echo "     build: $(cat "$berr")"
      fail=1
    fi
    rm -f "$cerr" "$berr"
  done
  unset -f tgt mkcase
  rm -rf "$tmp"
}

# TOOL-7 (Tooling §4.1) — THE TEST ARTIFACT OWNS ITS ENTRY. What `alatyr test` builds is a separate
# artifact whose entry point is the RUNNER's: the package's own entry — the manifest `Target.entry`
# symbol and any entry the program declares itself — is NOT linked into it. Before the rule, a program
# that declares its own entry was unbuildable under `test` for a reason unrelated to its tests: the
# assembler rejected the duplicate ("symbol `_start' is already defined", rc 13). The complementary
# half (TOOL-5) must not regress: `build`/`run` keep the program's entry and drop the `@test` items,
# checked here on the built artifact (entry symbol present as a global, no `__test` body linked).
run_test_entry_pkg() { # package dir, output artifact stem, entry symbol, report substring
  d="$1"; outnm="$2"; sym="$3"; want="$4"
  p="$ROOT/test/package/$d"
  [ -f "$p/package.al" ] || { echo "FAIL test_entry($d): no $p/package.al"; fail=1; return; }
  rm -rf "$p/target"
  report=$( (cd "$p" && "$CC" test package.al) 2>&1 ); got=$?
  if [ "$got" = 0 ] && case "$report" in *"test $want: ok"*) true ;; *) false ;; esac; then
    echo "ok   test_entry($d): test artifact links the runner's entry, not the package's"
  else
    echo "FAIL test_entry($d): rc=$got output=$report"; fail=1
  fi
  (cd "$p" && "$CC" run package.al) >/dev/null 2>&1; got=$?
  if [ "$got" = 42 ]; then echo "ok   test_entry($d): run keeps the package entry (42)"; else echo "FAIL test_entry($d): run rc $got want 42"; fail=1; fi
  if [ -x "$p/target/debug/$outnm" ] && [ -s "$p/target/debug/$outnm.s" ] && [ -s "$p/target/debug/$outnm.o" ]; then
    echo "ok   test_entry($d): TOOL-10 keeps run artifact and intermediates under target/"
  else
    echo "FAIL test_entry($d): TOOL-10 run artifact/intermediates missing from target/"; fail=1
  fi
  (cd "$p" && "$CC" build package.al) >/dev/null 2>&1
  # TOOL-10 leaves both the normal package artifact and the inspectable test artifact. Select the
  # manifest-declared output explicitly; taking the first directory entry can accidentally execute
  # `<output>.test` after a preceding `alatyr test`.
  exe="$p/target/debug/$outnm"
  if [ -x "${exe:-/nonexistent}" ]; then
    "$exe" >/dev/null 2>&1; got=$?
    if [ "$got" = 42 ]; then echo "ok   test_entry($d): artifact 42"; else echo "FAIL test_entry($d): artifact rc $got want 42"; fail=1; fi
    if nm "$exe" | grep -qE " T $sym\$"; then
      echo "ok   test_entry($d): build keeps the entry symbol $sym"
    else
      echo "FAIL test_entry($d): entry symbol $sym missing from the executable"; fail=1
    fi
    if nm "$exe" | grep -qE '__test'; then
      echo "FAIL test_entry($d): a @test body leaked into the executable"; fail=1
    else
      echo "ok   test_entry($d): executable omits the @test bodies"
    fi
  else
    echo "FAIL test_entry($d): build produced no artifact"; fail=1
  fi
  if [ -x "$p/target/debug/$outnm.test" ] && [ -s "$p/target/debug/$outnm.test.s" ] && [ -s "$p/target/debug/$outnm.test.o" ]; then
    echo "ok   test_entry($d): TOOL-10 keeps the test artifact and intermediates under target/"
  else
    echo "FAIL test_entry($d): TOOL-10 test artifact/intermediates missing from target/"; fail=1
  fi
  rm -rf "$p/target"
}

# The same rule for a BARE FILE-LIST `test`, which has no manifest and therefore the default entry
# `_start`: the program declares it, the runner supplies its own, and only the runner's is linked.
run_test_entry_file() { # fixture stem, report substring
  f="$ROOT/test/$1.al"
  [ -f "$f" ] || { echo "FAIL test_entry($1): no $f"; fail=1; return; }
  report=$("$CC" test "$f" 2>&1); got=$?
  if [ "$got" = 0 ] && case "$report" in *"test $2: ok"*) true ;; *) false ;; esac; then
    echo "ok   test_entry($1): single-file program with its own entry tests green"
  else
    echo "FAIL test_entry($1): rc=$got output=$report"; fail=1
  fi
}

# TOOL-10 — a manifest-less `run` may use /tmp, but it must remove the executable and every
# intermediate it created before returning. Exercise both the ordinary single-object path and the
# opt-in split path.
#
# Asserted on the invocation's OWN files, not on a before/after snapshot of every `.alatyr-run-*`
# in /tmp. The snapshot form false-failed whenever a second gate ran concurrently — and worse, it
# could also PASS while leaking, if the other gate happened to remove a file in the same window.
# `cli.al` names the artifact `/tmp/.alatyr-run-<pid>` from the compiler's own getpid, and the
# derived `.s`/`.o` carry the same suffix, so the exact file set is knowable: run the compiler via
# `exec` inside the backgrounded subshell, which makes `$!` the compiler's own pid rather than a
# shell wrapper's, and require nothing bearing that suffix to survive. Independent of what any
# other process is doing in /tmp, and it names the leaked file instead of just reporting a delta.
run_manifestless_cleanup() {
  tmp=$(mktemp -d)
  cp "$ROOT/test/smoke.al" "$tmp/main.al"
  for split in off on; do
    if [ "$split" = on ]; then
      ( cd "$tmp"; export ALATYR_OSPLIT=1; exec "$CC" run main.al ) >/dev/null 2>&1 &
    else
      ( cd "$tmp"; exec "$CC" run main.al ) >/dev/null 2>&1 &
    fi
    pid=$!
    wait "$pid"; got=$?
    left=$(find /tmp -maxdepth 1 -name ".alatyr-run-$pid*" 2>/dev/null | sort | tr '\n' ' ')
    if [ "$got" != 42 ]; then
      echo "FAIL manifestless_cleanup($split): rc=$got, want 42"; fail=1
    elif [ -n "$left" ]; then
      echo "FAIL manifestless_cleanup($split): run leaked its own artifacts: $left"; fail=1
    else
      echo "ok   manifestless_cleanup($split): run removed its temporary artifact set"
    fi
  done
  rm -rf "$tmp"
}

# MODULE-GLOBAL-REF (Modules §3, Memory §2.2) — a module-level global reference that this module
# may NOT address must be a LOCATED REJECT, never a fresh frame local. The pre-fix emitter turned a
# cross-module READ into `movq -8(%rbp), %rax` (an uninitialised slot, silently 0), a cross-module
# WRITE into a frame store that smashed the stack (SIGSEGV), and the qualified `mod::G = v` into a
# silent no-op. Every case below is package-shaped (it needs two modules), so it lives here rather
# than in the single-file `build_reject` table.
run_pkg_check_build_located() { # package dir, source line, naming module
  d="$1"; line="$2"; module="$3"
  p="$ROOT/test/package/$d"
  [ -f "$p/package.al" ] || { echo "FAIL pkg_check_build_located($d): no $p/package.al"; fail=1; return; }
  want="alatyr: check: invalid at line $line in $module"
  rm -rf "$p/target"
  check_out=$( (cd "$p" && "$CC" check package.al) 2>&1 ); check_rc=$?
  rm -rf "$p/target"
  build_out=$( (cd "$p" && "$CC" build package.al) 2>&1 ); build_rc=$?
  rm -rf "$p/target"
  if [ "$check_rc" != 1 ] || [ "$build_rc" != 1 ]; then
    echo "FAIL pkg_check_build_located($d): check rc=$check_rc build rc=$build_rc, want 1/1"; fail=1
  elif [ "$check_out" != "$build_out" ]; then
    echo "FAIL pkg_check_build_located($d): check/build diagnostics differ"; fail=1
  elif [ "$check_out" != "$want" ]; then
    echo "FAIL pkg_check_build_located($d): got '$check_out', want '$want'"; fail=1
  else
    echo "ok   pkg_check_build_located($d): check/build rc 1, $want"
  fi
}

# The positive half: a package whose cross-module global references ARE legal must build, link and
# exit with its own expected value (read from the fixture, not assumed to be 42), through `run` and
# through the built artifact alike. `want_sym` (optional) is a `.data` label that must be present,
# proving the reference was addressed by the MOD-6 mangled symbol and not by a frame slot.
run_pkg_exit() { # package dir, artifact stem, want-exit, [want symbol ...]
  d="$1"; outnm="$2"; want="$3"; shift 3
  p="$ROOT/test/package/$d"
  [ -f "$p/package.al" ] || { echo "FAIL pkg_exit($d): no $p/package.al"; fail=1; return; }
  rm -rf "$p/target"
  (cd "$p" && "$CC" check package.al) >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "ok   pkg_exit($d): check 0"; else echo "FAIL pkg_exit($d): check rc $got want 0"; fail=1; fi
  (cd "$p" && "$CC" run package.al) >/dev/null 2>&1; got=$?
  if [ "$got" = "$want" ]; then echo "ok   pkg_exit($d): run $want"; else echo "FAIL pkg_exit($d): run rc $got want $want"; fail=1; fi
  (cd "$p" && "$CC" build package.al) >/dev/null 2>&1
  exe="$p/target/debug/$outnm"
  if [ -x "$exe" ]; then
    "$exe" >/dev/null 2>&1; got=$?
    if [ "$got" = "$want" ]; then echo "ok   pkg_exit($d): artifact $want"; else echo "FAIL pkg_exit($d): artifact rc $got want $want"; fail=1; fi
    syms=$(nm "$exe")
    for sym in "$@"; do
      if printf '%s\n' "$syms" | grep -qE " $sym\$"; then
        echo "ok   pkg_exit($d): symbol $sym"
      else
        echo "FAIL pkg_exit($d): symbol $sym missing"; fail=1
      fi
    done
  else
    echo "FAIL pkg_exit($d): build produced no artifact at target/debug/$outnm"; fail=1
  fi
  rm -rf "$p/target"
}

# Tooling §4 / Modules §6.1, §6.3 — a package entry is a declaration path, not an arbitrary linker
# argument. The negative package must fail in the driver's Codegen pre-emission check (with no target
# directory and therefore no assembler/linker artifacts); `check` remains semantic-only. The positive
# package proves that the same qualified path resolves through an exact `@export` symbol and reaches
# the intended entry in both `run` and the retained build artifact.
run_tool12_entry_resolution() {
  local root="$ROOT/test/package/tool12_entry_resolution"
  local bad="$root/negative" good="$root/positive"
  local bad_out bad_rc good_out good_rc artifact_rc syms
  rm -rf "$bad/target" "$good/target"

  bad_out=$(cd "$bad" && "$CC" check package.al 2>&1); bad_rc=$?
  if [ "$bad_rc" = 0 ] && [ -z "$bad_out" ] && [ ! -e "$bad/target" ]; then
    echo "ok   tool12_entry_resolution: unresolved entry check is semantic-only and leaves no artifact"
  else
    echo "FAIL tool12_entry_resolution: check rc=$bad_rc out=$bad_out or target/ exists"; fail=1
  fi

  bad_out=$(cd "$bad" && "$CC" build package.al 2>&1); bad_rc=$?
  if [ "$bad_rc" = 1 ] \
    && printf '%s' "$bad_out" | grep -qF 'alatyr: build: codegen: package entry does not resolve to exactly one package declaration at line 11 in package' \
    && [ ! -e "$bad/target" ]; then
    echo "ok   tool12_entry_resolution: unresolved entry fails located Codegen before tools and artifacts"
  else
    echo "FAIL tool12_entry_resolution: build rc=$bad_rc out=$bad_out or target/ exists"; fail=1
  fi

  good_out=$(cd "$good" && "$CC" check package.al 2>&1); good_rc=$?
  if [ "$good_rc" = 0 ] && [ -z "$good_out" ] && [ ! -e "$good/target" ]; then
    echo "ok   tool12_entry_resolution: exact-export control check 0 with no artifact"
  else
    echo "FAIL tool12_entry_resolution: control check rc=$good_rc out=$good_out"; fail=1
  fi

  good_out=$(cd "$good" && "$CC" run package.al 2>&1); good_rc=$?
  if [ "$good_rc" = 42 ] && [ -z "$good_out" ]; then
    echo "ok   tool12_entry_resolution: exact-export control run 42"
  else
    echo "FAIL tool12_entry_resolution: control run rc=$good_rc out=$good_out"; fail=1
  fi

  rm -rf "$good/target"
  good_out=$(cd "$good" && "$CC" build package.al 2>&1); good_rc=$?
  artifact="$good/target/debug/tool12-entry-exact"
  if [ "$good_rc" = 0 ] && [ -x "$artifact" ]; then
    "$artifact" >/dev/null 2>&1; artifact_rc=$?
    syms=$(nm "$artifact" 2>/dev/null)
    if [ "$artifact_rc" = 42 ] && printf '%s\n' "$syms" | grep -qE ' [Tt] tool12_exact_entry$'; then
      echo "ok   tool12_entry_resolution: built exact-export control runs 42 and exports the selected symbol"
    else
      echo "FAIL tool12_entry_resolution: artifact rc=$artifact_rc or exact export missing"; fail=1
    fi
  else
    echo "FAIL tool12_entry_resolution: control build rc=$good_rc out=$good_out or artifact missing"; fail=1
  fi
  rm -rf "$bad/target" "$good/target"
}

# TOOL-15 / MOD-14 — the package manifest's private Package handle is visible only to the
# consuming package.  Keep this registration package-shaped: check, run and build all go through
# the same manifest path, while the negative rows compare the exact Config/Semantic diagnostics on
# both front-end surfaces.  The dependency fixture deliberately uses `name = "d"` with no alias;
# the dependency's `d__math` module must not inherit the root package's `app` binding.
run_tool15_manifest_handle() {
  local root="$ROOT/test/package/tool15_manifest_handle"
  local vis="$root/visibility"
  local dep="$root/dependency"
  local pub="$root/pub"
  local collision="$root/collision"
  local check_out build_out want check_rc build_rc run_rc artifact_rc nm_out nm_rc

  for p in "$vis" "$dep" "$pub" "$collision"; do
    if [ ! -f "$p/package.al" ]; then
      echo "FAIL tool15_manifest_handle: no $p/package.al"
      fail=1
    fi
    rm -rf "$p/target"
  done

  # MOD-14 shape is part of the registration contract: the local namespace is the dependency name.
  if grep -qF 'Dependency(name = "d", source = DepSource.Path("../dependency_dep"))' "$dep/package.al" \
    && ! grep -qE 'Dependency\([^)]*alias[[:space:]]*=' "$dep/package.al" \
    && grep -qF 'app.version' "$root/dependency_dep/src/math.al"; then
    echo "ok   tool15_dependency_shape: name=d, no alias, dependency probes app"
  else
    echo "FAIL tool15_dependency_shape: expected name=d without alias and app probe"; fail=1
  fi

  # Positive package handle: check, manifest-driven run and build must agree on 5.  The artifact
  # symbol scan is deliberately broader than `T app`: no linker-visible app/app__ symbol is allowed.
  (cd "$vis" && "$CC" check package.al) >/dev/null 2>&1; check_rc=$?
  if [ "$check_rc" = 0 ]; then echo "ok   tool15_visibility: check rc 0"; else echo "FAIL tool15_visibility: check rc=$check_rc want 0"; fail=1; fi
  (cd "$vis" && "$CC" run package.al) >/dev/null 2>&1; run_rc=$?
  if [ "$run_rc" = 5 ]; then echo "ok   tool15_visibility: run rc 5"; else echo "FAIL tool15_visibility: run rc=$run_rc want 5"; fail=1; fi
  (cd "$vis" && "$CC" build package.al) >/dev/null 2>&1; build_rc=$?
  if [ "$build_rc" != 0 ]; then
    echo "FAIL tool15_visibility: build rc=$build_rc want 0"; fail=1
  else
    echo "ok   tool15_visibility: build rc 0"
  fi
  artifact="$vis/target/debug/tool15-manifest-visibility"
  if [ -x "$artifact" ]; then
    "$artifact" >/dev/null 2>&1; artifact_rc=$?
    if [ "$artifact_rc" = 5 ]; then echo "ok   tool15_visibility: artifact rc 5"; else echo "FAIL tool15_visibility: artifact rc=$artifact_rc want 5"; fail=1; fi
    nm_out=$(nm "$artifact" 2>&1); nm_rc=$?
    if [ "$nm_rc" = 0 ] && ! printf '%s\n' "$nm_out" | grep -qE '(^|[[:space:]])[A-Za-z][[:space:]]+app($|_)'; then
      echo "ok   tool15_visibility: no app linker symbol"
    else
      echo "FAIL tool15_visibility: app linker symbol present or nm failed"; fail=1
    fi
  else
    echo "FAIL tool15_visibility: no target/debug/tool15-manifest-visibility artifact"; fail=1
  fi
  rm -rf "$vis/target"

  # Dependency isolation: both commands must fail with the same located diagnostic from d__math.
  want='alatyr: check: invalid at line 1 in d__math'
  check_out=$(cd "$dep" && "$CC" check package.al 2>&1); check_rc=$?
  build_out=$(cd "$dep" && "$CC" build package.al 2>&1); build_rc=$?
  if [ "$check_rc" = 1 ] && [ "$build_rc" = 1 ] && [ "$check_out" = "$want" ] && [ "$build_out" = "$want" ]; then
    echo "ok   tool15_dependency: check/build rc 1, app unavailable in d__math"
  else
    echo "FAIL tool15_dependency: check rc=$check_rc build rc=$build_rc check='$check_out' build='$build_out'"; fail=1
  fi
  rm -rf "$dep/target"

  # A manifest Package handle is configuration and cannot be published.
  want='alatyr: config: manifest binding '\''app'\'' must be private; `pub` is not allowed on a Package handle in package.al'
  check_out=$(cd "$pub" && "$CC" check package.al 2>&1); check_rc=$?
  build_out=$(cd "$pub" && "$CC" build package.al 2>&1); build_rc=$?
  if [ "$check_rc" = 1 ] && [ "$build_rc" = 1 ] && [ "$check_out" = "$want" ] && [ "$build_out" = "$want" ]; then
    echo "ok   tool15_pub_handle: check/build Config reject"
  else
    echo "FAIL tool15_pub_handle: check rc=$check_rc build rc=$build_rc check='$check_out' build='$build_out'"; fail=1
  fi
  rm -rf "$pub/target"

  # A root child module cannot share the manifest binding's name.
  want='alatyr: check: semantic duplicate name: manifest declaration '\''mylib'\'' in package.al conflicts with child module src/mylib.al'
  check_out=$(cd "$collision" && "$CC" check package.al 2>&1); check_rc=$?
  build_out=$(cd "$collision" && "$CC" build package.al 2>&1); build_rc=$?
  if [ "$check_rc" = 1 ] && [ "$build_rc" = 1 ] && [ "$check_out" = "$want" ] && [ "$build_out" = "$want" ]; then
    echo "ok   tool15_collision: check/build Semantic reject"
  else
    echo "FAIL tool15_collision: check rc=$check_rc build rc=$build_rc check='$check_out' build='$build_out'"; fail=1
  fi
  rm -rf "$collision/target"
}

# Modules §3/§4 — the LIBRARY-mode symbol surface of a `pub` declaration, which `lower_attrs::decl_is_pub`
# gates. Build a static-lib package and pin the `nm` binding letter of each named symbol: an UPPERCASE
# letter is a global (linkable by a consumer), lowercase is local. Two spellings of `pub` used to read as
# non-`pub` and so emitted LOCAL symbols — `pub mut NAME` (the only spelling a mutable global has) and a
# declaration on the FIRST line of the FIRST module (the concatenated module buffer leaves no whitespace
# before its `pub`). Measured before the fix: `d api__COUNT`, and an EMPTY archive for the first-line case
# (a library's DCE roots are its `pub` fns, so the only public entry was not a root at all).
run_lib_symbols() { # package dir, archive stem, "LETTER symbol" ...
  d="$1"; stem="$2"; shift 2
  p="$ROOT/test/package/$d"
  [ -f "$p/package.al" ] || { echo "FAIL lib_symbols($d): no $p/package.al"; fail=1; return; }
  rm -rf "$p/target"
  (cd "$p" && "$CC" build package.al) >/dev/null 2>&1
  obj="$p/target/debug/$stem.o"
  if [ ! -f "$obj" ]; then
    echo "FAIL lib_symbols($d): build produced no object at target/debug/$stem.o"; fail=1; rm -rf "$p/target"; return
  fi
  syms=$(nm "$obj")
  for want in "$@"; do
    if printf '%s\n' "$syms" | grep -qE " $want\$"; then
      echo "ok   lib_symbols($d): $want"
    else
      echo "FAIL lib_symbols($d): want '$want', got: $(printf '%s\n' "$syms" | tr '\n' ' ')"; fail=1
    fi
  done
  rm -rf "$p/target"
}

# TOOL-14 — manifest selection is independent of the shell's current directory, and a bare file list
# is a complete synthesized package. Keep this focused block opt-in so the package gate can continue to
# run its broad historical matrix while the implementation lane iterates on the new CLI boundary.
run_tool14_manifest_selection() {
  tmp=$(mktemp -d)
  mkdir -p "$tmp/pkg/src/nested" "$tmp/bare" "$tmp/empty" "$tmp/explicit"
  cat > "$tmp/pkg/package.al" <<'EOF'
app := Package(version = "0.1.0", source_dir = "src", target_dir = "target",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf,
                    entry = "_start", output = "upward")])
EOF
  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/pkg/src/main.al"

  ( cd "$tmp/pkg/src/nested" && "$CC" build ) >"$tmp/up.out" 2>"$tmp/up.err"
  up_rc=$?
  if [ "$up_rc" = 0 ] && [ -x "$tmp/pkg/target/debug/upward" ]; then
    "$tmp/pkg/target/debug/upward" >/dev/null 2>&1
    up_run=$?
    if [ "$up_run" = 42 ]; then
      echo "ok   tool14_upward: nested cwd selected $tmp/pkg/package.al and built target/debug/upward"
    else
      echo "FAIL tool14_upward: artifact rc=$up_run want 42"
      fail=1
    fi
  else
    echo "FAIL tool14_upward: build rc=$up_rc, stderr=$(cat "$tmp/up.err")"
    fail=1
  fi

  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/bare/root.al"
  printf 'pub helper := fn() -> u64 { return 1 }\n' > "$tmp/bare/helper.al"
  ( cd "$tmp/bare" && "$CC" build root.al helper.al ) >"$tmp/bare.out" 2>"$tmp/bare.err"
  bare_rc=$?
  if [ "$bare_rc" = 0 ] && [ -x "$tmp/bare/target/debug/root" ] && [ ! -e "$tmp/bare/target/debug/a.out" ]; then
    "$tmp/bare/target/debug/root" >/dev/null 2>&1
    bare_run=$?
    if [ "$bare_run" = 42 ]; then
      echo "ok   tool14_bare: first file root/stem root, artifact target/debug/root"
    else
      echo "FAIL tool14_bare: artifact rc=$bare_run want 42"
      fail=1
    fi
  else
    echo "FAIL tool14_bare: build rc=$bare_rc, expected target/debug/root; stderr=$(cat "$tmp/bare.err")"
    fail=1
  fi

  cp "$tmp/pkg/package.al" "$tmp/explicit/package.al"
  mkdir -p "$tmp/explicit/src"
  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/explicit/src/main.al"
  ( cd "$tmp/empty" && "$CC" build --manifest "$tmp/explicit/package.al" ) >"$tmp/explicit.out" 2>"$tmp/explicit.err"
  explicit_rc=$?
  if [ "$explicit_rc" = 0 ] && [ -x "$tmp/explicit/target/debug/upward" ]; then
    echo "ok   tool14_manifest: --manifest selected the explicit package"
  else
    echo "FAIL tool14_manifest: rc=$explicit_rc, stderr=$(cat "$tmp/explicit.err")"
    fail=1
  fi

  ## TOOL-13/14 layout seam: manifest target_dir is package-relative, --target-dir is caller-owned,
  ## and both retain the selected profile directory. The zero-Package root uses its file stem.
  mkdir -p "$tmp/layout/src" "$tmp/zero" "$tmp/override/src" "$tmp/exact/src" "$tmp/exact/custom"
  cat > "$tmp/layout/package.al" <<'EOF'
app := Package(source_dir = "src", target_dir = "out",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf,
                    entry = "_start", output = "prog")])
EOF
  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/layout/src/main.al"
  ( cd "$tmp/layout" && "$CC" build package.al ) >"$tmp/layout.out" 2>"$tmp/layout.err"
  layout_rc=$?
  if [ "$layout_rc" = 0 ] && [ -x "$tmp/layout/out/debug/prog" ] && [ ! -e "$tmp/layout/out/prog" ]; then
    echo "ok   tool14_layout: manifest target_dir=out -> out/debug/prog"
  else
    echo "FAIL tool14_layout: rc=$layout_rc, expected out/debug/prog; stderr=$(cat "$tmp/layout.err")"
    fail=1
  fi
  ( cd "$tmp/layout" && "$CC" build --target-dir relocated package.al ) >"$tmp/relocated.out" 2>"$tmp/relocated.err"
  relocated_rc=$?
  if [ "$relocated_rc" = 0 ] && [ -x "$tmp/layout/relocated/debug/prog" ]; then
    echo "ok   tool14_target_dir: --target-dir relocated -> relocated/debug/prog"
  else
    echo "FAIL tool14_target_dir: rc=$relocated_rc, expected relocated/debug/prog; stderr=$(cat "$tmp/relocated.err")"
    fail=1
  fi
  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/zero/package.al"
  ( cd "$tmp/zero" && "$CC" build package.al ) >"$tmp/zero.out" 2>"$tmp/zero.err"
  zero_rc=$?
  if [ "$zero_rc" = 0 ] && [ -x "$tmp/zero/target/debug/package" ] && [ ! -e "$tmp/zero/target/debug/a.out" ]; then
    echo "ok   tool14_zero_package: root stem package -> target/debug/package"
  else
    echo "FAIL tool14_zero_package: rc=$zero_rc, expected target/debug/package; stderr=$(cat "$tmp/zero.err")"
    fail=1
  fi
  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/override/src/main.al"
  cat > "$tmp/override/package.al" <<'EOF'
app := Package(source_dir = "src", target_dir = "out",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf,
                    entry = "_start", output = "prog")])
EOF
  ( cd "$tmp/override" && "$CC" build --release package.al ) >"$tmp/override.out" 2>"$tmp/override.err"
  override_rc=$?
  if [ "$override_rc" = 0 ] && [ -x "$tmp/override/out/release/prog" ]; then
    echo "ok   tool14_bare_profile: --release -> out/release/prog"
  else
    echo "FAIL tool14_bare_profile: rc=$override_rc, expected out/release/prog; stderr=$(cat "$tmp/override.err")"
    fail=1
  fi
  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/exact/src/main.al"
  cat > "$tmp/exact/package.al" <<'EOF'
app := Package(source_dir = "src", target_dir = "out",
  targets = [Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf,
                    entry = "_start", output = "prog")])
EOF
  exact="$tmp/exact/custom/result"
  ( cd "$tmp/exact" && "$CC" -o "$exact" package.al ) >"$tmp/exact.out" 2>"$tmp/exact.err"
  exact_rc=$?
  if [ "$exact_rc" = 0 ] && [ -x "$exact" ] && [ -s "$exact.s" ] && [ -s "$exact.o" ] \
    && [ ! -e "$tmp/exact/out" ] && [ ! -e "$tmp/exact/target" ] && [ ! -e "$exact.debug" ]; then
    echo "ok   tool14_exact_o: -o remains exact and bypasses target layout"
  else
    echo "FAIL tool14_exact_o: rc=$exact_rc, expected exact path only; stderr=$(cat "$tmp/exact.err")"
    fail=1
  fi

  printf 'main := fn() -> u64 { return 42 }\n' > "$tmp/empty/root.al"
  ( cd "$tmp/empty" && "$CC" build --manifest "$tmp/explicit/package.al" root.al ) >"$tmp/conflict.out" 2>"$tmp/conflict.err"
  conflict_rc=$?
  if [ "$conflict_rc" != 0 ] && grep -qF 'config:' "$tmp/conflict.err" && grep -qF -- '--manifest' "$tmp/conflict.err"; then
    echo "ok   tool14_conflict: file list plus --manifest is a Config diagnostic"
  else
    echo "FAIL tool14_conflict: rc=$conflict_rc, stderr=$(cat "$tmp/conflict.err")"
    fail=1
  fi

  for cmd in run build check test; do
    ( cd "$tmp/empty" && "$CC" "$cmd" ) >"$tmp/noinput-$cmd.out" 2>"$tmp/noinput-$cmd.err"
    noinput_rc=$?
    if [ "$noinput_rc" = 40 ] && grep -qF 'config: no discoverable package.al and no file list' "$tmp/noinput-$cmd.err"; then
      echo "ok   tool14_noinput($cmd): rc 40 Config diagnostic"
    else
      echo "FAIL tool14_noinput($cmd): rc=$noinput_rc, stderr=$(cat "$tmp/noinput-$cmd.err")"
      fail=1
    fi
  done

  ## The corpus's x86 row uses `-o <artifact> package.al`, not `build package.al`. A lone manifest must
  ## keep the package module closure on that legacy output surface too, or every package.al row turns
  ## into a single inert manifest and dies at ld with an undefined `main`.
  o_tmp=$(mktemp -d)
  ( cd "$ROOT" && "$CC" -o "$o_tmp/module-fn-ancestor" test/package/module_fn_ancestor/package.al ) >"$tmp/o-manifest.out" 2>"$tmp/o-manifest.err"
  o_rc=$?
  o_run=127
  if [ "$o_rc" = 0 ] && [ -x "$o_tmp/module-fn-ancestor" ]; then
    "$o_tmp/module-fn-ancestor" >/dev/null 2>&1
    o_run=$?
  fi
  if [ "$o_rc" = 0 ] && [ "$o_run" = 42 ]; then
    echo "ok   tool14_o_manifest: -o package.al keeps package modules and runs 42"
  else
    echo "FAIL tool14_o_manifest: compile rc=$o_rc run=$o_run, stderr=$(cat "$tmp/o-manifest.err")"
    fail=1
  fi
  rm -rf "$o_tmp"
  rm -rf "$tmp"
}

if [ "${CROSS_TARGET_ONLY:-0}" = 1 ]; then
  run_cross_target_test
  exit "$fail"
fi

if [ "${TOOL14_ONLY:-0}" = 1 ]; then
  run_tool14_manifest_selection
  exit "$fail"
fi

# Tooling §4: build, run, test, and check all accept the same profile selectors.
# `check` proves argument routing. `run` additionally proves the selected profile's
# manifest flag reaches `build.*` before lowering.
run_noarg_help
run_new_scaffold
run_zero_tests
run_cross_target_test
run_expect profile_check_named 0 check --profile release package.al
run_expect profile_check_release 0 check --release package.al
run_expect profile_run_debug 7 run package.al
run_expect profile_run_named 42 run --profile release package.al
run_expect profile_run_release 42 run --release package.al
run_profile_program_args
run_expect profile_test_parallel 0 test -j2 --profile release package.al
run_path_dep dep_declared main__main
run_path_dep dep_alias_use d__math__answer
run_dep_config_diag
run_manifest_structural_config
run_dep_cycle_diag
run_dep_spelling_identity
run_tool12_entry_resolution
run_check_build_parity
run_test_entry_file tool7_entry_start "program with its own entry"
run_test_entry_file tool7_entry_main_reached "a test reaches main"
run_manifestless_cleanup
run_test_entry_pkg tool7_entry tool7-entry _start "package entry is not linked into the test artifact"
run_test_entry_pkg tool7_entry_named tool7-entry-named launch "named entry is not linked into the test artifact"
run_test_entry_pkg test_entry_exclusion test-entry-exclusion _start "package _start is excluded while main and export remain"

# Modules §3 — a package whose EMITTED CALLS are the assertion, not just the exit code. `run_pkg_exit`
# checks the answer; this also pins WHICH function was called, because the whole defect class here is
# a call that lands on a same-named function in a module the program may not name. A `+sym` argument
# must appear as `call <sym>` in the emitted assembly; a `-sym` argument must not appear in it at all.
# Without the `-` half a fixture passes for the wrong reason the moment the decoy body is edited to
# agree with the real one (the pilot split's `decl_get` case was byte-invisible for exactly that
# reason). Kept x86_64-only, like the rest of the package fixtures.
run_pkg_callees() { # package dir, artifact stem, want-exit, [+want-callee | -forbidden-symbol ...]
  d="$1"; outnm="$2"; want="$3"; shift 3
  p="$ROOT/test/package/$d"
  [ -f "$p/package.al" ] || { echo "FAIL pkg_callees($d): no $p/package.al"; fail=1; return; }
  rm -rf "$p/target"
  (cd "$p" && "$CC" check package.al) >/dev/null 2>&1; got=$?
  if [ "$got" = 0 ]; then echo "ok   pkg_callees($d): check 0"; else echo "FAIL pkg_callees($d): check rc $got want 0"; fail=1; fi
  (cd "$p" && "$CC" run package.al) >/dev/null 2>&1; got=$?
  if [ "$got" = "$want" ]; then echo "ok   pkg_callees($d): run $want"; else echo "FAIL pkg_callees($d): run rc $got want $want"; fail=1; fi
  rm -rf "$p/target"
  (cd "$p" && "$CC" build package.al) >/dev/null 2>&1
  exe="$p/target/debug/$outnm"
  if [ -x "$exe" ]; then
    "$exe" >/dev/null 2>&1; got=$?
    if [ "$got" = "$want" ]; then echo "ok   pkg_callees($d): artifact $want"; else echo "FAIL pkg_callees($d): artifact rc $got want $want"; fail=1; fi
  else
    echo "FAIL pkg_callees($d): build produced no artifact at target/debug/$outnm"; fail=1
  fi
  gas=$(cat "$p"/target/debug/*.s 2>/dev/null)
  if [ -z "$gas" ]; then echo "FAIL pkg_callees($d): no emitted assembly under target/"; fail=1; fi
  for a in "$@"; do
    sym="${a#?}"
    case "$a" in
      +*)
        if printf '%s\n' "$gas" | grep -qE "^[[:space:]]*call[[:space:]]+$sym\$"; then
          echo "ok   pkg_callees($d): call $sym"
        else
          echo "FAIL pkg_callees($d): expected 'call $sym' in the emitted assembly"; fail=1
        fi ;;
      -*)
        if printf '%s\n' "$gas" | grep -qE "(^|[^A-Za-z0-9_])$sym([^A-Za-z0-9_]|\$)"; then
          echo "FAIL pkg_callees($d): the forbidden symbol $sym is present in the emitted assembly"; fail=1
        else
          echo "ok   pkg_callees($d): $sym absent"
        fi ;;
      *) echo "FAIL pkg_callees($d): argument '$a' needs a + or - prefix"; fail=1 ;;
    esac
  done
  rm -rf "$p/target"
}

run_pkg_check_build_located module_global_sibling_reject          2 other
run_pkg_check_build_located module_global_sibling_qual_reject     2 other
run_pkg_check_build_located module_global_sibling_write_reject    2 other
run_pkg_check_build_located module_global_sibling_arr_reject      2 other
run_pkg_check_build_located module_global_bare_nonancestor_reject 2 mod__child
## Modules §3 for EVERY declaration kind — a function, a type (struct and enum), a constant, an
## import/alias binding, a listed member projection (§4.1.1) and a signature-position type. Each of
## these compiled and RAN before 2026-08-20 (the check covered module GLOBALS only), silently
## ignoring the declaration's privacy; the constant case was the one already covered, by the
## module-global resolver, and keeps ITS diagnostic.
run_pkg_check_build_located visibility_fn_reject         4 main
run_pkg_check_build_located visibility_type_reject       3 main
run_pkg_check_build_located visibility_enum_reject       3 main
run_pkg_check_build_located visibility_alias_reject      4 main
run_pkg_check_build_located visibility_projection_reject 4 main
run_pkg_check_build_located visibility_sig_type_reject   5 main
run_pkg_check_build_located visibility_const_reject      3 main
## Modules §4.3 — a re-export may name only `pub` items, so a DESCENDANT may READ its ancestor's
## private helper (legal, §3) but may not `pub`-bind it upward.
run_pkg_check_build_located visibility_reexport_reject 5 geo__child
## The positive half: every legal cross-module spelling the compiler supports still builds and runs.
## 55 = 7 (pub fn by path) + 10 (pub constant) + 3 (pub fn over a pub struct) + 6 (cross-module
## generic) + 2 (pub fn over a pub enum) + 11 (a DESCENDANT reading its ancestor's private fn,
## constant and type) + 7 (projected pub fn) + 7 (projected pub struct) + 2 (projected pub enum).
run_pkg_exit visibility_legal visibility-legal 55 "T geo__answer" "T geo__child__from_ancestor"
## `lower_attrs::decl_is_pub` — the two spellings it used to miss, pinned on the surface it gates.
run_lib_symbols visibility_pub_mut_lib       libvisibility-pub-mut.a       "D api__COUNT" "d api__PRIVATE_COUNT" "T api__bump"
run_lib_symbols visibility_pub_firstline_lib libvisibility-pub-firstline.a "T api__first_line_api" "t api__helper"
run_pkg_exit module_global_ancestor module-global-ancestor 42 "D geo__COUNT" "D geo__TAB" "D geo__MSG" "D geo__QCOUNT" "D geo__QTAB"
run_pkg_exit module_global_qualified module-global-qualified 42 "D geo__G" "D geo__TAB" "D geo__MSG"
run_pkg_exit module_global_shadow module-global-shadow 42 "D geo__G" "D geo__child__G"

## Modules §3 for a BARE CALL — the callee counterpart of the module-global family above, and the
## defect the pilot file-split ran into head-first. `mod_head_matches` matched only the calling
## module (or a last-segment lib path), never the ANCESTOR CHAIN, so `callee_decl_idx`'s fallback took
## the FIRST same-named declaration in declaration order: an unrelated module's non-`pub` duplicate,
## which §3 makes unnameable from there. Measured on the frozen seed before the fix:
## `module_fn_ancestor` returned 12 (`call aother__helper`), `module_fn_shadow` 32
## (`call aother__bump`), and both reject fixtures returned 23 (`call aone__helper`) instead of
## rejecting. The `-` assertions are what make these fixtures loud: a decoy call is a wrong VALUE
## today only because the decoy bodies DISAGREE, and equal bodies made the pilot's own case
## byte-invisible to the fixpoint, the corpus manifest, e2e and all three sweeps alike.
run_pkg_callees module_fn_ancestor module-fn-ancestor 42 +geo__helper +geo__gid__u64 -aother__helper -aother__gid
run_pkg_callees module_fn_shadow   module-fn-shadow   42 +geo__child__helper +geo__bump -aother__helper -aother__bump
run_pkg_check_build_located module_fn_sibling_reject   1 geo__child
run_pkg_check_build_located module_fn_ambiguous_reject 1 caller

## Modules §3 + Types §4.1 for a bare TYPE NAME — the TYPE half of the same family, and the one that
## still blocked the file split. `lower_layout::struct_decl_of`/`enum_decl_of` took NO naming module at
## all and settled same-named candidates by DECLARATION ORDER (LAST wins — the opposite tie-break of
## the callee fallback, which was FIRST-wins), so a child's `Box.size()` sized a SIBLING's struct.
## Measured on the frozen seed before the fix: `module_type_ancestor` returned 7 (both the child and
## the grandchild sized `zother`s wider types), `module_type_shadow` 90 (46 + 44 instead of 22 + 20),
## and both reject fixtures BUILT and RAN — 50 and 58 — instead of rejecting. Each fixture brackets
## `geo.al` with a decoy sorting BEFORE it and one sorting AFTER, because the shapes in this family do
## not share a tie-break: the bare type resolver was LAST-wins, while the parser's struct field-order
## table and the `@require`/brand scan were FIRST-wins.
run_pkg_exit   module_type_ancestor module-type-ancestor 42
run_pkg_exit   module_type_shadow   module-type-shadow   42
run_pkg_check_build_located module_type_sibling_reject       1 geo__child
run_pkg_check_build_located module_type_enum_ambiguous_reject 1 user

run_tool15_manifest_handle

# The gate-of-the-gate. `scripts/callee_module_check.sh` is the ONLY check that can see a call bound to
# an unrelated module's same-named duplicate, so a silently vacuous version of it (a parser change, a
# module-name convention change) would take the whole class of defects back into the dark. Drive it
# over a synthetic declaration tree and a synthetic assembly: once with the WRONG callee (it must
# report a VIOLATION and exit nonzero) and once with the right one (it must pass).
run_callee_gate_selftest() {
  t=$(mktemp -d)
  mkdir -p "$t/src/geo"
  printf 'helper := fn() -> u64 { return 0 }\n' > "$t/src/aother.al"
  printf 'helper := fn() -> u64 { return 20 }\n' > "$t/src/geo.al"
  printf 'pub run := fn() -> u64 { return helper() + 22 }\n' > "$t/src/geo/child.al"
  printf 'geo__child__run:\n  call aother__helper\n  ret\n' > "$t/bad.s"
  printf 'geo__child__run:\n  call geo__helper\n  ret\n' > "$t/good.s"
  out=$(bash "$ROOT/scripts/callee_module_check.sh" "$t/bad.s" "$t/src" 2>&1); rc=$?
  case "$rc:$out" in
    0:*) echo "FAIL callee_gate_selftest: the gate ACCEPTED a call to an unrelated module's duplicate"; fail=1 ;;
    *VIOLATION*) echo "ok   callee_gate_selftest: reports the wrong-module callee" ;;
    *) echo "FAIL callee_gate_selftest: rc=$rc but no VIOLATION line: $out"; fail=1 ;;
  esac
  out=$(bash "$ROOT/scripts/callee_module_check.sh" "$t/good.s" "$t/src" 2>&1); rc=$?
  if [ "$rc" = 0 ]; then echo "ok   callee_gate_selftest: accepts the ancestor's declaration"; else echo "FAIL callee_gate_selftest: rejected a correct call: $out"; fail=1; fi
  rm -rf "$t"
}

## The whole-program EMITTED-CALLEE invariant over the compiler's OWN assembly (see the script's
## header): for every emitted `call`, the callee's module must be the NEAREST module on the calling
## module's §3 chain that declares that name. This is the gate none of the existing ones could be:
## fixpoint, the corpus manifest, e2e and the sweeps were all green while `driver.al`'s bare `streq`
## emitted `call aarch64__streq` (a different body), `riscv64.al`'s bare `param_find` emitted
## `call aarch64__param_find`, and `lower.al`'s bare `node_ptr` emitted `call wat__node_ptr__*`
## despite `(… node_ptr …) := lower_ctx` saying otherwise.
run_callee_gate_selftest
if [ -s "$ROOT/target/gas1.s" ]; then
  if bash "$ROOT/scripts/callee_module_check.sh" "$ROOT/target/gas1.s" >"$ROOT/target/callee_check.log" 2>&1; then
    echo "ok   callee_module_check: $(grep -c '^NONPUB' "$ROOT/target/callee_check.log") reported §3 non-pub reach(es), 0 violations"
  else
    echo "FAIL callee_module_check:"; grep -E '^(VIOLATION|callee_module_check)' "$ROOT/target/callee_check.log" | head -20; fail=1
  fi
else
  echo "SKIP callee_module_check: no target/gas1.s (run scripts/fixpoint.sh first)"
fi

# The gate-of-the-gate for the TYPE invariant. `scripts/type_module_check.sh` is the only check that can
# see an emitted type identity bound to an unrelated module's same-named declaration, so a silently
# vacuous version of it takes that whole class back into the dark — and it very nearly WAS vacuous once
# already: registering only the modules that DECLARE a type made it inspect 18 of the tree's 25
# monomorphized instances, because most instances live in modules that declare no type at all. So the
# self-test asserts BOTH verdicts AND a minimum instance count on the synthetic tree.
run_type_gate_selftest() {
  t=$(mktemp -d)
  # BAD tree: `Box` declared in TWO unrelated siblings, and a generic `Cell` in `holder` — a module
  # that declares no type at all, so the scan must register EVERY module to see its instance.
  mkdir -p "$t/bad/geo"
  printf 'Box := struct { a : u64 }\n' > "$t/bad/aone.al"
  printf 'Box := struct { a : u64, b : u64 }\n' > "$t/bad/atwo.al"
  printf 'pub Cell := fn(T : type) -> type { return struct { v : T } }\n' > "$t/bad/holder.al"
  printf 'pub run := fn() -> u64 { return 0 }\n' > "$t/bad/geo/child.al"
  printf 'geo__child__run:\n  call holder__Cell__Box\n  ret\nholder__Cell__Box:\n  ret\n' > "$t/bad.s"
  # GOOD tree: the same instance over a type exactly ONE module declares (the unique-declaration
  # leniency), and that declaration is `pub` — nothing for §3 to object to.
  mkdir -p "$t/good/geo"
  printf 'pub Box := struct { a : u64 }\n' > "$t/good/aone.al"
  printf 'pub Cell := fn(T : type) -> type { return struct { v : T } }\n' > "$t/good/holder.al"
  printf 'pub run := fn() -> u64 { return 0 }\n' > "$t/good/geo/child.al"
  printf 'geo__child__run:\n  call holder__Cell__Box\n  ret\nholder__Cell__Box:\n  ret\n' > "$t/good.s"
  out=$(bash "$ROOT/scripts/type_module_check.sh" "$t/bad.s" "$t/bad" 2>&1); rc=$?
  case "$rc:$out" in
    0:*) echo "FAIL type_gate_selftest: the gate ACCEPTED an ambiguous type binding"; fail=1 ;;
    *VIOLATION*) echo "ok   type_gate_selftest: reports the ambiguous type binding" ;;
    *) echo "FAIL type_gate_selftest: rc=$rc but no VIOLATION line: $out"; fail=1 ;;
  esac
  out=$(bash "$ROOT/scripts/type_module_check.sh" "$t/good.s" "$t/good" 2>&1); rc=$?
  if [ "$rc" = 0 ]; then echo "ok   type_gate_selftest: accepts the unique declaration"; else echo "FAIL type_gate_selftest: rejected a sound instance: $out"; fail=1; fi
  # The THIRD verdict: two `pub` candidates. The resolver keeps the tail-only answer there (a lost
  # qualified head may legitimately have meant either), so the gate must REPORT, not fail — and it
  # must not report nothing, which is how this class would go dark.
  mkdir -p "$t/pubamb/geo"
  printf 'pub Box := struct { a : u64 }\n' > "$t/pubamb/aone.al"
  printf 'pub Box := struct { a : u64, b : u64 }\n' > "$t/pubamb/atwo.al"
  printf 'pub Cell := fn(T : type) -> type { return struct { v : T } }\n' > "$t/pubamb/holder.al"
  printf 'pub run := fn() -> u64 { return 0 }\n' > "$t/pubamb/geo/child.al"
  cp "$t/good.s" "$t/pubamb.s"
  out=$(bash "$ROOT/scripts/type_module_check.sh" "$t/pubamb.s" "$t/pubamb" 2>&1); rc=$?
  case "$rc:$out" in
    0:*AMBIGPUB*) echo "ok   type_gate_selftest: reports the tail-only pub ambiguity without failing" ;;
    *) echo "FAIL type_gate_selftest: pub-ambiguity verdict wrong (rc=$rc): $out"; fail=1 ;;
  esac
  # NOT VACUOUS: the accepting run must actually have inspected the instance it accepted.
  case "$out" in
    *"1 distinct monomorphized instance symbol(s) inspected"*) echo "ok   type_gate_selftest: the scan saw the instance (not vacuous)" ;;
    *) echo "FAIL type_gate_selftest: the scan inspected no instance — vacuous: $out"; fail=1 ;;
  esac
  rm -rf "$t"
}

## The whole-program EMITTED-TYPE invariant over the compiler's OWN assembly: every monomorphized
## instance symbol `<mod>__<generic>__<Targ>` must name a type declaration `<mod>` may see under
## Modules §3. On the tree this reports 25 instances and 0 violations BOTH before and after
## TYPE-ANCESTOR — `src/`s modules are all top-level siblings (there is no ancestor chain in the
## compiler's own tree at all), so unlike the CALLEE half there was no latent wrong binding here to
## find. The gate exists for what comes next: the file split creates exactly those chains.
run_type_gate_selftest
if [ -s "$ROOT/target/gas1.s" ]; then
  if bash "$ROOT/scripts/type_module_check.sh" "$ROOT/target/gas1.s" >"$ROOT/target/type_check.log" 2>&1; then
    echo "ok   type_module_check: $(grep -oE '^type_module_check: [0-9]+ distinct' "$ROOT/target/type_check.log" | head -1 | grep -oE '[0-9]+') monomorphized instance(s), $(grep -c '^NONPUB' "$ROOT/target/type_check.log") reported §3 non-pub reach(es), $(grep -c '^AMBIGPUB' "$ROOT/target/type_check.log") tail-only pub ambiguity/ambiguities, 0 violations"
  else
    echo "FAIL type_module_check:"; grep -E '^(VIOLATION|type_module_check)' "$ROOT/target/type_check.log" | head -20; fail=1
  fi
else
  echo "SKIP type_module_check: no target/gas1.s (run scripts/fixpoint.sh first)"
fi

exit "$fail"
