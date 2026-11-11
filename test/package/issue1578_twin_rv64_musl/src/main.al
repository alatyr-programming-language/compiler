## #1578 — the program is trivial on purpose: the package's manifest is what the twin verbs judge.
main := fn() -> u64 {
  return 42
}
## Compiled alone (the corpus walk), this file is a bare program: every backend publishes its own
## default machine model, and the program runs to 42.
## expect: run 42
