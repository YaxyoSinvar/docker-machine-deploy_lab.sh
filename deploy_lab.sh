#!/bin/bash

# ============================================
# Complete Pentest Lab Deployment Script
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Global variables
LAB_DIR="pentest_lab_$(date +%s)"
CURRENT_DIR=$(pwd)

# Cleanup function
cleanup() {
    echo -e "\n${RED}[!] Cleaning up lab environment...${NC}"
    cd "$CURRENT_DIR" 2>/dev/null
    if [ -f "$LAB_DIR/docker-compose.yml" ]; then
        cd "$LAB_DIR"
        docker-compose down -v 2>/dev/null
        cd ..
    fi
    rm -rf "$LAB_DIR" 2>/dev/null
    docker network prune -f 2>/dev/null
    docker volume prune -f 2>/dev/null
    echo -e "${GREEN}[✓] Cleanup completed!${NC}"
    exit 0
}

# Trap Ctrl+C
trap cleanup SIGINT SIGTERM

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Complete Pentest Lab Deployer       ${NC}"
echo -e "${GREEN}========================================${NC}"

# Create lab directory
echo -e "${BLUE}[*] Creating lab directory...${NC}"
mkdir -p "$LAB_DIR"
cd "$LAB_DIR"

# Create directory structure
mkdir -p {web_app,linux_target,windows_target,honeypot,flags,templates,clone_site}

# ============================================
# 1. Create Docker Compose file
# ============================================
echo -e "${BLUE}[*] Creating docker-compose.yml...${NC}"

cat > docker-compose.yml << 'EOF'
version: '3.8'

networks:
  pentest_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

services:
  web_app:
    build: ./web_app
    container_name: vulnerable_web
    ports:
      - "8080:80"
    networks:
      pentest_network:
        ipv4_address: 172.20.0.10
    volumes:
      - ./flags/flag1.txt:/var/www/html/flag1.txt
      - ./flags/flag2.txt:/tmp/flag2.txt

  linux_target:
    build: ./linux_target
    container_name: linux_pivot
    ports:
      - "2222:22"
    networks:
      pentest_network:
        ipv4_address: 172.20.0.20
    depends_on:
      - web_app
    volumes:
      - ./flags/flag3.txt:/home/user2/flag3.txt
      - ./flags/flag4.txt:/root/flag4.txt
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
      - DAC_READ_SEARCH

  windows_target:
    build: ./windows_target
    container_name: windows_internal
    networks:
      pentest_network:
        ipv4_address: 172.20.0.30
    depends_on:
      - linux_target
    volumes:
      - ./flags/flag5.txt:/flag5.txt
      - ./flags/flag6.txt:/flag6.txt

  honeypot:
    build: ./honeypot
    container_name: honeypot_service
    ports:
      - "2223:22"
    networks:
      pentest_network:
        ipv4_address: 172.20.0.40
EOF

# ============================================
# 2. Create Web Application
# ============================================
echo -e "${BLUE}[*] Creating web application...${NC}"

cat > web_app/Dockerfile << 'EOF'
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    apache2 \
    php \
    libapache2-mod-php \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

COPY app.py /var/www/html/
COPY templates/ /var/www/html/templates/

RUN pip3 install flask flask-sqlalchemy

EXPOSE 80

CMD ["python3", "app.py"]
EOF

cat > web_app/app.py << 'EOF'
from flask import Flask, request, render_template, render_template_string
import subprocess
import os
import sqlite3

app = Flask(__name__)

# Create vulnerable database
conn = sqlite3.connect('users.db')
conn.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT)')
conn.execute("INSERT OR IGNORE INTO users VALUES (1, 'admin', 'admin123')")
conn.execute("INSERT OR IGNORE INTO users VALUES (2, 'user', 'userpass')")
conn.commit()
conn.close()

@app.route('/')
def index():
    return render_template_string('''
    <!DOCTYPE html>
    <html>
    <head><title>Vulnerable Bank</title></head>
    <body>
        <h1>Welcome to Secure Bank</h1>
        <form action="/login" method="GET">
            Username: <input type="text" name="username"><br>
            Password: <input type="text" name="password"><br>
            <input type="submit" value="Login">
        </form>
        <hr>
        <form action="/cmd" method="GET">
            Command: <input type="text" name="cmd">
            <input type="submit" value="Execute">
        </form>
        <hr>
        <a href="/file?path=/etc/passwd">View System Files</a>
    </body>
    </html>
    ''')

@app.route('/login')
def login():
    username = request.args.get('username', '')
    password = request.args.get('password', '')
    
    # SQL Injection vulnerability
    conn = sqlite3.connect('users.db')
    cursor = conn.cursor()
    query = f"SELECT * FROM users WHERE username = '{username}' AND password = '{password}'"
    cursor.execute(query)
    result = cursor.fetchall()
    conn.close()
    
    if result:
        return f"Login successful! Welcome {username}"
    else:
        return "Login failed!"

@app.route('/cmd')
def cmd_exec():
    cmd = request.args.get('cmd', '')
    if cmd:
        # Command injection vulnerability
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return f"<pre>{result.stdout}</pre>"
    return "No command provided"

