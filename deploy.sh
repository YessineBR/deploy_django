#!/bin/bash
set -euo pipefail

# Django Deployment Script with Enhanced Error Handling
# Author: Yessine Ben Rhouma

# Default values
DOMAIN="none"
ROLLBACK_FILES=()
APP_USER="www-data"  # Standard web server user
APP_GROUP="www-data"

# Trap errors for rollback
trap 'rollback_changes' ERR

function rollback_changes() {
    echo "An error occurred. Rolling back changes..."
    for file in "${ROLLBACK_FILES[@]}"; do
        if [[ -e $file ]]; then
            echo "Removing $file..."
            sudo rm -rf "$file"
        fi
    done
    echo "Rollback complete. Exiting."
    exit 1
}

function check_prerequisites() {
    echo "Checking prerequisites..."
    if ! command -v python3 &> /dev/null; then
        echo "Python3 not found. Installing required packages..."
        sudo apt update && sudo apt install -y python3 python3-venv python3-pip &> /dev/null
    fi
    
    if ! command -v nginx &> /dev/null; then
        echo "Nginx not found. Installing..."
        sudo apt install -y nginx &> /dev/null
    fi
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --repo) PROJECT_REPO="$2"; shift ;;
        --domain) DOMAIN="$2"; shift ;;
        --user) APP_USER="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "${PROJECT_REPO:-}" ]]; then
    echo "Error: --repo is required."
    exit 1
fi

# Check and install prerequisites
check_prerequisites

