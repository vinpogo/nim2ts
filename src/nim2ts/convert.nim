## Pure helpers that turn (untyped) Nim type AST into TypeScript source text.
##
## Nothing in here has side effects, so every proc can be tested in isolation
## from a `static:` block (see `tests/tconvert.nim`).
##
## Tip: to see what AST a piece of Nim code produces, run
## `dumpTree: <your code>` from `std/macros`.

import std/[macros, sequtils, strutils]

proc identName*(n: NimNode): string =
  ## Returns the plain name of a type or field, stripping the export marker
  ## (`Foo*`), pragmas (`foo {.bar.}`) and backticks (`` `type` ``).
  case n.kind
  of nnkIdent, nnkSym:
    result = n.strVal
  of nnkPostfix:
    result = identName(n[1])
  of nnkPragmaExpr:
    result = identName(n[0])
  of nnkAccQuoted:
    for part in n:
      result.add identName(part)
  else:
    error("nim2ts: expected a name, got " & $n.kind, n)

proc wrapUnion(tsType: string): string =
  ## `number | null` must become `(number | null)` before appending `[]`.
  if " | " in tsType: "(" & tsType & ")" else: tsType

proc toTsType*(n: NimNode): string =
  ## Maps a Nim type expression to a TypeScript type expression.
  ## This is the place to add new mappings.
  case n.kind
  of nnkIdent, nnkSym:
    case n.strVal
    of "string", "char", "cstring":
      result = "string"
    of "int", "int8", "int16", "int32", "int64",
       "uint", "uint8", "uint16", "uint32", "uint64", "byte",
       "float", "float32", "float64", "Natural", "Positive":
      result = "number"
    of "bool":
      result = "boolean"
    of "JsonNode":
      result = "unknown"
    else:
      # A custom type: emitted by name. It must also be annotated with
      # `{.ts.}`, otherwise tsc will complain about an unknown type.
      result = n.strVal
  of nnkBracketExpr:
    let head = identName(n[0])
    case head
    of "seq", "array":
      # `array[3, T]` carries the element type last.
      result = wrapUnion(toTsType(n[^1])) & "[]"
    of "Option":
      result = toTsType(n[1]) & " | null"
    of "Table", "OrderedTable":
      result = "Record<" & toTsType(n[1]) & ", " & toTsType(n[2]) & ">"
    else:
      # A generic custom type like `Page[User]` -> `Page<User>`.
      result = head & "<" & n[1..^1].mapIt(toTsType(it)).join(", ") & ">"
  of nnkRefTy, nnkPtrTy, nnkDistinctTy:
    result = toTsType(n[0])
  else:
    error("nim2ts: unsupported type (" & $n.kind & "): " & n.repr, n)

proc objectToTs(name, generics: string, objTy: NimNode): string =
  ## `objTy` is an `nnkObjectTy`: (pragmas, inheritance, fields).
  result = "export interface " & name & generics

  let inherit = objTy[1]
  if inherit.kind == nnkOfInherit and identName(inherit[0]) != "RootObj":
    result.add " extends " & toTsType(inherit[0])

  var fields: seq[string]
  let recList = objTy[2]
  if recList.kind == nnkRecList:
    for def in recList:
      case def.kind
      of nnkIdentDefs:
        # `a, b: int` is one nnkIdentDefs: (a, b, type, default value).
        let tsType = toTsType(def[^2])
        for field in def[0 ..< ^2]:
          fields.add "  " & identName(field) & ": " & tsType & ";"
      of nnkRecCase:
        error("nim2ts: case objects are not supported yet", def)
      else:
        error("nim2ts: unsupported object field (" & $def.kind & ")", def)

  if fields.len == 0:
    result.add " {}"
  else:
    result.add " {\n" & fields.join("\n") & "\n}"

proc enumToTs(name: string, enumTy: NimNode): string =
  ## Enums become a union of string literals, which is how `std/json` and
  ## jsony serialize them (via `$`).
  var members: seq[string]
  for field in enumTy[1..^1]: # enumTy[0] is always empty
    var value: string
    if field.kind == nnkEnumFieldDef:
      let explicit = field[1]
      case explicit.kind
      of nnkStrLit..nnkTripleStrLit:
        value = explicit.strVal # `active = "ACTIVE"`
      of nnkTupleConstr, nnkPar:
        value = explicit[1].strVal # `active = (1, "ACTIVE")`
      else:
        value = identName(field[0]) # `active = 1`: `$` still gives the name
    else:
      value = identName(field)
    members.add "\"" & value & "\""
  result = "export type " & name & " = " & members.join(" | ") & ";"

proc genericParams(n: NimNode): string =
  ## `[T, U: SomeNumber]` -> `<T, U>`
  if n.kind != nnkGenericParams:
    return ""
  var names: seq[string]
  for def in n:
    for param in def[0 ..< ^2]:
      names.add identName(param)
  result = "<" & names.join(", ") & ">"

proc toTsDecl*(typeDef: NimNode): tuple[name, code: string] =
  ## Turns one `nnkTypeDef` (name, generic params, definition) into a
  ## complete TypeScript declaration.
  typeDef.expectKind nnkTypeDef
  let name = identName(typeDef[0])
  let generics = genericParams(typeDef[1])

  var rhs = typeDef[2]
  if rhs.kind == nnkRefTy and rhs[0].kind == nnkObjectTy:
    rhs = rhs[0] # `ref object` looks the same as `object` on the wire

  case rhs.kind
  of nnkObjectTy:
    result = (name, objectToTs(name, generics, rhs))
  of nnkEnumTy:
    result = (name, enumToTs(name, rhs))
  else:
    # Aliases (`Tags = seq[string]`) and distinct types (`UserId = distinct int`).
    result = (name, "export type " & name & generics & " = " & toTsType(rhs) & ";")
