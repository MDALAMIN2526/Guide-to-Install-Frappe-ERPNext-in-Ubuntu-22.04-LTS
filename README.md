# Guide to Install Frappe & ERPNext- v13 & v14 & v15 in Ubuntu-22.04-LTS
A complete Guide to Install Frappe Bench in Ubuntu 22.04 LTS and install Frappe/ERPNext Application

### Pre-requisites 

      Python 3.6+
      Node.js 14+
      Redis 5                                       (caching and real time updates)
      MariaDB 10.3.x / Postgres 9.5.x               (to run database driven apps)
      yarn 1.12+                                    (js dependency manager)
      pip 20+                                       (py dependency manager)
      wkhtmltopdf (version 0.12.5 with patched qt)  (for pdf generation)
      cron                                          (bench's scheduled jobs: automated certificate renewal, scheduled backups)
      NGINX                                         (proxying multitenant sites in production)



### STEP 1 Install git
    sudo apt-get install git -y
    sudo apt-get install cron
    sudo apt install curl

### STEP 2 install python-dev

    sudo apt-get install python3-dev -y

### STEP 3 Install setuptools and pip (Python's Package Manager).

    sudo apt-get install python3-setuptools python3-pip -y

### STEP 4 Install virtualenv
    
    sudo apt-get install virtualenv -y
    
  CHECK PYTHON VERSION 
  
    python3 -V
  
  IF VERSION IS 3.8.X RUN
  
    sudo apt install python3.8-venv -y

  IF VERSION IS 3.10.X RUN
  
     sudo apt install python3.10-venv -y

### STEP 5 Install MariaDB

    sudo apt-get install software-properties-common
    sudo apt install mariadb-server -y
    sudo mysql_secure_installation
    
    
### STEP 6  MySQL database development files

    sudo apt-get install libmysqlclient-dev -y

### STEP 7 Edit the mariadb configuration ( unicode character encoding )

    sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf

add this to the 50-server.cnf file

    
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

Now press (Ctrl-X) to exit

    sudo service mysql restart

### STEP 8 install Redis
    
    sudo apt-get install redis-server -y

### STEP 9 install Node.js 14.X package

    sudo apt-get remove nodejs
    sudo apt-get remove npm
    sudo apt-get update
    which node

    sudo apt install curl 
    curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash
    source ~/.profile
    nvm install 18.18.0 -y
    nvm use 18.18.0
    nvm alias default 18.18.0
    which node

### STEP 10  install Yarn

    sudo apt-get install npm -y

    sudo npm install -g yarn -y

### STEP 11 install wkhtmltopdf

    sudo apt-get install xvfb libfontconfig wkhtmltopdf -y

### STEP  12 Create a new user
    sudo adduser cpmerp
    sudo usermod -aG sudo cpmerp
    su - cpmerp
    chmod -R o+rx /home/cpmerp

### STEP 13 install frappe-bench

    sudo -H pip3 install frappe-bench
    
    bench --version
    
### STEP 14 initilise the frappe bench & install frappe latest version 

    bench init --frappe-branch version-13 frappe-bench 

    bench init --frappe-branch version-14 frappe-bench 

    bench init --frappe-branch version-15 frappe-bench
    
    cd frappe-bench/
    bench start
    
### STEP 15 create a site in frappe bench 
    
    bench new-site cpm.com
    
    bench use cpm.com
    #### Change Site Port 
          bench set-nginx-port cpm.com 88 

### STEP 16 install ERPNext latest version in bench & site

    bench get-app erpnext --branch version-13
    ###OR
    bench get-app erpnext --branch version-14
    bench get-app hrms --branch version-14
    ###OR
    bench get-app erpnext --branch version-15
    bench get-app hrms --branch version-15
    ###OR
    bench get-app https://github.com/frappe/erpnext --branch version-13
    ###OR
    bench get-app https://github.com/frappe/erpnext --branch version-14
    ###OR
    bench get-app https://github.com/frappe/erpnext --branch version-15
    
    bench --site cpm.com install-app erpnext
    
    bench --site cpm.com install-app hrms
    
    bench start
### STEP 17 SETUP PRODUCTION SERVER 
## Enable scheduler service 

    bench --site cpm.com enable-scheduler 
    

## Disable maintenance mode 

    bench --site cpm.com set-maintenance-mode off 
    

## Setup production config 

    sudo bench setup production cpmerp 
    

## Setup NGINX web server 

    bench setup nginx 
    

## Final server setup 

    sudo supervisorctl restart all 
    sudo bench setup production cpmerp 
    

# When prompted to save new/existing config files, hit “Y” 

## Delete a site
bench drop-site cpm.com
    
