#!/bin/bash
# ERPNext LXC Auto-Installer for Proxmox with Automatic Template Handling

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if running on Proxmox host
if ! grep -q "Proxmox" /etc/issue; then
    echo -e "${RED}This script must be run on a Proxmox host${NC}"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

# Function to handle template verification and download
verify_template() {
    echo -e "${YELLOW}Checking for Ubuntu 22.04 template...${NC}"
    pveam update >/dev/null
    
    # Look for any Ubuntu 22.04 template
    TEMPLATE=$(pveam available --section system | grep -i "ubuntu-22" | head -1 | awk '{print $2}')
    
    if [ -z "$TEMPLATE" ]; then
        echo -e "${RED}No Ubuntu 22.04 template found in repositories${NC}"
        echo -e "${YELLOW}Attempting to download directly...${NC}"
        
        TEMPLATE="ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
        TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"
        
        if [ ! -f "$TEMPLATE_PATH" ]; then
            wget https://cloud-images.ubuntu.com/releases/22.04/release/$TEMPLATE -P /var/lib/vz/template/cache/
            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to download Ubuntu 22.04 template${NC}"
                echo "Please manually download a template and try again."
                echo "Options:"
                echo "1. pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
                echo "2. Download from: https://cloud-images.ubuntu.com/releases/22.04/release/"
                exit 1
            fi
            echo -e "${GREEN}Template downloaded successfully${NC}"
        fi
        echo -e "${YELLOW}Using manually downloaded template${NC}"
        return
    fi
    
    # Check if template is already downloaded
    if ! pveam list local | grep -q "$TEMPLATE"; then
        echo -e "${YELLOW}Downloading $TEMPLATE...${NC}"
        pveam download local "$TEMPLATE"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to download template $TEMPLATE${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}Using template: $TEMPLATE${NC}"
}

# Verify and handle template
verify_template

# Get next available CTID
CTID=$(pvesh get /cluster/nextid)
if [ -z "$CTID" ]; then
    CTID=100
fi

echo ""
echo "ERPNext LXC Container Creation"
echo "============================="

# Get basic LXC parameters
read -p "Enter hostname for the container [erpnext-lxc]: " HOSTNAME
HOSTNAME=${HOSTNAME:-erpnext-lxc}

read -p "Enter domain name [local.lan]: " DOMAIN
DOMAIN=${DOMAIN:-local.lan}

FQDN="${HOSTNAME}.${DOMAIN}"

read -p "Enter container ID [$CTID]: " INPUT_CTID
CTID=${INPUT_CTID:-$CTID}

read -p "Enter root password for container: " ROOT_PASS
while [ -z "$ROOT_PASS" ]; do
    read -p "Root password cannot be empty. Enter root password: " ROOT_PASS
done

read -p "Enter memory allocation in MB [2048]: " MEMORY
MEMORY=${MEMORY:-2048}

read -p "Enter disk space in GB [20]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-20}

read -p "Enter number of CPU cores [2]: " CORES
CORES=${CORES:-2}

# Get ERPNext specific parameters
echo ""
echo "ERPNext Configuration"
echo "===================="

read -p "Enter ERPNext admin username [erpuser]: " ERP_USER
ERP_USER=${ERP_USER:-erpuser}

read -p "Enter ERPNext admin password: " ERP_PASS
while [ -z "$ERP_PASS" ]; do
    read -p "ERPNext password cannot be empty. Enter password: " ERP_PASS
done

read -p "Enter site name [erp.example.com]: " SITE_NAME
SITE_NAME=${SITE_NAME:-erp.example.com}

read -p "Enter MariaDB root password: " DB_ROOT_PASS
while [ -z "$DB_ROOT_PASS" ]; do
    read -p "Database root password cannot be empty. Enter password: " DB_ROOT_PASS
done

echo ""
echo "Available ERPNext versions:"
echo "1) Version 13"
echo "2) Version 14"
echo "3) Version 15"
read -p "Select ERPNext version (1-3) [3]: " VERSION_CHOICE
VERSION_CHOICE=${VERSION_CHOICE:-3}

case $VERSION_CHOICE in
    1) 
        FRAPPE_BRANCH="version-13"
        ERPNEXT_BRANCH="version-13"
        ;;
    2) 
        FRAPPE_BRANCH="version-14"
        ERPNEXT_BRANCH="version-14"
        ;;
    3) 
        FRAPPE_BRANCH="version-15"
        ERPNEXT_BRANCH="version-15"
        ;;
    *)
        echo -e "${RED}Invalid version choice${NC}"
        exit 1
        ;;
