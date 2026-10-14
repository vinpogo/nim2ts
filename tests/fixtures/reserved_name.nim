import nim2ts

type Client* {.ts.} = object
  name*: string

proc ping() {.rpc.} = discard
