# osTicket Labs

> Cross-reference: [[osticket-methodology]]

---

## Lab 1: Email Pivoting → GitLab Access → Credential Harvesting

### Objective
Use osTicket's email system to register on internal GitLab and find credentials.

### Steps

- [ ] Browse to `http://TARGET` — confirm osTicket (OSTSESSID cookie, footer)
- [ ] Navigate to `/open.php` (ticket submission)
- [ ] Submit a new ticket:
  - Name: `Test User`
  - Email: `your@email.com`
  - Subject: `Access Request`
  - Message: `Need help with account`
- [ ] Note the ticket number displayed (e.g., `940288`)
- [ ] Derive internal email: `940288@inlanefreight.local`
- [ ] Navigate to internal GitLab (e.g., `http://gitlab.inlanefreight.local`)
- [ ] Click **Register** → use email `940288@inlanefreight.local`
- [ ] Go back to osTicket → check your ticket for new replies
- [ ] Find GitLab confirmation email in ticket reply thread
- [ ] Click the verification/confirmation link
- [ ] Login to GitLab with your new account
- [ ] Enumerate repositories:
  - Browse all public/internal projects
  - Search for: `password`, `secret`, `key`, `token`, `config`
  - Check `.env` files, `docker-compose.yml`, CI/CD variables
  - Check commit history for removed secrets: `git log -p --all -S 'password'`
- [ ] Use discovered credentials to pivot to other services

### Success Criteria
- [ ] Registered on GitLab using osTicket-derived email
- [ ] Found credentials or sensitive data in repos
- [ ] Pivoted to additional service (SSH, database, admin panel)