esac

# Summary
echo ""
echo "Configuration Summary"
echo "==================="
echo "Container ID: $CTID"
echo "Hostname: $HOSTNAME"
echo "FQDN: $FQDN"
echo "Memory: $MEMORY MB"
echo "Disk: $DISK_SIZE GB"
echo "Cores: $CORES"
echo ""
echo "ERPNext Username: $ERP_USER"
echo "ERPNext Site: $SITE_NAME"
echo "ERPNext Version: $ERPNEXT_BRANCH"
echo ""
read -p "Proceed with container creation? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Aborting...${NC}"
    exit 1
fi

# Create the container
echo -e "${YELLOW}Creating LXC container...${NC}"
if [[ $TEMPLATE == *"http"* ]]; then
    # Using manually downloaded template
    pct create $CTID \
        /var/lib/vz/template/cache/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
        --hostname $FQDN \
        --password "$ROOT_PASS" \
        --storage local-lvm \
        --unprivileged 1 \
        --cores $CORES \
        --memory $MEMORY \
        --swap 512 \
        --ostype ubuntu \
        --arch amd64 \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --rootfs local-lvm:${DISK_SIZE} \
        --features nesting=1 \
        --onboot 1 \
        --start 1
else
    # Using template from Proxmox repository
    pct create $CTID \
        local:vztmpl/$TEMPLATE \
        --hostname $FQDN \
        --password "$ROOT_PASS" \
        --storage local-lvm \
        --unprivileged 1 \
        --cores $CORES \
        --memory $MEMORY \
        --swap 512 \
        --ostype ubuntu \
        --arch amd64 \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --rootfs local-lvm:${DISK_SIZE} \
        --features nesting=1 \
        --onboot 1 \
        --start 1
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create container${NC}"
    exit 1
fi

# Wait for container to start
echo -e "${YELLOW}Waiting for container to start...${NC}"
sleep 15

# Prepare installation script to be executed inside container
INSTALL_SCRIPT="/tmp/install_erpnext_$CTID.sh"

cat > $INSTALL_SCRIPT <<EOF
#!/bin/bash
# ERPNext Auto-Installer for Proxmox LXC

# Parameters from Proxmox host
ERP_USER="$ERP_USER"
ERP_PASS="$ERP_PASS"
SITE_NAME="$SITE_NAME"
DB_ROOT_PASS="$DB_ROOT_PASS"
FRAPPE_BRANCH="$FRAPPE_BRANCH"
ERPNEXT_BRANCH="$ERPNEXT_BRANCH"

# Install required packages
apt-get update
apt-get install -y sudo curl wget

# Create user and set password
adduser --disabled-password --gecos "" \$ERP_USER
echo "\$ERP_USER:\$ERP_PASS" | chpasswd
usermod -aG sudo \$ERP_USER

# Create the installation script in the new user's home
sudo -u \$ERP_USER bash -c 'cat > /home/\$USER/install_erpnext.sh <<"EOSCRIPT"
#!/bin/bash

