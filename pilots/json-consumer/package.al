## pilots/json-consumer — a program that depends on the json library by path (#1125). It parses
## a fixed set of documents, checks what it reads, renders them back, and exits 0 when every
## check holds; otherwise it exits with the number of the first check that failed.
consumer := Package(
  version = "0.1.0",
  dependencies = [
    Dependency(name = "json", source = DepSource.Path("../json")),
  ],
)
