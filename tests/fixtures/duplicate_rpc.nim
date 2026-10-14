import nim2ts

proc ping(a: int) {.rpc.} = discard
proc ping(a: string) {.rpc.} = discard