# Colors
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[0;33m'
NC='\\033[0m'

# Update system
echo -e "\${YELLOW}Updating system...\${NC}"
sudo apt-get update && sudo apt-get upgrade -y

# Install dependencies
echo -e "\${YELLOW}Installing dependencies...\${NC}"
sudo apt-get install -y git cron curl python3-dev python3-setuptools python3-pip virtualenv

# Python venv
PYTHON_VERSION=\$(python3 -V | cut -d" " -f2 | cut -d"." -f1-2)
sudo apt-get install -y python3.\$PYTHON_VERSION-venv

# Install MariaDB
echo -e "\${YELLOW}Installing MariaDB...\${NC}"
sudo apt-get install -y software-properties-common mariadb-server libmysqlclient-dev

# Secure MariaDB
echo -e "\${YELLOW}Securing MariaDB...\${NC}"
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '\$DB_ROOT_PASS';"
sudo mysql -uroot -p"\$DB_ROOT_PASS" -e "DELETE FROM mysql.user WHERE User='';"
sudo mysql -uroot -p"\$DB_ROOT_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
sudo mysql -uroot -p"\$DB_ROOT_PASS" -e "DROP DATABASE IF EXISTS test;"
sudo mysql -uroot -p"\$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# Configure MariaDB
echo -e "\${YELLOW}Configuring MariaDB...\${NC}"
sudo cat > /etc/mysql/mariadb.conf.d/50-server.cnf <<EOL
[server]
user = mysql
pid-file = /run/mysqld/mysqld.pid
socket = /run/mysqld/mysqld.sock
basedir = /usr
datadir = /var/lib/mysql
tmpdir = /tmp
lc-messages-dir = /usr/share/mysql
bind-address = 127.0.0.1
query_cache_size = 16M
log_error = /var/log/mysql/error.log

[mysqld]
innodb-file-format=barracuda
innodb-file-per-table=1
innodb-large-prefix=1
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOL

sudo service mysql restart

# Install Redis
echo -e "\${YELLOW}Installing Redis...\${NC}"
sudo apt-get install -y redis-server

# Install Node.js
echo -e "\${YELLOW}Installing Node.js...\${NC}"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
nvm install 18.18.0
nvm use 18.18.0
nvm alias default 18.18.0

# Install Yarn
echo -e "\${YELLOW}Installing Yarn...\${NC}"
npm install -g yarn

# Install wkhtmltopdf
echo -e "\${YELLOW}Installing wkhtmltopdf...\${NC}"
sudo apt-get install -y xvfb libfontconfig wkhtmltopdf

# Install frappe-bench
echo -e "\${YELLOW}Installing frappe-bench...\${NC}"
pip3 install frappe-bench

# Initialize bench
echo -e "\${YELLOW}Initializing bench...\${NC}"
bench init --frappe-branch \$FRAPPE_BRANCH frappe-bench

# Create new site
echo -e "\${YELLOW}Creating site...\${NC}"
cd frappe-bench
bench new-site \$SITE_NAME --mariadb-root-password \$DB_ROOT_PASS

# Get ERPNext app
echo -e "\${YELLOW}Downloading ERPNext...\${NC}"
bench get-app erpnext --branch \$ERPNEXT_BRANCH

# Install ERPNext
echo -e "\${YELLOW}Installing ERPNext...\${NC}"
bench --site \$SITE_NAME install-app erpnext

# Install HRMS if version 14 or 15
if [[ "\$ERPNEXT_BRANCH" == "version-14" || "\$ERPNEXT_BRANCH" == "version-15" ]]; then
    echo -e "\${YELLOW}Downloading HRMS...\${NC}"
    bench get-app hrms --branch \$ERPNEXT_BRANCH
    
    echo -e "\${YELLOW}Installing HRMS...\${NC}"
    bench --site \$SITE_NAME install-app hrms
fi

# Setup production
echo -e "\${YELLOW}Setting up production...\${NC}"
bench --site \$SITE_NAME enable-scheduler
bench --site \$SITE_NAME set-maintenance-mode off
bench setup production \$USER
bench setup nginx
sudo supervisorctl restart all

# Get container IP
IP=\$(hostname -I | awk '{print \$1}')

# Completion message
echo -e "\${GREEN}ERPNext installation completed successfully!\${NC}"
echo ""
echo "Access your ERPNext installation:"
echo "URL: http://\$IP"
echo "Site: \$SITE_NAME"
echo "Username: Administrator"
echo "Password: The password you set during site creation"
echo ""
echo "To start bench in development mode:"
echo "cd ~/frappe-bench && bench start"
EOSCRIPT'

# Make the script executable and run it
chmod +x /home/\$ERP_USER/install_erpnext.sh
sudo -u \$ERP_USER bash -c "cd /home/\$USER && ./install_erpnext.sh"
EOF

# Copy and execute the installation script inside the container
echo -e "${YELLOW}Starting ERPNext installation inside container...${NC}"
chmod +x $INSTALL_SCRIPT
pct push $CTID $INSTALL_SCRIPT /root/install_erpnext.sh
pct exec $CTID -- bash /root/install_erpnext.sh

# Cleanup
rm $INSTALL_SCRIPT

# Get container IP
CT_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')

echo -e "${GREEN}ERPNext LXC container setup completed successfully!${NC}"
echo ""
echo "Container Details:"
echo "================="
echo "Container ID: $CTID"
echo "Hostname: $FQDN"
echo "IP Address: $CT_IP"
echo "Root Password: $ROOT_PASS"
echo ""
echo "ERPNext Details:"
echo "==============="
echo "Site URL: http://$CT_IP"
echo "Site Name: $SITE_NAME"
echo "ERPNext Admin: $ERP_USER"
echo "ERPNext Password: $ERP_PASS"
echo "MariaDB Root Password: $DB_ROOT_PASS"
echo "ERPNext Version: $ERPNEXT_BRANCH"
echo ""
echo "Access the container: pct enter $CTID"
echo "Start development server: sudo -u $ERP_USER -i; cd ~/frappe-bench; bench start"
