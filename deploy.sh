#!/bin/bash

# Default values for optional arguments
DOMAIN="none"

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --repo) PROJECT_REPO="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Ensure required arguments are provided
if [[ -z "$PROJECT_REPO" ]]; then
    echo "Error: --repo is required."
    exit 1
fi

# Extract the project name from the repository URL
PROJECT_NAME=$(basename -s .git "$PROJECT_REPO")

# Detect the server's public IP address
SERVER_IP=$(hostname -I | tr ' ' '\n' | grep -Ev '^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.' | head -n 1)

# Define other variables
PROJECT_DIR="/var/www/$PROJECT_NAME/"
VENV_NAME="venv"

# Update the system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y git python3 python3-venv libaugeas0 python3-dev nginx

# Create project directory and set up the project
mkdir -p $PROJECT_DIR && cd $PROJECT_DIR
git clone $PROJECT_REPO .
python3 -m venv $VENV_NAME
source $VENV_NAME/bin/activate

# Install project dependencies
pip install -r requirements.txt

# Collect static files
python3 manage.py collectstatic --noinput

# Update ALLOWED_HOSTS in settings.py
sed -i "s/ALLOWED_HOSTS = \[.*\]/ALLOWED_HOSTS = ['$SERVER_IP']/" $PROJECT_DIR/$PROJECT_NAME/settings.py

# Install Gunicorn
pip install gunicorn

# Calculate worker count
WORKER_COUNT=$(( $(nproc) * 2 + 1 ))

# Create Gunicorn socket file
cat <<EOF | sudo tee /etc/systemd/system/gunicorn.socket
[Unit]
Description=Gunicorn Socket

[Socket]
ListenStream=/run/gunicorn.sock

[Install]
WantedBy=sockets.target
EOF

# Create Gunicorn service file
cat <<EOF | sudo tee /etc/systemd/system/gunicorn.service
[Unit]
Description=Gunicorn Service
Requires=gunicorn.socket
After=network.target

[Service]
User=root
Group=root
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/$VENV_NAME/bin/gunicorn \
    --access-logfile - \
    --workers $WORKER_COUNT \
    --bind unix:/run/gunicorn.sock \
    $PROJECT_NAME.wsgi:application

[Install]
WantedBy=multi-user.target
EOF

# Create NGINX configuration
cat <<EOF | sudo tee /etc/nginx/sites-available/$PROJECT_NAME
server {
    listen 80;
    server_name $SERVER_IP ${DOMAIN:-_};

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
sudo ln -s /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/

# Test NGINX configuration and restart
sudo nginx -t && sudo systemctl restart nginx

# Set permissions for static and media files
sudo chown -R root:root $PROJECT_DIR
sudo chmod -R 755 $PROJECT_DIR

# Optional: Set up HTTPS using Certbot if a domain is provided
if [[ $DOMAIN != "none" ]]; then
    sudo python3 -m venv /opt/certbot/
    sudo /opt/certbot/bin/pip install certbot certbot-nginx
    sudo ln -s /opt/certbot/bin/certbot /usr/bin/certbot
    sudo certbot --nginx -d $DOMAIN
fi

# Finalize settings
sed -i "s/DEBUG = True/DEBUG = False/" $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME/settings.py
sed -i "s/CSRF_COOKIE_SECURE = False/CSRF_COOKIE_SECURE = True/" $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME/settings.py
sed -i "s/SESSION_COOKIE_SECURE = False/SESSION_COOKIE_SECURE = True/" $PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME/settings.py

# Restart NGINX
sudo nginx -t && sudo systemctl restart nginx

# Done!
echo "Django website deployed successfully!"
echo "Server IP: $SERVER_IP"
if [[ $DOMAIN != "none" ]]; then
    echo "Domain: $DOMAIN"
fi
