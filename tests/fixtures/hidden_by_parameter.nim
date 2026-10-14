import nim2ts

type
  Box*[DbRecord] {.ts.} = object
    item*: Record
  Record* {.ts: "DbRecord".} = object
    id*: int
