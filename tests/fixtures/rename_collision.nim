import nim2ts

type
  Account* {.ts: "User".} = object
  User* {.ts.} = object
