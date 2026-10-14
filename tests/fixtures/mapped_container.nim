import nim2ts

type Table*[V] {.ts.} = object
  value*: V
