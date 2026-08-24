## A grandchild: the same globals reached two steps up, spelled with the QUALIFIED path.
pub run := fn() -> u64 {
  geo::QCOUNT = 8
  geo::QCOUNT += 1
  geo::QTAB[3] = 8
  return geo::QCOUNT + geo::QTAB[3]
}
