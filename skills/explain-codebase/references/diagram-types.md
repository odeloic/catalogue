# Diagram types

Mermaid cheat sheet. Pick the type from the question shape. Put the chosen diagram source in the explain payload's `mermaid` field — the renderer draws it.

## sequenceDiagram — for flow / trace

Best when there are clearly named actors that talk to each other in order.

```
sequenceDiagram
  participant Client
  participant API as API Gateway
  participant Auth
  participant DB

  Client->>API: POST /login
  API->>Auth: validateCredentials(email, pw)
  Auth->>DB: SELECT user WHERE email=...
  DB-->>Auth: user row
  Auth-->>API: { ok: true, userId }
  API->>Auth: createSession(userId)
  Auth-->>API: sessionId
  API-->>Client: 200 + Set-Cookie
```

## stateDiagram-v2 — for lifecycle

Best when an entity has a small set of discrete states and explicit transitions.

```
stateDiagram-v2
  [*] --> Pending
  Pending --> Active: confirmEmail()
  Active --> Suspended: adminAction
  Suspended --> Active: reinstate()
  Active --> Deleted: user delete
  Deleted --> [*]
```

## classDiagram — for hierarchy / structure

Best when showing class inheritance, interfaces, or the shape of a few related types.

```
classDiagram
  class Session {
    +string id
    +string userId
    +Date expiresAt
    +refresh() void
    +invalidate() void
  }
  class User {
    +string id
    +string email
  }
  Session --> User : belongsTo
```

## flowchart TB — for structure / process

Top-to-bottom flowchart. Good for processes that branch but don't have distinct actors.

```
flowchart TB
  Start([Request received]) --> CheckAuth{Authenticated?}
  CheckAuth -- yes --> LoadUser[Load user from DB]
  CheckAuth -- no  --> Reject[401]
  LoadUser --> Handler[Run route handler]
  Handler --> Response([Send response])
```

## flowchart LR — for dependency / call graph

Left-to-right flowchart. Good when showing what calls what.

```
flowchart LR
  Login[loginHandler] --> Validate[validateCredentials]
  Login --> Create[createSession]
  Validate --> DB[(users table)]
  Create --> Redis[(session store)]
  Create --> Cookie[serializeCookie]
```

## erDiagram — for data model

Best when explaining tables / entities and their relationships.

```
erDiagram
  USER ||--o{ SESSION : has
  USER ||--o{ ORDER   : places
  ORDER ||--|{ ITEM   : contains

  USER {
    string id PK
    string email
  }
  SESSION {
    string id PK
    string user_id FK
    datetime expires_at
  }
```

## Mermaid tips

- Use double quotes inside node labels if the text has spaces or special chars: `A["Has space"]`.
- For `sequenceDiagram`, `participant Foo as Friendly Name` lets you alias.
- Keep node IDs short and lowercase; put readable text in the label.
- If mermaid fails to parse, surface the raw `.mmd` source for the user to fix — don't try to render an invalid diagram.
- Theme is set in the HTML template to follow the user's color-scheme preference.
