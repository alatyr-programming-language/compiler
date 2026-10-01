# Seed-forms planted programs

Each `<name>.al` here is the planted program of one row of `scripts/seed_forms.tsv`: a form the
frozen seed (`seed/alatyr`) miscompiles, checked by `scripts/seed_forms_check.sh` in the full gate.
The rationale and the retirement history are in `.agents/skills/alatyr-lane/strict_forms.md` §8.

The directory may hold no program: a promotion retires a row when the new seed handles its form,
and the registry then declares `# live-rows: 0`. This file keeps the directory in the tree, because
git does not record an empty one and the check requires the directory to exist.
