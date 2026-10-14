## Pure helpers that turn (untyped) Nim type AST into TypeScript source text.
##
## Nothing in here has side effects, so every proc can be tested in isolation
## from a `static:` block (see `tests/tconvert.nim`).
##
## Tip: to see what AST a piece of Nim code produces, run
## `dumpTree: <your code>` from `std/macros`.

import std/[macros, sequtils, strutils, tables]

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

type
  EnumValues* = Table[string, seq[tuple[member, value: string]]]
    ## Wire values per enum, in declaration order.

  Known* = object
    ## What the converter knows about other `{.ts.}` declarations, keyed by
    ## `nimIdentNormalize` of the Nim type name.
    enums*: EnumValues ## case objects label their branches with these
    names*: Table[string, string] ## the TypeScript name of each type

proc tsName*(known: Known, nimName: string): string =
  known.names.getOrDefault(nimIdentNormalize(nimName), nimName)

proc wrapUnion(tsType: string): string =
  ## `number | null` must become `(number | null)` before appending `[]`.
  if " | " in tsType: "(" & tsType & ")" else: tsType

proc toTsType*(n: NimNode, known = default(Known)): string =
  ## Maps a Nim type expression to a TypeScript type expression.
  ## This is the place to add new mappings.
  case n.kind
  of nnkIdent, nnkSym:
    case n.strVal
    of "string", "char":
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
      # A custom type: emitted by its TypeScript name. It must also be
      # annotated with `{.ts.}`, otherwise tsc reports an unknown type.
      result = known.tsName(n.strVal)
  of nnkBracketExpr:
    let head = identName(n[0])
    case head
    of "seq", "array":
      # `array[3, T]` carries the element type last.
      result = wrapUnion(toTsType(n[^1], known)) & "[]"
    of "Option":
      result = toTsType(n[1], known) & " | null"
    of "Table", "OrderedTable":
      if n[1].kind notin {nnkIdent, nnkSym} or n[1].strVal != "string":
        error("nim2ts: table keys must be strings, got " & n[1].repr, n)
      result = "Record<string, " & toTsType(n[2], known) & ">"
    else:
      # A generic custom type like `Page[User]` -> `Page<User>`.
      result = known.tsName(head) & "<" &
        n[1..^1].mapIt(toTsType(it, known)).join(", ") & ">"
  of nnkRefTy, nnkDistinctTy:
    result = toTsType(n[0], known)
  else:
    error("nim2ts: unsupported type (" & $n.kind & "): " & n.repr, n)

proc enumMembers*(enumTy: NimNode): seq[tuple[member, value: string]] =
  ## The members of an `nnkEnumTy` and the strings `$` gives for them,
  ## which is how `std/json` and jsony serialize enums. Two members with
  ## the same string could not be told apart on the wire, so they are an
  ## error.
  for field in enumTy[1..^1]: # enumTy[0] is always empty
    var member, value: string
    if field.kind == nnkEnumFieldDef:
      member = identName(field[0])
      let explicit = field[1]
      case explicit.kind
      of nnkStrLit..nnkTripleStrLit:
        value = explicit.strVal # `active = "ACTIVE"`
      of nnkTupleConstr, nnkPar:
        value = explicit[1].strVal # `active = (1, "ACTIVE")`
      else:
        value = member # `active = 1`: `$` still gives the name
    else:
      member = identName(field)
      value = member
    for seen in result:
      if seen.value == value:
        error("nim2ts: enum members '" & seen.member & "' and '" & member &
          "' share the wire value \"" & value & "\"", field)
    result.add (member, value)

proc hasPragma(field: NimNode, name: string): bool =
  if field.kind == nnkPragmaExpr:
    for p in field[1]:
      if p.kind in {nnkIdent, nnkSym} and p.strVal == name:
        return true

proc fieldsToTs(def: NimNode, known: Known): seq[string] =
  ## `a, b: int` is one nnkIdentDefs: (a, b, type, default value).
  let typ = def[^2]
  for field in def[0 ..< ^2]:
    if field.hasPragma("omitNone"):
      if typ.kind != nnkBracketExpr or identName(typ[0]) != "Option":
        error("nim2ts: {.omitNone.} needs an Option field: " & identName(field), field)
      result.add identName(field) & "?: " & toTsType(typ[1], known)
    else:
      result.add identName(field) & ": " & toTsType(typ, known)

