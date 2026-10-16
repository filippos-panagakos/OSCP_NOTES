# osTicket Methodology

## 1. Discovery & Fingerprinting

- [ ] Check cookies for `OSTSESSID` → confirms osTicket
- [ ] View page source/footer → "powered by osTicket"
- [ ] Key endpoints:
  - `/open.php` — ticket submission portal (often unauthenticated)
  - `/scp/` — Staff Control Panel (admin login)
  - `/login.php` — user login
  - `/api/` — API endpoint

---

## 2. Email Pivoting Technique (PRIMARY ATTACK)

> **This is not a direct exploit — it's a pivoting technique to gain access to internal services.**

### How It Works

1. osTicket assigns an internal email to each ticket: `TICKET_NUMBER@company.local`
2. Submit a ticket → get a ticket number → you now control an internal email address
3. Use that email to register on internal services (GitLab, Slack, Mattermost, wikis)
4. Confirmation emails arrive as ticket replies
5. Click verification link → account verified on target service

### Step-by-Step

- [ ] Submit ticket via `/open.php`:
```bash
# Via browser or curl
curl -X POST "http://TARGET/open.php" \
  -d "name=Test+User&email=attacker@evil.com&topicId=1&subject=Test&message=Need+help"
```
- [ ] Note the assigned ticket number (e.g., `940288`)
- [ ] The internal email is now: `940288@inlanefreight.local`
- [ ] Go to internal GitLab → Register with email `940288@inlanefreight.local`
- [ ] GitLab sends confirmation to `940288@inlanefreight.local`
- [ ] Check osTicket ticket → confirmation email appears as a reply
- [ ] Click the verification link in the reply → GitLab account is now verified
- [ ] Browse internal repos for:
  - Hardcoded credentials
  - SSH keys
  - API tokens
  - Configuration files
  - `.env` files

### Services to Target with Pivoted Email
| Service | Why |
|---------|-----|
| GitLab | Source code, secrets, CI/CD configs |
| Slack | Internal comms, shared credentials |
| Mattermost | Same as Slack |
| Wiki/Confluence | Documentation, architecture, passwords |
| Jira | Internal info, sometimes creds in tickets |

---

## 3. CVE-2020-24881 — SSRF (osTicket 1.14.1)

- [ ] Server-Side Request Forgery
- [ ] Scan internal ports from the osTicket server
- [ ] Access internal resources not exposed externally
- [ ] Useful for internal network mapping

---

## 4. Post-Exploitation

- [ ] Config file: `include/ost-config.php`
```bash
cat include/ost-config.php | grep -i "db\|pass\|host"
```
- [ ] Database tables of interest:
  - `ost_staff` — staff credentials (username + password hash)
  - `ost_ticket` — ticket contents (may contain sensitive info)
  - `ost_config` — system configuration
- [ ] Tickets themselves may contain:
  - Password reset emails
  - Internal communications
  - VPN credentials
  - Service account info

---

## 5. Decision Tree

```
osTicket Found
├── /open.php accessible?
│   ├── YES → Submit ticket → get internal email
│   │   ├── Register on GitLab → browse repos → creds/keys
│   │   ├── Register on Slack/Mattermost → internal comms
│   │   └── Register on wiki → documentation/architecture
│   └── NO → try /scp/ admin login → default creds
├── Version 1.14.1? → CVE-2020-24881 SSRF → internal scanning
└── Post-exploit: ost-config.php → DB creds → pivot
```
