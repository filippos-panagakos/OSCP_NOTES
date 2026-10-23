
This lab's password reset functionality is vulnerable. To solve the lab, reset Carlos's password then log in and access his "My account" page.

- Your credentials: `wiener:peter`
- Victim's username: `carlos`


-----------

We get a temp token for our own account and use that token to reset a other users password 

replaced our username with carlos and we successfully reseted his password , the back end didnt validate the token to see if its the correct one for that user! it just relies on what is written in the parameter

![](../../images/Pasted%20image%2020261022155428.png)


---------

Beyond host header poisoning, other weak reset mechanisms you’ll see in the wild:

- Tokens that are just the user ID or username base64 encoded
- Tokens that never expire
- Tokens that don’t get invalidated after use (so one leaked token works forever)
- Reset links sent over HTTP instead of HTTPS (token visible in transit)
- The token leaked in the Referer header when the reset page loads external resources
- Predictable tokens based on timestamps or sequential numbers
- Password reset that only asks security questions with easily guessable answers
- Reset forms that tell you “this email doesn’t exist” (username enumeration)

The host header one is actually considered a medium-to-high severity finding on real pentests because it requires user interaction (carlos has to click the link). But combined with a convincing phishing setup, it works.