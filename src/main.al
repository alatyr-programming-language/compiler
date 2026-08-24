## selfhost::main — the self-hosted Alatyr compiler's entry point (ROADMAP §1.0).
##
## The emitted `_start` calls `main__main`; this hands off to `cli::run_cli`, which reads the
## process arguments and either emits a program's GAS to stdout or BUILDS it (write `.s` + run
## `as`/`ld`). So the compiled binary IS the driveable compiler:
##   alatyr-self <file.al>...           — print the program's x86_64 GAS
##   alatyr-self -o <out> <file.al>...  — assemble+link the program into the executable <out>
##   alatyr-self run <file.al>...       — build to a temp executable, then fork/exec it
##   alatyr-self check <file.al>...     — type-check only (lex+parse+sema); exit 0 ok / 1 reject / 9 parse
##   alatyr-self test <file.al>...      — build a @test runner + run it; exit code = number of failing tests
## All on the lean `rt` runtime — the same code Stage1 and Stage2 run, so the tree compiles
## itself to the TOOL-1 fixpoint (see selfhost/fixpoint.sh).
pub main := fn() -> usize {
  mut a := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(a, 67108864)
  return cli::run_cli(a)
}
