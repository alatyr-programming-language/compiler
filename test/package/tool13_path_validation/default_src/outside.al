## This module is deliberately outside the omitted source_dir default `src`. It must not enter the
## package's module graph; the exported symbol makes accidental root discovery observable in the e2e row.
@export("tool13_outside_default_probe") outside := fn() -> u64 {
  return 7
}
