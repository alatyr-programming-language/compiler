- **The GitHub gate runs as four parallel parts with one verdict (#1568).** A `gate/**` push now
  runs `scripts/full.sh` once per part (`full.sh --parts`), each with its own fixpoint, and a
  `verdict` job aggregates them with `scripts/full_parts.sh`. The run log and the `gate-<sha>`
  artifact's `gate.log` still carry exactly one gate verdict line and one `xbackend diff:` line;
  a part prints `--- full part <part>: … ---`, which is not a verdict. Download `gate-<sha>` for the
  verdict and `gate-<sha>-<part>` for a part's per-stage logs. The omen merge queue and a plain
  `full.sh` run are unchanged. No compiler behaviour changes.
