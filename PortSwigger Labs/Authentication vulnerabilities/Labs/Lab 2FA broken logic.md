
LABNot solved

This lab's two-factor authentication is vulnerable due to its flawed logic. To solve the lab, access Carlos's account page.

- Your credentials: `wiener:peter`
- Victim's username: `carlos`

You also have access to the email server to receive your 2FA verification code.


---------------

# Solution


Because the GET `/login2` is what **triggers the server to generate and send the OTP** to that user.

The flow is:

1. **POST `/login`** — you submit wiener’s username/password. Server validates it, sets a `verify=wiener` cookie, and redirects you to...
2. **GET `/login2`** — this is the 2FA page. When the server sees this request, it reads the `verify` cookie to decide **who to generate an OTP for**. If `verify=wiener`, it generates and sends wiener’s OTP. If you change it to `verify=carlos` here, **the server generates carlos’s OTP**.
3. **POST `/login2`** — you submit the OTP code. Server again reads the `verify` cookie to decide whose OTP to check against.

If you skip step 2 with `verify=carlos`, no OTP is ever generated for carlos. So when you brute force in step 3, you’re trying to match against an OTP that **doesn’t exist**. Every code fails.

That’s why your ffuf attempts returned zero hits — you were fuzzing against nothing.

The fix: after logging in as wiener, before fuzzing, send one GET `/login2` with `verify=carlos` to make the server generate carlos’s OTP. Then immediately brute force POST `/login2` with that same session cookie and `verify=carlos`. Now there’s an actual OTP to match against.

once you have a active session with carlos cookie you can grab that and change it with your cookie session and you are now logged in as carlos
![](../../images/Pasted%20image%2020261021190656.png)