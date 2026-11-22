- **The merge queue no longer stops at the IR coverage floors' follow commit (#1877).** `land.sh`'s
  main-provenance walk now accepts an integrator tail commit that changes only
  `scripts/ir_census.src.baseline` and `scripts/ir_census.targets.baseline`, as the integrator
  procedure requires after every landing that grows IR coverage; before, the next queue pass refused
  it as a commit that came through no pull request, and no PR could land.
