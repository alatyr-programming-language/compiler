- The shared IR builds a read, a write or a whole copy through a pointer to a struct with an enum
  field, a niche-folded `Option(ptr(T))` field, a nested struct of word-wide fields or a fixed array of
  words, and passes such a struct by value. Each child sits at the place `lower_layout::field_byte_place`
  gives it, the image x86_64's legacy emitter reads and writes (#1786). The twins keep such functions
  on their legacy emitters. A child the image does not cover stays refused under its own cause: a
  sub-word scalar inside a nested aggregate (or a signed one in a by-value parameter), or an enum whose
  payload holds an aggregate.
