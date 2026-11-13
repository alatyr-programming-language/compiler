- Merge queue: `ALATYR_QUEUE_RUNNER=github` gates a batch as speculative stacks (main+A, main+A+B,
  … up to `ALATYR_QUEUE_DEPTH`) on parallel `gate/**` runs and lands the deepest green prefix in one
  push of exactly the gated object; a red stack over a green one isolates its member, and a verdict
  counts only for the base its stack was composed on. omen stays the default (#1571).
