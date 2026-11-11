# HTB Delivery — Full Writeup

## Box Info

| Field | Value |
|---|---|
| Platform | HackTheBox |
| OS | Linux |
| Difficulty | Easy |
| Stack | Nginx / osTicket / Mattermost / MySQL |
| Key Concepts | Email trust abuse, credential reuse, hashcat rules, bcrypt cracking |

## Attack Flow

Nmap → Discover delivery.htb and helpdesk.delivery.htb → Find Mattermost on port 8065 → Open osTicket guest ticket → Get @delivery.htb ticket email → Register on Mattermost with ticket email → Retrieve verification email from osTicket ticket thread → Activate Mattermost account → Find SSH creds in internal channel → SSH as maildeliverer → Find MySQL creds in Mattermost config.json → Dump root bcrypt hash → Crack with hashcat rules → su root

## Phase 1: Enumeration

Nmap found port 22 (SSH), port 80 (HTTP/Nginx), and port 8065 (Mattermost).

Add to `/etc/hosts`:

```
10.10.x.x delivery.htb helpdesk.delivery.htb
```

The main site at `delivery.htb` has a contact page with a hint: you need a `@delivery.htb` email to access the Mattermost server. There's also a link to the helpdesk at `helpdesk.delivery.htb`.

Port 8065 runs Mattermost — a Slack-like team chat platform. Registration requires a `@delivery.htb` email for verification.

## Phase 2: Email Trust Abuse — osTicket to Mattermost

This is the core of the box and it's a real-world attack pattern.

### The Problem

Mattermost requires email verification with a `@delivery.htb` address. You don't have a mailbox on that domain.

### The Trick

osTicket assigns every new ticket a unique email address like `1234567@delivery.htb`. Any email sent to that address gets appended to the ticket thread. You can view the ticket thread as a guest by checking your ticket status.

### Steps

1. Go to `helpdesk.delivery.htb` and open a new ticket as a guest (use any email/name)
2. Note the ticket number and the assigned email (e.g., `1234567@delivery.htb`)
3. Go to Mattermost at `delivery.htb:8065` and register a new account using that ticket email
4. Mattermost sends a verification email to `1234567@delivery.htb`
5. Go back to osTicket → Check Ticket Status → enter your ticket email and ticket number
6. The Mattermost verification email appears in the ticket thread
7. Click the verification link → Mattermost account activated

### Why This Works

osTicket is designed to receive emails and append them to tickets. It trusts any email sent to a ticket address. Mattermost trusts that if you can click the verification link, you own that email address. By chaining these two trust assumptions, you bypass the email verification without ever owning a real mailbox.

This is a common pattern in real life — any system that gives you a controllable email inbox (ticketing systems, temp mail services, misconfigured mail servers) can be used to bypass email-based verification.

## Phase 3: Credential Discovery in Mattermost

After logging into Mattermost, join the internal team channel. There's a message from root containing SSH credentials:

```
maildeliverer : Youve_telestrategicOmitted
```

(The actual password is in the channel — grab it from there.)

```bash
ssh maildeliverer@delivery.htb
```

User flag is in `/home/maildeliverer/user.txt` or accessible from here.

## Phase 4: Privilege Escalation — maildeliverer to root

### Mattermost Config File

Mattermost stores its configuration in a JSON file. Find it:

```bash
find / -name config.json 2>/dev/null | grep mattermost
cat /opt/mattermost/config/config.json
```

Look for the SQL connection string:

```json
"DataSource": "mmuser:Crack_The_MM_Admin_PW@tcp(127.0.0.1:3306)/mattermost?..."
```

### MySQL Enumeration

Connect to MySQL with the creds from config.json:

```bash
mysql -u mmuser -p'Crack_The_MM_Admin_PW' mattermost
```

Dump the root user's hash:

```sql
SELECT Username, Password FROM Users WHERE Username = 'root'\G
```

This gives you a bcrypt hash (`$2a$10$...`).

### Cracking with Hashcat Rules

The Mattermost channel has a hint that the password is a variant of "PleaseSubscribe!" and mentions hashcat rules.

Instead of brute forcing the whole rockyou list against bcrypt (which is painfully slow), create a small wordlist and use hashcat rules to generate variations:

```bash
echo "PleaseSubscribe!" > base.txt
hashcat -m 3200 hash.txt base.txt -r /usr/share/hashcat/rules/best64.rule
```

The `best64.rule` generates common mutations — uppercase, lowercase, appending numbers, leet speak, etc. Since bcrypt is slow to crack, using a small targeted wordlist with rules is way faster than throwing rockyou at it.

Alternatively with john:

```bash
john hash.txt --wordlist=base.txt --rules=best64
```

### Root

```bash
su root
# Enter cracked password
cat /root/root.txt
```

## Methodology Notes

### Email Trust Abuse

This is an underrated attack vector. The pattern:
- Find a system that gives you a controllable email inbox (ticketing systems, support portals, temp mail)
- Use that inbox to bypass email verification on another service
- osTicket, Zendesk, OTRS, and similar tools are all potential targets
- Look for this whenever you see "requires @company.com email" restrictions

### Mattermost / Team Chat Pentesting

Internal chat platforms are goldmines:
- Default channels often contain credentials, API keys, internal URLs
- Check all channels you can access, including archived ones
- Config files contain database credentials (`config.json`, `.env`)
- Common locations: `/opt/mattermost/config/config.json`

### Hashcat Rules for Targeted Cracking

When you have a hint about the base password:
- Don't brute force with rockyou against bcrypt — it'll take days
- Create a small wordlist with the known base word
- Apply rules to generate variations: `best64.rule`, `rockyou-30000.rule`, `d3ad0ne.rule`
- This turns one word into thousands of mutations instantly
- Hashcat rules: `/usr/share/hashcat/rules/`

Common rules:
- `best64.rule` — 64 most effective mutations (fast)
- `rockyou-30000.rule` — 30k rules from rockyou analysis
- `d3ad0ne.rule` — large, thorough rule set
- `toggles1.rule` — toggle case of each character

### Bcrypt Cracking

Bcrypt (`$2a$`, `$2b$`, `$2y$`) is intentionally slow:
- Rockyou full list against bcrypt = hours/days
- Always try targeted wordlists + rules first
- Look for password hints in the environment (chat messages, comments, docs)
- The cost factor (the number after `$2a$10$`) determines speed — 10 is standard, higher is slower

### Config File Locations

Common places to find database credentials after getting a shell:
- `/opt/mattermost/config/config.json` — Mattermost
- `/var/www/html/.env` — Laravel, Node.js apps
- `/var/www/html/wp-config.php` — WordPress
- `/etc/grafana/grafana.ini` — Grafana
- `/opt/gitlab/embedded/service/gitlab-rails/config/database.yml` — GitLab
- Application config directories under `/opt/`, `/srv/`, `/var/www/`
