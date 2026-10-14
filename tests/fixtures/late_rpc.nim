import std/json
import nim2ts

proc early(): int {.rpc.} = 1
discard dispatch("early", %*{})
proc late(): int {.rpc.} = 2