proc branchFieldsToTs(body: NimNode, known: Known): seq[string] =
  case body.kind
  of nnkNilLit:
    discard # `of x: discard`
  of nnkIdentDefs:
    result = fieldsToTs(body, known)
  of nnkRecList:
    for def in body:
      result.add branchFieldsToTs(def, known)
  of nnkRecCase:
    error("nim2ts: nested case objects are not supported yet", body)
  else:
    error("nim2ts: unsupported object field (" & $body.kind & ")", body)

proc caseToTs(recCase: NimNode, known: Known): string =
  ## One `case` section becomes a union with one member per branch, each
  ## carrying the discriminator and the fields `std/json` emits for it.
  let discriminator = recCase[0]
  let tag = identName(discriminator[0])
  let tagType = identName(discriminator[1])
  var values: seq[tuple[member, value: string]]
  if tagType == "bool":
    values = @[("false", "false"), ("true", "true")]
  elif nimIdentNormalize(tagType) in known.enums:
    for (member, value) in known.enums[nimIdentNormalize(tagType)]:
      values.add (member, "\"" & value & "\"")
  else:
    error("nim2ts: the discriminator '" & tag & "' must be a bool or an " &
      "enum annotated with {.ts.} and declared before this type", discriminator)

  proc valueOf(label: NimNode): string =
    let member = identName(label)
    for v in values:
      if v.member == member:
        return v.value
    error("nim2ts: '" & member & "' is not a member of " & tagType, label)

  var covered: seq[string]
  var branches: seq[string]
  for branch in recCase[1..^1]:
    var labels: seq[string]
    case branch.kind
    of nnkOfBranch:
      for label in branch[0 ..< ^1]:
        if label.kind notin {nnkIdent, nnkSym}:
          error("nim2ts: only plain branch labels are supported, got " &
            label.repr, label)
        labels.add valueOf(label)
      covered.add labels
    of nnkElse:
      for v in values:
        if v.value notin covered:
          labels.add v.value
    else:
      error("nim2ts: unsupported case branch (" & $branch.kind & ")", branch)
    if labels.len == 0:
      continue
    let fields = @[tag & ": " & labels.join(" | ")] & branchFieldsToTs(branch[^1], known)
    branches.add "  | { " & fields.join("; ") & " }"
  result = "(\n" & branches.join("\n") & "\n)"

proc objectToTs(name, generics: string, objTy: NimNode, known: Known): string =
  ## `objTy` is an `nnkObjectTy`: (pragmas, inheritance, fields). The
  ## result is the intersection of its base, its shared fields and one
  ## union per `case` section.
  var base = ""
  let inherit = objTy[1]
  if inherit.kind == nnkOfInherit and identName(inherit[0]) != "RootObj":
    base = toTsType(inherit[0], known)

  var fields: seq[string]
  var unions: seq[string]
  let recList = objTy[2]
  if recList.kind == nnkRecList:
    for def in recList:
      case def.kind
      of nnkIdentDefs:
        fields.add fieldsToTs(def, known)
      of nnkRecCase:
        unions.add caseToTs(def, known)
      else:
        error("nim2ts: unsupported object field (" & $def.kind & ")", def)

  var parts: seq[string]
  if base.len > 0:
    parts.add base
  if fields.len > 0:
    parts.add "{\n" & fields.mapIt("  " & it & ";").join("\n") & "\n}"
  parts.add unions
  if parts.len == 0:
    parts.add "{}"
  result = "export type " & name & generics & " = " & parts.join(" & ") & ";"

proc enumToTs(name: string, enumTy: NimNode): string =
  ## Enums become a union of string literals.
  let members = enumMembers(enumTy).mapIt("\"" & it.value & "\"")
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

proc toTsDecl*(typeDef: NimNode, known = default(Known)): string =
  ## Turns one `nnkTypeDef` (name, generic params, definition) into a
  ## complete TypeScript declaration.
  typeDef.expectKind nnkTypeDef
  let name = known.tsName(identName(typeDef[0]))
  let generics = genericParams(typeDef[1])

  var rhs = typeDef[2]
  if rhs.kind == nnkRefTy and rhs[0].kind == nnkObjectTy:
    rhs = rhs[0] # `ref object` looks the same as `object` on the wire

  case rhs.kind
  of nnkObjectTy:
    result = objectToTs(name, generics, rhs, known)
  of nnkEnumTy:
    result = enumToTs(name, rhs)
  else:
    # Aliases (`Tags = seq[string]`) and distinct types (`UserId = distinct int`).
    result = "export type " & name & generics & " = " & toTsType(rhs, known) & ";"

