#!/bin/bash
set -euo pipefail

# Rollback script for Django Deployment
# Author: Yessine Ben Rhouma

echo "Starting rollback process..."

# Function to find all Django projects by locating manage.py
find_django_projects() {
    find /var/www -type f -name "manage.py" | while read -r filepath; do
        dirname "$filepath"
    done
}

# Prompt user to choose a project
choose_project() {
    local projects=("$@")
    if [[ ${#projects[@]} -eq 0 ]]; then
        echo "Error: No Django projects found in /var/www." >&2
        exit 1
    elif [[ ${#projects[@]} -eq 1 ]]; then
        echo "${projects[0]}"
    else
        echo "Multiple Django projects found:"
        for i in "${!projects[@]}"; do
            echo "$((i + 1)). ${projects[$i]}"
        done

        read -p "Enter the number of the project you want to roll back: " choice
        if [[ $choice -ge 1 && $choice -le ${#projects[@]} ]]; then
            echo "${projects[$((choice - 1))]}"
        else
            echo "Invalid selection." >&2
            exit 1
        fi
    fi
}

# Find all projects and let the user choose
PROJECT_PATHS=($(find_django_projects))
PROJECT_PATH=$(choose_project "${PROJECT_PATHS[@]}")

# Derive project name and paths
PROJECT_NAME=$(basename "$PROJECT_PATH")
VENV_DIR="$PROJECT_PATH/venv"
GUNICORN_SERVICE="/etc/systemd/system/gunicorn.service"
GUNICORN_SOCKET="/etc/systemd/system/gunicorn.socket"
NGINX_CONF="/etc/nginx/sites-available/$PROJECT_NAME"
NGINX_LINK="/etc/nginx/sites-enabled/$PROJECT_NAME"

echo "Selected Django project: $PROJECT_NAME at $PROJECT_PATH"

# Stop services
echo "Stopping Gunicorn and Nginx services..."
if systemctl is-active --quiet gunicorn.service; then
    sudo systemctl stop gunicorn.service
fi
if systemctl is-active --quiet gunicorn.socket; then
    sudo systemctl stop gunicorn.socket
fi
if systemctl is-active --quiet nginx; then
    sudo systemctl restart nginx
fi

# Remove Gunicorn socket and service files
echo "Removing Gunicorn systemd files..."
if [[ -f "$GUNICORN_SERVICE" ]]; then
    sudo rm -f "$GUNICORN_SERVICE"
fi
if [[ -f "$GUNICORN_SOCKET" ]]; then
    sudo rm -f "$GUNICORN_SOCKET"
fi
sudo systemctl daemon-reload

# Remove NGINX configuration
echo "Removing Nginx configuration..."
if [[ -f "$NGINX_CONF" ]]; then
    sudo rm -f "$NGINX_CONF"
fi
if [[ -L "$NGINX_LINK" ]]; then
    sudo rm -f "$NGINX_LINK"
fi
sudo nginx -t || echo "NGINX config validation failed (as expected, configuration removed)"
sudo systemctl restart nginx

# Remove the virtual environment
echo "Removing virtual environment..."
if [[ -d "$VENV_DIR" ]]; then
    sudo rm -rf "$VENV_DIR"
fi

# Remove the project directory
echo "Removing project directory..."
if [[ -d "$PROJECT_PATH" ]]; then
    sudo rm -rf "$PROJECT_PATH"
fi

# Optionally revoke SSL certificates (if Certbot was used)
if [[ -n "$(which certbot)" ]]; then
    echo "Revoking and deleting SSL certificate..."
    DOMAIN="your_domain.com"  # Replace with your domain if needed
    sudo certbot delete --cert-name "$DOMAIN" || echo "SSL certificate not found for $DOMAIN"
fi

echo "Rollback completed successfully."
