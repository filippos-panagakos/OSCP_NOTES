# SMTP (Port 25)/ IMAP (Port 143) / POP3 (Port 110)

if you see this, there may be an exploit related to client side attacks so keep this in mind. 

Also once you get an initial foothold, be sure to check the /var/mail folder. Might have mail.

## Nmap Scripts

```bash
# SMTP
nmap -sV -sC -p 25 <target ip>
nmap --script smtp-commands -p 25 <target ip>            # list supported commands
nmap --script smtp-enum-users -p 25 <target ip>          # enumerate users
nmap --script smtp-vuln* -p 25 <target ip>               # known vulns
nmap --script smtp-open-relay -p 25 <target ip>          # check open relay

# IMAP
nmap -sV -sC -p 143,993 <target ip>
nmap --script imap-capabilities -p 143 <target ip>

# POP3
nmap -sV -sC -p 110,995 <target ip>
```

## User Enumeration

```bash
Usage: smtp-user-enum [options] ( -u username | -U file-of-usernames ) ( -t host | -T file-of-targets )

options are:
        -m n     Maximum number of processes (default: 5)
	-M mode  Method to use for username guessing EXPN, VRFY or RCPT (default: VRFY)
	-u user  Check if user exists on remote system
	-f addr  MAIL FROM email address.  Used only in "RCPT TO" mode (default: user@example.com)
        -D dom   Domain to append to supplied user list to make email addresses (Default: none)
                 Use this option when you want to guess valid email addresses instead of just usernames
                 e.g. "-D example.com" would guess foo@example.com, bar@example.com, etc.  Instead of 
                      simply the usernames foo and bar.
	-U file  File of usernames to check via smtp service
	-t host  Server host running smtp service
	-T file  File of hostnames running the smtp service
	-p port  TCP port on which smtp service runs (default: 25)
	-d       Debugging output
	-w n     Wait a maximum of n seconds for reply (default: 5)
	-v       Verbose

Examples:

$ smtp-user-enum -M VRFY -U users.txt -t 10.0.0.1
$ smtp-user-enum -M EXPN -u admin1 -t 10.0.0.1
$ smtp-user-enum -M RCPT -U users.txt -T mail-server-ips.txt
$ smtp-user-enum -M EXPN -D example.com -U users.txt -t 10.0.0.1
```

## Manual SMTP Interaction

```bash
# connect manually
nc -nv <target ip> 25
# or
telnet <target ip> 25

# commands to try
HELO test
EHLO test                    # extended hello, shows capabilities
VRFY root                   # verify if user exists
VRFY admin
EXPN postmaster             # expand mailing list
MAIL FROM:<attacker@test.com>
RCPT TO:<admin@target.com>  # if accepted, user exists
```

## Reading Mail (with creds)

```bash
# POP3 manual
telnet <target ip> 110
USER admin
PASS password
LIST                        # list messages
RETR 1                      # read message 1

# IMAP manual
telnet <target ip> 143
a LOGIN admin password
a LIST "" "*"               # list mailboxes
a SELECT INBOX
a FETCH 1 BODY[]            # read message 1

# curl for quick access
curl -k 'imaps://<target ip>' --user admin:password
curl -k 'imaps://<target ip>/INBOX;UID=1' --user admin:password
```

## Sending Email / Client-Side Attacks

You can use swaks to send email or use thunderbird for a GUI

```bash
# prep the config.Library-ms and body.txt in advance

sudo swaks -t <target email> --from <legit email> --attach @config.Library-ms --server <target ip> --body @body.txt --header <anything you want> --suppress-data -ap

# simple test email
swaks --to user@target.com --from attacker@test.com --server <target ip> --body "test"

# with attachment
swaks --to user@target.com --from attacker@test.com --server <target ip> --attach @malicious.odt
```

## Brute Force

```bash
# SMTP
hydra -L users.txt -P passwords.txt smtp://<target ip>

# POP3
hydra -L users.txt -P passwords.txt pop3://<target ip>

# IMAP
hydra -L users.txt -P passwords.txt imap://<target ip>
```
