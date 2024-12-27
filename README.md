# Django Deployment Script

This script automates the deployment of a Django project on a server. It handles dependency installation, virtual environment setup, Gunicorn configuration, and Nginx setup as the web server. The script also offers optional HTTPS configuration using Certbot for SSL certificates.

## Prerequisites

- Fresh Ubuntu installation on the target server
- Git repository containing your Django project
- SSH access to the server with sudo privileges
- Domain name (optional, for HTTPS setup)

### System Requirements

The script will install the following dependencies:
- Python 3 and related packages (python3-venv, python3-dev)
- Git for version control
- Nginx as the web server
- Gunicorn as the WSGI server
- libaugeas0 for Nginx configuration
- Certbot (optional, for SSL certificates)

## Installation

### Basic Usage

Deploy your Django project with the following command:

```bash
bash deploy.sh --repo <repository_url> --domain <your_domain>
```

### Command Arguments

- `--repo` (Required): URL of your Django project's Git repository
- `--domain` (Optional): Domain name for the project
  - If provided, HTTPS will be configured using Certbot
  - If omitted, the server's public IP address will be used

### Example Command

```bash
bash deploy.sh --repo https://github.com/yourusername/yourproject.git --domain example.com
```

## Deployment Process

The script performs the following steps in order:

1. **System Preparation**
   - Updates system packages
   - Installs required dependencies
   - Creates necessary directories

2. **Project Setup**
   - Clones the repository to `/var/www/yourproject/`
   - Creates and configures Python virtual environment
   - Installs project dependencies from `requirements.txt`
   - Collects static files using Django's collectstatic

3. **Server Configuration**
   - Sets up Gunicorn as the WSGI server
   - Configures Nginx as the reverse proxy
   - Implements HTTPS if domain is provided
   - Updates Django settings for production

4. **Security Implementation**
   - Configures secure cookies
   - Disables DEBUG mode
   - Sets up HTTPS redirects (if applicable)
   - Configures appropriate ALLOWED_HOSTS

## Post-Deployment Verification

### Server Status Checks

Monitor the status of your services:

```bash
sudo systemctl status gunicorn
sudo systemctl status nginx
```

### Log File Locations

- Nginx access logs: `/var/log/nginx/access.log`
- Nginx error logs: `/var/log/nginx/error.log`
- Gunicorn logs: Check systemd journal with `journalctl -u gunicorn`

## Configuration Requirements

### Project Requirements

1. Valid `requirements.txt` file in your repository
2. Django project structured according to best practices
3. Static files configured correctly in settings.py
4. Database configuration appropriate for production

### Server Requirements

1. Open ports:
   - Port 80 (HTTP)
   - Port 443 (HTTPS, if using SSL)
2. Sufficient permissions to:
   - Create/modify files in `/var/www/`
   - Manage system services
   - Configure Nginx

## Troubleshooting Guide

### Common Issues

1. **Gunicorn Fails to Start**
   - Check socket file existence: `/run/gunicorn.sock`
   - Verify file permissions
   - Review Gunicorn logs for Python errors

2. **Nginx Configuration Issues**
   - Validate configuration: `sudo nginx -t`
   - Check error logs: `/var/log/nginx/error.log`
   - Verify proxy settings to Gunicorn

3. **Static Files Not Serving**
   - Confirm STATIC_ROOT in settings.py
   - Verify collectstatic ran successfully
   - Check Nginx static file location configuration

### Security Notes

- Regularly update system packages
- Monitor server logs for suspicious activity
- Keep Django and dependencies updated
- Use strong database passwords
- Configure appropriate firewall rules

## License

This deployment script is released under the MIT License. See LICENSE file for details.

## Contributing

Contributions are welcome! Please submit issues and pull requests on the project repository.