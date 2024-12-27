#!/bin/bash

# Variables - Update these to fit your setup
PROJECT_REPO="https://git.ulmus.tn/YessineBR/illico_pizza.git"
PROJECT_NAME="illico_pizza"
PROJECT_DIR="/var/www/illico_pizza/"
VENV_NAME="venv"
STATIC_ROOT="/var/www/illico_pizza"
MEDIA_ROOT="/var/www/illico_pizza"
SERVER_IP="<your_server_ip_address>"
DOMAIN="example.com" # Optional, use if you have a domain


sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y git python3 python3-venv libaugeas0 python3-dev nginx

# Create virtual environment and activate it
mkdir $PROJECT_DIR && cd $PROJECT_DIR
git clone $PROJECT_REPO .
python3 -m venv $VENV_NAME
source $VENV_NAME/bin/activate

# Install project dependencies
pip install -r requirements.txt

# Collect static files
python3 manage.py collectstatic --noinput

# Update ALLOWED_HOSTS
sed -i "s/ALLOWED_HOSTS = \[.*\]/ALLOWED_HOSTS = ['$SERVER_IP']" $PROJECT_DIR/$PROJECT_NAME/settings.py

# Install Gunicorn
pip install gunicorn

# Create Gunicorn socket file
cat <<EOF | sudo tee /etc/systemd/system/gunicorn.socket
[Unit]
Description=Gunicorn Socket

[Socket]
ListenStream=/run/gunicorn.sock

[Install]
WantedBy=sockets.target
EOF

WORKER_COUNT=$(( $(nproc) * 2 + 1 ))

# Create Gunicorn service file
cat <<EOF | sudo tee /etc/systemd/system/gunicorn.service
[Unit]
Description=Gunicorn Service
Requires=gunicorn.socket
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=$PROJECT_DIR/$PROJECT_NAME
ExecStart=$PROJECT_DIR/$VENV_NAME/bin/gunicorn \
    --access-logfile - \
    --workers $WORKER_COUNT \
    --bind unix:/run/gunicorn.sock \
    $PROJECT_NAME.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

# Create NGINX configuration
cat <<EOF | sudo tee /etc/nginx/sites-available/$DOMAIN
server {
    listen 80;
    server_name $SERVER_IP $DOMAIN;

    location = /favicon.ico { access_log off; log_not_found off; }

    location /static/ {
        root $PROJECT_DIR;
        autoindex on;
    }

    location /media/ {
        root $PROJECT_DIR;
        autoindex on;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/gunicorn.sock;
    }
}
EOF

# Enable NGINX configuration
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Test NGINX configuration and restart
sudo nginx -t && sudo systemctl restart nginx

# Set permissions for static and media files
sudo chown -R root:root $PROJECT_DIR
sudo chown -R root:root $PROJECT_DIR
sudo chmod -R 755 $PROJECT_DIR
sudo chmod -R 755 $PROJECT_DIR

# Optional: Set up HTTPS using Certbot
sudo python3 -m venv /opt/certbot/
sudo /opt/certbot/bin/pip install certbot certbot-nginx
sudo ln -s /opt/certbot/bin/certbot /usr/bin/certbot
sudo certbot --nginx -d $DOMAIN

# Finalize settings
sed -i "s/DEBUG = True/DEBUG = False/" $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME/settings.py
sed -i "s/CSRF_COOKIE_SECURE = False/CSRF_COOKIE_SECURE = True/" $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME/settings.py
sed -i "s/SESSION_COOKIE_SECURE = False/SESSION_COOKIE_SECURE = True/" $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME/settings.py

# Restart NGINX
sudo nginx -t && sudo systemctl restart nginx

# Done!
echo "Django website deployed successfully!"
