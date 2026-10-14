import nim2ts

type
  Table* {.ts: "DbTable".} = object
    name*: string
  Schema* {.ts.} = object
    tables*: seq[Table]
