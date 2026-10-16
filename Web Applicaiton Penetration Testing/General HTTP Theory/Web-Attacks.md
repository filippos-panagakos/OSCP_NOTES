

The vulnerability usually happens when we limit a page's authorization to a particular set of HTTP verbs/methods, which leaves the other remaining methods unprotected.

For example, if a security filter was being used to detect injection vulnerabilities and only checked for injections in `POST` parameters (e.g. `$_POST['parameter']`), it may be possible to bypass it by simply changing the request method to `GET`.

`HTTP Method`

- HEAD
- PUT
- DELETE
- OPTIONS
- PATCH

a way to see what http verbs are allowed on a web server is to use curl with the X- options 

```
 curl -i  -X OPTIONS  http://154.57.164.73:32226/

```


Here we tried to create a test; file and it got rejected , if we change our request from a GET to a POST  the command executes 
![[Pasted image 20260916142518.png]]

![[Pasted image 20260916142618.png]]


![[Pasted image 20260916142640.png]]


![[Pasted image 20260916142647.png]]


> [!KEEP IN MIND]
> This shows that we successfully bypassed the filter through an HTTP Verb Tampering vulnerability and achieved command injection. Without the HTTP Verb Tampering vulnerability, the web application may have been secure against Command Injection attacks, and this vulnerability allowed us to bypass the filters in place altogether.



# Insecure Configurations

The following is an example of a vulnerable configuration for an Apache web server, which is located in the site configuration file (e.g. `000-default.conf`), or in a `.htaccess` web page configuration file:

```
<Directory "/var/www/html/admin">
    AuthType Basic
    AuthName "Admin Panel"
    AuthUserFile /etc/apache2/.htpasswd
    <Limit GET>
        Require valid-user
    </Limit>
</Directory>
```


> [!NOTE]
> this configuration is setting the authorization configurations for the `admin` web directory. However, as the `<Limit GET>` keyword is being used, the `Require valid-user` setting will only apply to `GET` requests, leaving the page accessible through `POST` requests. Even if both `GET` and `POST` were specified, this would leave the page accessible through other methods, like `HEAD` or `OPTIONS`



The following example shows the same vulnerability for a `Tomcat` web server configuration, which can be found in the `web.xml` file for a certain Java web application:

```
<security-constraint>
    <web-resource-collection>
        <url-pattern>/admin/*</url-pattern>
        <http-method>GET</http-method>
    </web-resource-collection>
    <auth-constraint>
        <role-name>admin</role-name>
    </auth-constraint>
</security-constraint>
```

We can see that the authorization is being limited only to the `GET` method with `http-method`, which leaves the page accessible through other HTTP methods.


```
<system.web>
    <authorization>
        <allow verbs="GET" roles="admin">
            <deny verbs="GET" users="*">
        </deny>
        </allow>
    </authorization>
</system.web>
```


Once again, the `allow` and `deny` scope is limited to the `GET` method, which leaves the web application accessible through other HTTP methods.


```
if (isset($_REQUEST['filename'])) {
    if (!preg_match('/[^A-Za-z0-9. _-]/', $_POST['filename'])) {
        system("touch " . $_REQUEST['filename']);
    } else {
        echo "Malicious Request Denied!";
    }
}
```


We see that the `preg_match` filter only checks for special characters in `POST` parameters with `$_POST['filename']`. However, the final `system` command uses the `$_REQUEST['filename']` variable, which covers both `GET` and `POST` parameters



## AJAX Calls


> [!NOTE]
> For example, if we did not have an admin account, only the user-level functions would be used, while the admin functions would be disabled. However, we may still be able to find the admin functions if we look into the front-end JavaScript code and may be able to identify AJAX calls to specific end-points or APIs that contain direct object references. If we identify direct object references in the JavaScript code, we can test them for IDOR vulnerabilities.





## IDOR

`Identify IDORS`

- In `URL parameters & APIs`
- In `AJAX Calls`
- By `understanding reference hashing/encoding`
- By `comparing user roles`


![[Pasted image 20260918140042.png]]


Here we were able to change the request from a POST to a GET use profile user 5 and manipulate the API call and get the information of user 5


Chaining IDOR # Vulnerabilities

![[Pasted image 20260918144123.png]]


Here we could fuzz the api call $ with intruder , we specified a number from 1-20 to find out what different roles exist, we found at UID 10 a user with admin rights

so we changed our cookie to his , and we were able to change and modify other users details since the web app had some sort of protection again the cookie role , once we changed it we could do anything!

We first changed our request to GET to extract the information and once we had everything needed we could do a POST request to finalize our changed and with a GET request we were able to see our updated profiles! 


# XXE

Here we saw that the entity email was printing text value so we declared it using 

DOCTYPE email

and then we added a new entity
ENTITY xxe 

and called the entity using the name "&xxe;"

![[Pasted image 20260918204710.png]]

> [!NOTE]
> In our example, the XML input in the HTTP request had no DTD being declared within the XML data itself, or being referenced externally, so we added a new DTD before defining our entity. If the `DOCTYPE` was already declared in the XML request, we would just add the `ENTITY` element to it.





![[Pasted image 20260918214949.png]]