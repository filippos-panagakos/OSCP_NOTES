LABNot solved

This lab's password change functionality makes it vulnerable to brute-force attacks. To solve the lab, use the list of candidate passwords to brute-force Carlos's account and access his "My account" page.

- Your credentials: `wiener:peter`
- Victim's username: `carlos`
- [Candidate passwords](https://portswigger.net/web-security/authentication/auth-lab-passwords)

[](https://portswigger.net/web-security/learning-paths/authentication-vulnerabilities/vulnerabilities-in-other-authentication-mechanisms/authentication/other-mechanisms/lab-password-brute-force-via-password-change#)


-------------

# Solution


The change password form has a hidden `username` field and three different behaviors based on what you submit:

1. Wrong current password + matching new passwords → account locks out
2. Wrong current password + mismatched new passwords → “Current password is incorrect” (no lockout)
3. Correct current password + mismatched new passwords → “New passwords do not match” (no lockout)

The flaw is that behavior 2 and 3 produce different error messages, and neither triggers a lockout. So by always sending mismatched new passwords, you bypass the lockout mechanism entirely and can brute force the current password by looking for which response says “New passwords do not match” instead of “Current password is incorrect.”

Change the hidden `username` to carlos, fuzz `current-password` with the candidate list, keep `new-password-1` and `new-password-2` different, and grep for “New passwords do not match.” That’s carlos’s password.

```
POST /my-account/change-password
username=carlos&current-password=FUZZ&new-password-1=123&new-password-2=abc
```

The developer only added lockout protection for one code path and forgot the others. Classic logic flaw.


![](../../images/Pasted%20image%2020261022170020.png)


![](../../images/Pasted%20image%2020261022170031.png)