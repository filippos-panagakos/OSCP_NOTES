# NoSQL Injection — Complete Notes

## What Is NoSQL Injection

NoSQL injection is the same concept as SQLi but targeting NoSQL databases (MongoDB, CouchDB, etc). Instead of injecting SQL syntax, you inject MongoDB operators or JavaScript into queries that aren't properly sanitized. The two main types are syntax injection (breaking out of a query string) and operator injection (injecting MongoDB query operators as JSON objects).

## Two Injection Types

### Syntax Injection

The input gets concatenated into a server-side JavaScript query or MongoDB expression. You break out of the string context with a single quote, just like SQLi with a single quote in SQL.

Detection: inject a single quote `'` into the parameter. If the app errors or behaves differently, the query broke. Then test boolean control by injecting conditions like `' && 1 && 'x` (true) and `' && 0 && 'x` (false). Two different responses confirm you have a boolean oracle.

Typical injection point: URL parameters or any input that ends up in a MongoDB `$where` clause or JavaScript-evaluated query.

URL encoding matters: `&&` must be `%26%26` and `||` must be `%7c%7c` in URL parameters, otherwise the browser treats them as parameter separators. Python's `requests` library handles this automatically through the `params` dict.

Example extraction payload:
```
administrator' && this.password[0]=='a' || 'a'=='b
```
This checks if the first character of the password is `a`. The `|| 'a'=='b` at the end is a false condition that closes the query syntax cleanly without the trailing quote breaking things.

### Operator Injection

The input is parsed as JSON and passed to MongoDB as a query object. Instead of breaking out of a string, you replace a value with a MongoDB operator object.

Detection: change a string value like `"password":"test"` to `"password":{"$ne":""}`. If the response changes (login succeeds, different error message), the operator was evaluated.

Common operators for injection:
- `$ne` — not equal (bypasses exact match checks)
- `$regex` — pattern matching (used for character-by-character extraction)
- `$in` — match against a list of values
- `$exists` — check if a field exists
- `$where` — execute arbitrary JavaScript (most powerful)

Typical injection point: JSON bodies in POST requests, especially login endpoints.

If the endpoint doesn't accept JSON, you can try the bracket syntax in URL-encoded form data: `username[$ne]=&password[$ne]=`

## Building a Boolean Oracle

Every extraction technique needs an oracle — a way to distinguish true from false conditions. Three types exist, in order of preference:

### 1. Content-Based (Best)

The server returns different responses for true vs false conditions. Could be different error messages ("Account locked" vs "Invalid credentials"), different response lengths, different status codes (302 vs 200), or different page content.

How to identify: send a known-true and known-false condition and compare the responses.

### 2. Timing-Based (Fallback)

When responses are identical for both conditions, use time delays. Inject `sleep(5000)` or a busy-wait loop that only executes when the condition is true. If the response takes 5 seconds, the condition was true.

Payload examples:
```
admin'+function(x){var waitTill = new Date(new Date().getTime() + 5000);while((x.password[0]==="a") && waitTill > new Date()){};}(this)+'
```
```
admin'+function(x){if(x.password[0]==="a"){sleep(5000)};}(this)+'
```

Downside: much slower than content-based. Each true hit costs the full delay time.

### 3. No Oracle

If neither content nor timing produces a difference, the injection may not be exploitable for data extraction (though it might still work for authentication bypass with `$ne`).

## Data Extraction Methodology

### Step 1: Confirm Injection

Inject operators or syntax and observe different responses.

For operator injection: `{"password":{"$ne":""}}` — if behavior changes, operators are processed.

For syntax injection: `'` to break the query, then `' && 1 && 'x` vs `' && 0 && 'x` for boolean control.

### Step 2: Test for JavaScript Execution ($where)

Add `"$where":"0"` and `"$where":"1"` as additional JSON parameters. If responses differ, you have JavaScript execution inside MongoDB — this is the most powerful position because you can enumerate everything.

### Step 3: Enumerate Field Names (if $where works)

Use `Object.keys(this)[index].match('^.{position}character.*')` to extract field names character by character. Iterate through key indexes (0, 1, 2...) to discover all fields on the document.

This is how you find hidden fields like password reset tokens, API keys, or internal flags that aren't exposed in the application's normal responses.

### Step 4: Extract Field Values

Once you know the field name, switch to `this.fieldName.match('^.{position}character.*')` to extract the value character by character.

Alternative without `$where`: use `$regex` on a known field — `{"password":{"$regex":"^a.*"}}`. This works for fields you already know the name of but can't discover unknown fields.

### Step 5: Use the Extracted Data

Depends on what you found. A password lets you log in directly. A reset token goes into the password reset flow. An API key might unlock other endpoints.

## Scripting Is Essential

Character-by-character extraction generates hundreds to thousands of requests. A 32-character token with 36 possible characters per position (a-z + 0-9) means up to 1,152 requests for the value alone. With field name enumeration on top, you're looking at 2,500+ requests total.

Burp Intruder Community Edition throttles to ~1 request/second, making this painfully slow. A Python script using the `requests` library fires as fast as the server responds and chains phases automatically.

Basic script pattern:
```python
import requests, string

for position in range(50):
    for char in string.ascii_lowercase + string.digits:
        payload = f"injection with position {position} and char {char}"
        r = requests.post(url, json=payload, cookies=cookies)
        if len(r.text) > threshold:  # or status code, or response time
            result += char
            break
```

## Authentication Bypass Quick Reference

When you just need to bypass a login without extracting data:

```json
{"username":"admin","password":{"$ne":""}}
```
Matches any admin account with a non-empty password.

```json
{"username":{"$regex":"^admin"},"password":{"$ne":""}}
```
Pattern matches usernames starting with "admin" — useful when you don't know the exact username.

```json
{"username":"admin","password":{"$regex":"^.*"}}
```
Password matches any string — alternative to `$ne`.

If `$ne` on both fields returns too many records and the app expects one result, narrow the username with `$regex`.

## Prevention (For Reports)

- Sanitize and validate user input using an allowlist of accepted characters
- Use parameterized queries instead of concatenating user input into queries
- Apply an allowlist of accepted keys to prevent operator injection (`$ne`, `$where`, `$regex` should never come from user input)
- Disable server-side JavaScript execution (`$where`) if not needed
