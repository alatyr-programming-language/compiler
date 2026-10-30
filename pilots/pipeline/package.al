## pilots/pipeline — worker threads hash input chunks handed out over a channel, with a result that
## does not depend on scheduling (#1125). See src/main.al for what it checks and its exit codes.
pipeline := Package(
  version = "0.1.0",
)