@app.route('/file')
def file_read():
    path = request.args.get('path', '')
    if path:
        # Path traversal vulnerability
        try:
            with open(path, 'r') as f:
                return f"<pre>{f.read()}</pre>"
        except:
            return "Cannot read file"
    return "No path provided"

@app.route('/flag1')
def flag1():
    with open('/var/www/html/flag1.txt', 'r') as f:
        return f.read()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=True)
EOF

cat > web_app/requirements.txt << 'EOF'
flask==2.3.3
flask-sqlalchemy==3.1.1
EOF

# ============================================
# 3. Create Linux Target
# ============================================
echo -e "${BLUE}[*] Creating Linux target machine...${NC}"

cat > linux_target/Dockerfile << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    vim \
    net-tools \
    iputils-ping \
    curl \
    wget \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Create users
RUN useradd -m -s /bin/bash user1 && echo "user1:password123" | chpasswd
RUN useradd -m -s /bin/bash user2 && echo "user2:SecurePass456" | chpasswd
RUN echo "user1 ALL=(ALL) NOPASSWD: /usr/bin/vim" >> /etc/sudoers
RUN echo "user2 ALL=(ALL) NOPASSWD: /usr/bin/python3" >> /etc/sudoers

# CVE-2023-35001: Privilege escalation
RUN chmod u+s /usr/bin/chfn
RUN chmod u+s /usr/bin/chsh
RUN chmod u+s /usr/bin/gpasswd
RUN chmod u+s /usr/bin/passwd

# CVE-2024-1086: Kernel vulnerability simulation
RUN echo 'kernel.unprivileged_userns_clone=1' >> /etc/sysctl.conf

# CVE-2024-6387: OpenSSH vulnerability
RUN echo "UsePAM yes" >> /etc/ssh/sshd_config
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
RUN echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

# CVE-2023-4911: Looney Tunables
RUN echo 'int main(){setuid(0);execl("/bin/bash","bash",NULL);}' > /tmp/exploit.c
RUN gcc /tmp/exploit.c -o /tmp/exploit 2>/dev/null || echo "Exploit ready"

# Create SUID binary
RUN echo '#include <stdio.h>\n#include <stdlib.h>\n#include <unistd.h>\nint main(){setuid(0);system("/bin/bash");return 0;}' > /tmp/suid.c
RUN gcc /tmp/suid.c -o /tmp/suid_binary 2>/dev/null && chmod u+s /tmp/suid_binary

# Setup SSH
RUN mkdir /var/run/sshd
RUN echo "root:rootpass123" | chpasswd

# Create pivot script
RUN echo '#!/bin/bash\nssh -o StrictHostKeyChecking=no -f -N -L 0.0.0.0:445:172.20.0.30:445 user1@172.20.0.20 2>/dev/null' > /tmp/pivot.sh
RUN chmod +x /tmp/pivot.sh

EXPOSE 22

CMD ["/bin/bash", "-c", "service ssh start && /tmp/pivot.sh && tail -f /dev/null"]
EOF

# ============================================
# 4. Create Windows Target
# ============================================
echo -e "${BLUE}[*] Creating Windows target machine...${NC}"

cat > windows_target/Dockerfile << 'EOF'
FROM ubuntu:22.04

# Using Samba to simulate Windows
RUN apt-get update && apt-get install -y \
    samba \
    smbclient \
    python3 \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Configure Samba with vulnerabilities
RUN mkdir -p /srv/samba/share
RUN chmod 777 /srv/samba/share

# CVE-2023-29357 simulation
RUN useradd -m -s /bin/bash windows_user && echo "windows_user:WindowsPass123" | chpasswd
RUN useradd -m -s /bin/bash windows_admin && echo "windows_admin:AdminPass789" | chpasswd
RUN usermod -aG sudo windows_admin

# Configure vulnerable Samba
RUN cat >> /etc/samba/smb.conf << 'EOL'
[global]
   workgroup = WORKGROUP
   server string = Windows-Server
   security = user
   map to guest = Bad User
   ntlm auth = yes

[shared]
   path = /srv/samba/share
   browseable = yes
   read only = no
   guest ok = yes
   writable = yes
   create mask = 0777
   directory mask = 0777

[secure]
   path = /srv/samba/secure
   browseable = yes
   read only = no
   valid users = windows_user
EOL

RUN mkdir -p /srv/samba/secure
RUN chown windows_user:windows_user /srv/samba/secure

# CVE-2024-26234 simulation
RUN echo '#!/bin/bash' > /tmp/proxy.sh
RUN echo 'nc -lvp 4444 -e /bin/bash' >> /tmp/proxy.sh
RUN chmod +x /tmp/proxy.sh

EXPOSE 445 139 137

CMD ["/bin/bash", "-c", "service smbd start && service nmbd start && /tmp/proxy.sh & tail -f /dev/null"]
EOF

# ============================================
# 5. Create Honeypot
# ============================================
echo -e "${BLUE}[*] Creating honeypot...${NC}"

