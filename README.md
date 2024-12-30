# Django Deployment Script

This script automates the deployment of a Django project on a server. It handles dependency installation, virtual environment setup, Gunicorn configuration, and Nginx setup as the web server. The script includes error handling with automatic rollback capability and optional HTTPS configuration using Certbot.

## Prerequisites

- Fresh Ubuntu installation on the target server
- Git repository containing your Django project
- SSH access to the server with sudo privileges
- Domain name (optional, for HTTPS setup)

### System Requirements

The script will automatically install the following dependencies if not present:
- Python 3 and related packages (python3-venv)
- Git for version control
- Nginx as the web server
- Gunicorn as the WSGI server
- Psycopg2-binary as the PostgreSQL adapter
- Certbot (optional, for SSL certificates)

## Installation

### Basic Usage

Deploy your Django project with the following command:

```bash
bash deploy.sh --repo <repository_url> [--domain <your_domain>] [--user <system_user>]
```

### Command Arguments

- `--repo` (Required): URL of your Django project's Git repository
- `--domain` (Optional): Domain name for the project
  - If provided, HTTPS will be configured using Certbot
  - If omitted, the server's IP address will be used
- `--user` (Optional): System user to run the application
  - Defaults to 'www-data' if not specified

### Example Commands

```bash
# Basic deployment using IP address
bash deploy.sh --repo https://github.com/yourusername/yourproject.git

# Deployment with domain and HTTPS
bash deploy.sh --repo https://github.com/yourusername/yourproject.git --domain example.com

# Deployment with custom system user
bash deploy.sh --repo https://github.com/yourusername/yourproject.git --domain example.com --user customuser
```

## Deployment Process

The script performs the following steps in order:

1. **System Preparation**
   - Checks and installs required dependencies
   - Creates necessary directories
   - Sets up proper file permissions

2. **Project Setup**
   - Clones the repository to `/var/www/yourproject/`
   - Creates and configures Python virtual environment
   - Installs project dependencies from `requirements.txt`
   - Runs migrations and collects static files

3. **Server Configuration**
   - Sets up Gunicorn with automatic worker calculation
   - Configures Nginx with optimized settings
   - Implements HTTPS if domain is provided
   - Updates Django settings for production

4. **Security Implementation**
   - Configures secure cookies
   - Disables DEBUG mode
   - Sets up HTTPS redirects (if applicable)
   - Configures appropriate ALLOWED_HOSTS
   - Sets proper file permissions and ownership

## Post-Deployment Verification

### Server Status Checks

Monitor the status of your services:

```bash
sudo systemctl status gunicorn_<project_name>.service
sudo systemctl status nginx
```

### Log File Locations

The script creates separate log files for each project:

- Nginx access logs: `/var/log/nginx/<server_name>_access.log`
- Nginx error logs: `/var/log/nginx/<server_name>_error.log`
- Gunicorn access logs: `/var/log/gunicorn_<project_name>_access.log`
- Gunicorn error logs: `/var/log/gunicorn_<project_name>_error.log`

Where:
- `<server_name>` is your domain name if provided, otherwise your project name
- `<project_name>` is automatically detected from your Django project structure

## Configuration Requirements

### Project Requirements

1. Valid `requirements.txt` file in your repository
2. Standard Django project structure with discoverable settings.py
3. Properly configured static files in settings.py
4. Production-ready database configuration

### Server Requirements

1. Open ports:
   - Port 80 (HTTP)
   - Port 443 (HTTPS, if using SSL)
2. Sufficient permissions to:
   - Create/modify files in `/var/www/`
   - Manage system services
   - Configure Nginx

## Error Handling and Rollback

The script includes automatic rollback functionality that:
- Tracks all created files and configurations
- Automatically removes them if an error occurs
- Provides clear error messages
- Ensures the server remains in a clean state even if deployment fails

## Troubleshooting Guide

### Common Issues

1. **Gunicorn Socket Connection Issues**
   - Check socket file existence: `/run/gunicorn_<project_name>.sock`
   - Verify file permissions and ownership
   - Check Gunicorn service status and logs

2. **Nginx Configuration Issues**
   - Validate configuration: `sudo nginx -t`
   - Check server_name directive matches your domain/project name
   - Verify proxy pass to correct socket file

3. **Static Files Not Serving**
   - Confirm STATIC_ROOT in settings.py
   - Check file permissions in static directory
   - Verify Nginx static file location configuration

4. **Permission Issues**
   - Check ownership of project files (`www-data:www-data` by default)
   - Verify socket file permissions
   - Check log file permissions

### Security Notes

- The script configures services with secure defaults
- Uses separate service instances per project for isolation
- Implements secure cookie settings
- Sets up HTTPS when domain is provided
- Uses proper file permissions and ownership
- Keeps services isolated with systemd
- Regularly update system packages and dependencies

## Best Practices

1. **Backup Before Deployment**
   - Take server snapshots if possible
   - Backup database if updating existing installation

2. **Testing**
   - Test deployment in a staging environment first
   - Verify all application functionality post-deployment
   - Check logs for any warnings or errors

3. **Maintenance**
   - Monitor log files regularly
   - Keep system packages updated
   - Regularly renew SSL certificates
   - Monitor disk space and resource usage

## Contributing

Contributions are welcome! Please submit issues and pull requests on the project repository.

## License

This deployment script is released under the MIT License. See LICENSE file for details.

## Acknowledgments

Original author: Yessine Ben Rhouma