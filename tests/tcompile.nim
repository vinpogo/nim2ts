# Behavior that only shows across modules or declarations, on the
# fixtures in tests/fixtures/.

import std/[os, osproc, strutils, unittest]

let dir = currentSourcePath.parentDir

proc compiler(command, fixture: string): tuple[output: string, exitCode: int] =
  execCmdEx(getCurrentCompilerExe() & " " & command & " --hints:off --path:" &
    quoteShell(dir / ".." / "src") & " -d:nim2tsOut=" & quoteShell(getTempDir() / "nim2ts-fixture.ts") &
    " " & quoteShell(dir / "fixtures" / fixture))

proc checkError(fixture: string): string =
  let (output, code) = compiler("check", fixture)
  if code == 0:
    return "(no error)"
  output

test "dispatch reaches procs its caller does not import, and keeps foo apart from Foo":
  let (output, code) = compiler("r", "selective_import.nim")
  check code == 0
  check output.strip.splitLines == @["\"user 7\"", "\"foo\"", "\"Foo\"", "\"hidden\""]

test "an {.rpc.} proc declared after dispatch":
  check "comes after a dispatch call" in checkError("late_rpc.nim")

test "a {.ts.} type using a name of the RPC client":
  check "the RPC client declares 'Client'" in checkError("reserved_name.nim")

test "two {.rpc.} procs with the same name":
  check "an {.rpc.} proc named 'ping' already exists" in checkError("duplicate_rpc.nim")

test "two {.rpc.} procs whose names are the same Nim identifier":
  check "an {.rpc.} proc named 'foo_bar' already exists" in checkError("same_identifier.nim")

test "two {.ts.} types with the same TypeScript name":
  check "'Account' already uses the TypeScript name 'User'" in checkError("rename_collision.nim")

test "a TypeScript name that is not an identifier":
  check "'user-account' is not a TypeScript identifier" in checkError("bad_ts_name.nim")
