# Mistakes that only show across declarations: each fixture must fail
# `nim check` with the given message.

import std/[os, osproc, strutils, unittest]

proc checkError(fixture: string): string =
  let dir = currentSourcePath.parentDir
  let (output, code) = execCmdEx(getCurrentCompilerExe() & " check --hints:off --path:" &
    quoteShell(dir / ".." / "src") & " " & quoteShell(dir / "fixtures" / fixture))
  if code == 0:
    return "(no error)"
  output

test "an {.rpc.} proc declared after dispatch":
  check "comes after a dispatch call" in checkError("late_rpc.nim")

test "a {.ts.} type using a name of the RPC client":
  check "the RPC client declares 'Client'" in checkError("reserved_name.nim")

test "two {.rpc.} procs with the same name":
  check "an {.rpc.} proc named 'ping' already exists" in checkError("duplicate_rpc.nim")