type
  RpcParam* = object
    name*: string
    typ*: NimNode
    context*: bool ## `{.context.}`: passed by `dispatch`, not on the wire

  RpcSignature* = object
    name*: string
    params*: seq[RpcParam]
    returnType*: NimNode ## `nnkEmpty` for a proc without a result

proc rpcSignature*(procDef: NimNode): RpcSignature =
  ## Validates an `{.rpc.}` proc and extracts what both the TypeScript
  ## client and the dispatcher need.
  if procDef.kind != nnkProcDef:
    error("nim2ts: {.rpc.} goes on a proc", procDef)
  result.name = identName(procDef[0])
  if procDef[2].kind != nnkEmpty:
    error("nim2ts: an {.rpc.} proc cannot be generic", procDef[2])
  if procDef[6].kind == nnkEmpty:
    error("nim2ts: put {.rpc.} on the proc's implementation", procDef)
  let formal = procDef[3]
  result.returnType = formal[0]
  if result.returnType.kind in {nnkIdent, nnkSym} and result.returnType.strVal == "void":
    result.returnType = newEmptyNode()
  var contexts = 0
  for def in formal[1..^1]:
    let typ = def[^2]
    if typ.kind == nnkEmpty:
      error("nim2ts: {.rpc.} parameters need an explicit type", def)
    if def[^1].kind != nnkEmpty:
      error("nim2ts: {.rpc.} parameters cannot have defaults; use Option[T]", def)
    if typ.kind == nnkVarTy:
      error("nim2ts: {.rpc.} parameters cannot be var", def)
    for param in def[0 ..< ^2]:
      let context = param.hasPragma("context")
      if context:
        inc contexts
      result.params.add RpcParam(name: identName(param), typ: typ, context: context)
  if contexts > 1:
    error("nim2ts: an {.rpc.} proc takes at most one {.context.} parameter", formal)

proc hasInput(sig: RpcSignature): bool =
  sig.params.anyIt(not it.context)

proc procedureToTs*(sig: RpcSignature, known = default(Known)): string =
  ## One entry of the `Procedures` map. `Option` parameters may be left
  ## out, since reading accepts a missing key as `none`.
  var fields: seq[string]
  for p in sig.params:
    if p.context:
      continue
    if p.typ.kind == nnkBracketExpr and identName(p.typ[0]) == "Option":
      fields.add p.name & "?: " & toTsType(p.typ, known)
    else:
      fields.add p.name & ": " & toTsType(p.typ, known)
  let input =
    if fields.len == 0: "Record<string, never>"
    else: "{ " & fields.join("; ") & " }"
  let output =
    if sig.returnType.kind == nnkEmpty: "null"
    else: toTsType(sig.returnType, known)
  result = sig.name & ": { input: " & input & "; output: " & output & " };"

const rpcNames* = ["Procedures", "Transport", "createClient", "Client"]
  ## Declared by the generated client next to the user's types.

proc clientToTs*(procedures: seq[RpcSignature], known = default(Known)): string =
  ## The `Procedures` map, the `Transport` the app supplies and a client
  ## with one function per procedure.
  var calls: seq[string]
  for p in procedures:
    if p.hasInput:
      calls.add "  " & p.name & ": (input: Procedures[\"" & p.name &
        "\"][\"input\"]) => transport(\"" & p.name & "\", input),"
    else:
      calls.add "  " & p.name & ": () => transport(\"" & p.name & "\", {}),"
  result = "export type Procedures = {\n" &
    procedures.mapIt("  " & procedureToTs(it, known)).join("\n") & "\n};\n\n" &
    "export type Transport = <P extends keyof Procedures>(\n" &
    "  procedure: P,\n" &
    "  input: Procedures[P][\"input\"],\n" &
    ") => Promise<Procedures[P][\"output\"]>;\n\n" &
    "export const createClient = (transport: Transport) => ({\n" &
    calls.join("\n") & "\n});\n\n" &
    "export type Client = ReturnType<typeof createClient>;"