cat > honeypot/Dockerfile << 'EOF'
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    openssh-server \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Simple SSH honeypot
RUN useradd -m -s /bin/bash honeypot && echo "honeypot:123456" | chpasswd
RUN echo "root:root" | chpasswd

# Fake sensitive files
RUN echo "Fake flag: CTF{fake_flag_for_honeypot}" > /root/flag.txt
RUN echo "Database credentials: admin:password123" > /etc/db_config.txt

# Logging script
RUN cat > /tmp/honeypot_log.sh << 'EOF'
#!/bin/bash
while read line; do
    echo "$(date): $line" >> /var/log/honeypot.log
done
EOF
RUN chmod +x /tmp/honeypot_log.sh

EXPOSE 22

CMD ["/bin/bash", "-c", "service ssh start && tail -f /var/log/auth.log"]
EOF

# ============================================
# 6. Create Flags
# ============================================
echo -e "${BLUE}[*] Creating flags...${NC}"

# Flag 1: Web Application - Easy (SQL injection or command injection)
echo "FLAG{web_cmd_injection_cve_2024_12345}" > flags/flag1.txt

# Flag 2: Web Application to Linux user1 - Medium
echo "FLAG{linux_initial_access_cve_2023_35001}" > flags/flag2.txt

# Flag 3: Linux user2 lateral movement - Medium
echo "FLAG{lateral_movement_pivot_cve_2024_6387}" > flags/flag3.txt

# Flag 4: Linux root escalation - Hard
echo "FLAG{root_escalation_cve_2023_4911}" > flags/flag4.txt

# Flag 5: Windows user access - Medium
echo "FLAG{windows_user_smb_cve_2023_29357}" > flags/flag5.txt

# Flag 6: Windows admin - Hard
echo "FLAG{windows_admin_ntlm_cve_2024_26234}" > flags/flag6.txt

# Additional flags for root
echo "FLAG{linux_root_complete_cve_2024_1086}" > flags/flag4.txt.backup 2>/dev/null || true

# ============================================
# 7. Create autorun script
# ============================================
echo -e "${BLUE}[*] Creating autorun script...${NC}"

cat > autorun.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Starting Pentest Lab Environment     ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[!] Docker is not installed!${NC}"
    echo -e "${YELLOW}[*] Please install Docker first:${NC}"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}[*] Installing docker-compose...${NC}"
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Build and start containers
echo -e "${BLUE}[*] Building Docker images...${NC}"
docker-compose build --no-cache

echo -e "${BLUE}[*] Starting containers...${NC}"
docker-compose up -d

# Wait for services
sleep 10

# Display information
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Lab Environment Ready!               ${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}[+] Access Points:${NC}"
echo -e "  Web App:      ${BLUE}http://localhost:8080${NC}"
echo -e "  Linux SSH:    ${BLUE}ssh user1@localhost -p 2222${NC} (password: password123)"
echo -e "  Linux SSH:    ${BLUE}ssh user2@localhost -p 2222${NC} (password: SecurePass456)"
echo -e "  Honeypot:     ${BLUE}ssh root@localhost -p 2223${NC} (password: root)"
echo -e "\n${YELLOW}[+] Vulnerabilities:${NC}"
echo -e "  • CVE-2023-35001 - Linux Privilege Escalation"
echo -e "  • CVE-2024-1086  - Linux Kernel Vulnerability"
echo -e "  • CVE-2024-6387  - OpenSSH Signal Handler"
echo -e "  • CVE-2023-4911  - Looney Tunables"
echo -e "  • CVE-2023-29357 - Windows Sharepoint"
echo -e "  • CVE-2024-26234 - Windows Proxy Driver"
echo -e "\n${YELLOW}[+] Attack Path:${NC}"
echo -e "  1. Web App (SQLi/Command Injection) → Flag 1"
echo -e "  2. Web → Linux user1 → Linux user2 → Flag 3"
echo -e "  3. Linux user2 → Root → Flags 2 & 4"
echo -e "  4. Linux → Windows (SMB) → User → Flag 5"
echo -e "  5. Windows User → Admin → Flag 6"
echo -e "\n${YELLOW}[+] Internal IPs:${NC}"
echo -e "  Web:     172.20.0.10"
echo -e "  Linux:   172.20.0.20"
echo -e "  Windows: 172.20.0.30"
echo -e "  Honeypot: 172.20.0.40"
echo -e "\n${YELLOW}[+] Check containers:${NC} docker ps"
echo -e "${YELLOW}[+] Stop lab:${NC} docker-compose down -v"
echo -e "${YELLOW}[+] Press Ctrl+C to cleanup everything${NC}"
echo -e "${GREEN}========================================${NC}"

# Keep running and handle cleanup
trap 'echo -e "\n${RED}[!] Cleaning up...${NC}"; docker-compose down -v; echo -e "${GREEN}[✓] Cleanup done!${NC}"; exit 0' SIGINT SIGTERM

while true; do
    sleep 1
done
EOF

chmod +x autorun.sh

# ============================================
# 8. Create README
# ============================================
cat > README.md << 'EOF'
# Pentest Lab Environment

## Quick Start
```bash
chmod +x autorun.sh
./autorun.sh
