This lab's change email function is vulnerable to CSRF. To solve the lab, perform a CSRF attack that changes the victim's email address. You should use the provided exploit server to host your attack.

You can log in to your own account using the following credentials: `wiener:peter`

#### Hint

[ACCESS THE LAB](https://portswigger.net/web-security/learning-paths/csrf/csrf-bypassing-samesite-restrictions-using-on-site-gadgets/csrf/bypassing-samesite-restrictions/lab-samesite-strict-bypass-via-client-side-redirect#)

-------------


# Solution


The lab’s login cookie uses `SameSite=Strict`, which means the browser won’t send it on any cross-site request — so a normal CSRF attack (form POST from your exploit server) fails because the cookie never travels with it.

The trick is finding a **client-side redirect gadget** on the target site itself. The `/post/comment/confirmation` page takes a `postId` parameter and uses it in a `window.location` redirect via JavaScript. Because JavaScript redirects are treated as **same-site navigations** by the browser (unlike server-side 302s), the cookie gets attached.

By setting `postId` to a path traversal like `../my-account/change-email?email=hacked%40evil-user.net%26submit=1`, the confirmation page redirects the victim’s browser to the change-email endpoint — and since it’s a same-site navigation originating from the target domain, `SameSite=Strict` is satisfied and the session cookie rides along.

**The chain:**

1. Victim clicks exploit link → lands on target domain’s `/post/comment/confirmation`
2. That page’s JS reads `postId` and does `window.location = "/post/comment/confirmation/" + postId`
3. Path traversal breaks out to `/my-account/change-email?email=...&submit=1`
4. Browser treats it as same-site → cookie included → email changed

**Key takeaway:** `SameSite=Strict` isn’t bulletproof. Any open redirect or client-side redirect gadget on the same domain can bypass it. Always look for JavaScript-based redirects that accept user input — they’re your way around Strict.



<script>
window.location = "https://0a3600b103a81617806431660079005d.web-security-academy.net/post/comment/confirmation?postId=../my-account/change-email?email=hacked%40evil-user.net%26submit=1";
</script>