SERVER_IP=$(curl -s http://checkip.amazonaws.com)

# Clone repository
echo "Cloning repository..."
git clone "$PROJECT_REPO" temp_repo &> /dev/null
ROLLBACK_FILES+=("temp_repo")

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
SOCKET_FILE="/run/gunicorn_${PROJECT_NAME}.sock"
ROLLBACK_FILES+=("$PROJECT_DIR")

# Create project directory and set permissions
echo "Setting up project directory..."
sudo mkdir -p "$REPO_DIR"
sudo mv temp_repo/* "$REPO_DIR"
sudo rm -rf temp_repo

# Set correct ownership
sudo chown -R $APP_USER:$APP_GROUP "$PROJECT_DIR"

# Create and activate virtual environment with proper permissions
echo "Creating virtual environment..."
sudo -u $APP_USER python3 -m venv "$VENV_DIR" &> /dev/null
source "$VENV_DIR/bin/activate"

# Install dependencies
echo "Installing dependencies..."
sudo -u $APP_USER "$VENV_DIR/bin/pip" install -r "$REPO_DIR/requirements.txt" &> /dev/null
sudo -u $APP_USER "$VENV_DIR/bin/pip" install gunicorn psycopg2-binary &> /dev/null

# Apply migrations and collect static files
echo "Applying database migrations..."
sudo -u $APP_USER "$VENV_DIR/bin/python3" "$REPO_DIR/manage.py" migrate &> /dev/null
echo "Collecting static files..."
sudo -u $APP_USER "$VENV_DIR/bin/python3" "$REPO_DIR/manage.py" collectstatic --noinput &> /dev/null

# Modify settings
echo "Updating Django settings..."
sudo -u $APP_USER python3 <<EOF &> /dev/null
import re
from pathlib import Path

settings_path = Path("$REPO_DIR/$PROJECT_NAME/settings.py")
content = settings_path.read_text()

updates = {
    r"DEBUG\s*=\s*True": "DEBUG = False",
    r"ALLOWED_HOSTS\s*=\s*\[.*?\]": f"ALLOWED_HOSTS = ['$SERVER_IP', '$DOMAIN']",
    r"CSRF_COOKIE_SECURE\s*=\s*False": "CSRF_COOKIE_SECURE = True",
    r"SESSION_COOKIE_SECURE\s*=\s*False": "SESSION_COOKIE_SECURE = True"
}

for pattern, replacement in updates.items():
    content = re.sub(pattern, replacement, content)

settings_path.write_text(content)
EOF

# Calculate workers based on CPU cores
WORKER_COUNT=$(( $(nproc) * 2 + 1 ))

# Gunicorn socket configuration
echo "Configuring Gunicorn socket..."
sudo tee /etc/systemd/system/gunicorn_${PROJECT_NAME}.socket > /dev/null <<EOF
[Unit]
Description=Gunicorn Socket for ${PROJECT_NAME}

[Socket]
ListenStream=${SOCKET_FILE}
SocketUser=${APP_USER}
SocketGroup=${APP_GROUP}
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF
ROLLBACK_FILES+=("/etc/systemd/system/gunicorn_${PROJECT_NAME}.socket")

# Gunicorn service configuration
echo "Configuring Gunicorn service..."
sudo tee /etc/systemd/system/gunicorn_${PROJECT_NAME}.service > /dev/null <<EOF
[Unit]
Description=Gunicorn Service for ${PROJECT_NAME}
Requires=gunicorn_${PROJECT_NAME}.socket
After=network.target

[Service]
Type=notify
User=${APP_USER}
Group=${APP_GROUP}
RuntimeDirectory=gunicorn
WorkingDirectory=${REPO_DIR}
ExecStart=${VENV_DIR}/bin/gunicorn \
    --workers ${WORKER_COUNT} \
    --bind unix:${SOCKET_FILE} \
    --access-logfile /var/log/gunicorn_${PROJECT_NAME}_access.log \
    --error-logfile /var/log/gunicorn_${PROJECT_NAME}_error.log \
    ${PROJECT_NAME}.wsgi:application
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
ROLLBACK_FILES+=("/etc/systemd/system/gunicorn_${PROJECT_NAME}.service")

# Create log files and set permissions
sudo touch /var/log/gunicorn_${PROJECT_NAME}_access.log /var/log/gunicorn_${PROJECT_NAME}_error.log
sudo chown ${APP_USER}:${APP_GROUP} /var/log/gunicorn_${PROJECT_NAME}*.log

# Reload and start services
echo "Starting Gunicorn services..."
sudo systemctl daemon-reload
sudo systemctl start gunicorn_${PROJECT_NAME}.socket
sudo systemctl enable gunicorn_${PROJECT_NAME}.socket &> /dev/null
sudo systemctl start gunicorn_${PROJECT_NAME}.service
sudo systemctl enable gunicorn_${PROJECT_NAME}.service &> /dev/null

# NGINX configuration
echo "Configuring Nginx..."
# Determine the server name based on domain or project name
SERVER_NAME=${DOMAIN}
if [[ $DOMAIN == "none" ]]; then
    SERVER_NAME=${PROJECT_NAME}
fi

sudo tee /etc/nginx/sites-available/${SERVER_NAME} > /dev/null <<EOF
server {
    listen 80;
    server_name ${SERVER_IP} ${SERVER_NAME};

    access_log /var/log/nginx/${SERVER_NAME}_access.log;
    error_log /var/log/nginx/${SERVER_NAME}_error.log;

    client_max_body_size 100M;

    location /static/ {
        alias ${PROJECT_DIR}/static/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location /media/ {
        alias ${PROJECT_DIR}/media/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:${SOCKET_FILE};
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOF
ROLLBACK_FILES+=("/etc/nginx/sites-available/${SERVER_NAME}")

# Enable site and restart Nginx
sudo ln -sf /etc/nginx/sites-available/${SERVER_NAME} /etc/nginx/sites-enabled/
ROLLBACK_FILES+=("/etc/nginx/sites-enabled/${SERVER_NAME}")

# Test Nginx configuration
echo "Testing Nginx configuration..."
sudo nginx -t &> /dev/null
sudo systemctl restart nginx

# Optional: Set up HTTPS using Certbot if a domain is provided
if [[ $DOMAIN != "none" ]]; then
    echo "Setting up HTTPS with Certbot..."
    sudo python3 -m venv /opt/certbot/ &> /dev/null
    sudo /opt/certbot/bin/pip install certbot certbot-nginx &> /dev/null
    sudo ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m contact@$DOMAIN &> /dev/null
    ROLLBACK_FILES+=("/opt/certbot")
fi

# Final status check
echo "Performing final status check..."
sudo systemctl status gunicorn_${PROJECT_NAME}.service --no-pager
sudo systemctl status nginx --no-pager

# Cleanup rollback files on success
ROLLBACK_FILES=()
echo "Django project $PROJECT_NAME deployed successfully at $SERVER_IP!"
echo "You can check the application logs at:"
echo "- Gunicorn access log: /var/log/gunicorn_${PROJECT_NAME}_access.log"
echo "- Gunicorn error log: /var/log/gunicorn_${PROJECT_NAME}_error.log"
echo "- Nginx access log: /var/log/nginx/${PROJECT_NAME}_access.log"
echo "- Nginx error log: /var/log/nginx/${PROJECT_NAME}_error.log"