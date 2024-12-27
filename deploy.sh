#!/bin/bash
set -e
# Django Deployment Script
# Author: Yessine Ben Rhouma

# Default values
DOMAIN="none"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --repo) PROJECT_REPO="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$PROJECT_REPO" ]]; then
    echo "Error: --repo is required."
    exit 1
fi

sudo apt update && sudo apt upgrade -y
sudo apt install -y curl

SERVER_IP=$(curl -s http://checkip.amazonaws.com)

# Clone repository
git clone "$PROJECT_REPO" temp_repo

# Find project name by locating the settings.py file
SETTINGS_FILE=$(find temp_repo -name "settings.py" | head -n 1)
if [[ -z "$SETTINGS_FILE" ]]; then
    echo "Error: Could not find settings.py in the repository."
    exit 1
fi

PROJECT_NAME=$(basename "$(dirname "$SETTINGS_FILE")")
echo "Detected Django project name: $PROJECT_NAME"

# Setup project directory
PROJECT_DIR="/var/www/$PROJECT_NAME"
REPO_DIR="$PROJECT_DIR/$PROJECT_NAME"
VENV_DIR="$PROJECT_DIR/venv"

# Move repository contents
mkdir -p "$REPO_DIR"
mv temp_repo/* "$REPO_DIR"
rm -rf temp_repo

# Create and activate the virtual environment
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install -r "$REPO_DIR/requirements.txt"
pip install psycopg2-binary gunicorn

# Apply migrations and collect static files
python3 "$REPO_DIR/manage.py" migrate
python3 "$REPO_DIR/manage.py" collectstatic --noinput

# Modify settings
python3 <<EOF
import re
from pathlib import Path

settings_path = Path("$REPO_DIR/$PROJECT_NAME/settings.py")
content = settings_path.read_text()

content = re.sub(r"DEBUG\s*=\s*True", "DEBUG = False", content)
content = re.sub(r"ALLOWED_HOSTS\s*=\s*\[.*?\]", f"ALLOWED_HOSTS = ['{SERVER_IP}', '{DOMAIN}']", content)
content = re.sub(r"CSRF_COOKIE_SECURE\s*=\s*False", "CSRF_COOKIE_SECURE = True", content)
content = re.sub(r"SESSION_COOKIE_SECURE\s*=\s*False", "SESSION_COOKIE_SECURE = True", content)

settings_path.write_text(content)
EOF

# Gunicorn setup
WORKER_COUNT=$(( $(nproc) * 2 + 1 ))

sudo tee /etc/systemd/system/gunicorn.socket > /dev/null <<EOF
[Unit]
Description=Gunicorn Socket
[Socket]
ListenStream=/run/gunicorn.sock
SocketUser=www-data
SocketGroup=www-data
SocketMode=0660
[Install]
WantedBy=sockets.target
EOF

sudo tee /etc/systemd/system/gunicorn.service > /dev/null <<EOF
[Unit]
Description=Gunicorn Service
After=network.target
[Service]
User=www-data
Group=www-data
WorkingDirectory=$REPO_DIR
ExecStart=$VENV_DIR/bin/gunicorn --workers $WORKER_COUNT --bind unix:/run/gunicorn.sock $PROJECT_NAME.wsgi:application
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl start gunicorn.socket && sudo systemctl enable gunicorn.socket

# NGINX setup
sudo tee /etc/nginx/sites-available/$PROJECT_NAME > /dev/null <<EOF
server {
    listen 80;
    server_name $SERVER_IP ${DOMAIN:-_};

    location /static/ {
        root $REPO_DIR;
        autoindex on;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/gunicorn.sock;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl restart nginx

# Optional: Set up HTTPS using Certbot if a domain is provided
if [[ $DOMAIN != "none" ]]; then
    sudo python3 -m venv /opt/certbot/
    sudo /opt/certbot/bin/pip install certbot certbot-nginx
    sudo ln -s /opt/certbot/bin/certbot /usr/bin/certbot
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m contact@$DOMAIN
fi

echo "Django project $PROJECT_NAME deployed successfully at $SERVER_IP!"
