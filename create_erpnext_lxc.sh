#!/bin/bash

# Exit on errors
set -e

# Function to prompt input with default
prompt() {
    read -p "$1 [$2]: " input
    echo "${input:-$2}"
}

echo "=== ERPNext Proxmox LXC Installer ==="

# Prompt for inputs
CT_ID=$(prompt "Enter LXC Container ID" "100")
CT_NAME=$(prompt "Enter LXC Container Name" "erpnext-lxc")
HOSTNAME=$(prompt "Enter hostname" "$CT_NAME")
DISK_SIZE=$(prompt "Enter disk size (in GB)" "8")
RAM_SIZE=$(prompt "Enter RAM size (in MB)" "2048")
CORE_COUNT=$(prompt "Enter CPU core count" "2")
USERNAME=$(prompt "Enter ERPNext system username" "cpmerp")
SITENAME=$(prompt "Enter ERPNext site name" "cpm.com")
ERP_BRANCH=$(prompt "Enter ERPNext version (version-13 / version-14 / version-15)" "version-15")
PASSWORD=$(prompt "Enter MySQL root password" "admin123")
TEMPLATE="local:vztmpl/ubuntu-22.04-standard_*.tar.zst"

# Check if template exists
if ! pct templates | grep -q "ubuntu-22.04"; then
    echo "Ubuntu 22.04 template not found. Downloading..."
    pveam update
    TEMPLATE_REMOTE=$(pveam available | grep "ubuntu-22.04" | sort -r | head -n1 | awk '{print $1}')
    pveam download local $TEMPLATE_REMOTE
fi

# Create the LXC container
echo "Creating LXC container..."
pct create $CT_ID $TEMPLATE \
    --hostname $HOSTNAME \
    --cores $CORE_COUNT \
    --memory $RAM_SIZE \
    --rootfs local-lvm:${DISK_SIZE}G \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --ostype ubuntu \
    --unprivileged 1 \
    --features nesting=1

# Start container
pct start $CT_ID
sleep 5

echo "Running installation inside LXC container..."
pct exec $CT_ID -- bash -c "
    set -e

    echo 'Updating and installing base packages...'
    apt-get update
    apt-get install -y git curl cron python3-dev python3-setuptools python3-pip virtualenv software-properties-common mariadb-server libmysqlclient-dev redis-server xvfb libfontconfig wkhtmltopdf npm

    echo 'Setting up Node and Yarn...'
    curl -fsSL https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash
    source ~/.profile
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\"
    nvm install 18.18.0
    nvm use 18.18.0
    nvm alias default 18.18.0
    npm install -g yarn

    echo 'Configuring MariaDB...'
    systemctl start mariadb
    mysql -e \"UPDATE mysql.user SET plugin='mysql_native_password' WHERE User='root';\"
    mysql -e \"FLUSH PRIVILEGES;\"
    mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '$PASSWORD';\"

    cat <<EOF > /etc/mysql/mariadb.conf.d/50-server.cnf
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
EOF

    service mysql restart

    echo 'Creating user $USERNAME...'
    adduser --disabled-password --gecos \"\" $USERNAME
    usermod -aG sudo $USERNAME
    chmod -R o+rx /home/$USERNAME

    echo 'Installing frappe-bench...'
    pip3 install frappe-bench

    echo 'Initializing bench for $USERNAME...'
    su - $USERNAME -c \"
        bench init --frappe-branch $ERP_BRANCH frappe-bench
        cd frappe-bench
        bench new-site $SITENAME --mariadb-root-password $PASSWORD --admin-password admin
        bench get-app erpnext --branch $ERP_BRANCH
        bench --site $SITENAME install-app erpnext
        bench start &
    \"
"

echo "=== ERPNext installation complete in LXC Container $CT_ID ==="
echo "Login with user: $USERNAME"
echo "Access site at: http://<container-ip>:8000"
