
This lab is vulnerable to username enumeration. It uses account locking, but this contains a logic flaw. To solve the lab, enumerate a valid username, brute-force this user's password, then access their account page.

- [Candidate usernames](https://portswigger.net/web-security/authentication/auth-lab-usernames)
- [Candidate passwords](https://portswigger.net/web-security/authentication/auth-lab-passwords)

--------
# Solution

We use a cluster bomb attack, first payload goes at the username parameter and the second one is just 5 null payloads to distinguish which account is valid its going to send 5 null payloads so a valid username would be when we receive the error message "You have made too many incorrect login attempts. Please try again in 1 minute" 

Once we get that valid user we can go ahead and brute force the password with a dir list! 

we will see different lengths from the responses, different errors as well , pay close attention to the response that has no error at all!  Weird , but the logic is when an account is locked out and you actually try a correct password it just redirects you to the login page

![](../../images/Pasted%20image%2020261015180246.png)