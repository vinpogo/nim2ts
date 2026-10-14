import nim2ts

proc getUser*(id: int): string {.rpc.} = "user " & $id
proc foo*(): string {.rpc.} = "foo"
proc Foo*(): string {.rpc.} = "Foo"
proc hidden(): string {.rpc.} = "hidden"
