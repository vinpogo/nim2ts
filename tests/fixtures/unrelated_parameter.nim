import nim2ts

type
  Box*[DbRecord] {.ts.} = object
    x*: int
  Record* {.ts: "DbRecord".} = object
    id*: int
