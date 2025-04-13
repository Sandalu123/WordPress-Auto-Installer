# WordPress Auto-Installer

An interactive Bash script that automatically installs and configures WordPress with multiple SSL options, custom port configuration, and firewall settings.

## Features

- **Interactive setup**: Configure HTTP/HTTPS ports and firewall settings
- **Multiple SSL options**:
  - CloudFlare integration
  - Let's Encrypt automatic certificates
  - Custom SSL certificate support
  - Self-signed certificates
- **Custom port support**: Run WordPress on any port you choose
- **Firewall configuration**: UFW firewall setup with customizable rules
- **One-command installation**: Complete WordPress setup with a single command
- **Secure by default**: Random password generation and proper file permissions
- **Full LAMP stack**: Installs and configures Linux, Apache, MySQL, and PHP
- **Detailed logging**: Saves all credentials and configuration to a protected log file

## Requirements

- Ubuntu or Debian-based Linux distribution
- Root access
- Internet connection
- Domain name (required for Let's Encrypt and recommended for CloudFlare)

## Quick Install

Execute directly from GitHub:

```bash
curl -L https://raw.githubusercontent.com/Sandalu123/WordPress-Auto-Installer/main/install-wordpress.sh | sudo bash
```

## Manual Installation

```bash
# Clone repository
git clone https://github.com/Sandalu123/WordPress-Auto-Installer.git

# Navigate to directory
cd WordPress-Auto-Installer

# Make script executable
chmod +x install-wordpress.sh

# Run script as root
sudo ./install-wordpress.sh
```

## SSL Configuration Options

### 1. Self-signed Certificate
- Quickest setup option
- No domain required
- Browser will show security warnings
- Good for development and testing

### 2. CloudFlare
- Uses CloudFlare as SSL provider
- Requires a CloudFlare account and domain
- Configures Apache for CloudFlare origin certificates
- Provides proper SSL without browser warnings

### 3. Let's Encrypt
- Free trusted SSL certificates
- Requires a domain pointing to your server
- Automatic certificate renewal
- No browser warnings

### 4. Custom SSL Certificate
- Use your existing SSL certificate files
- Validates certificate and key before installation
- Supports various certificate formats

## Firewall Configuration

The script can configure UFW (Uncomplicated Firewall) with:
- Custom SSH port (enhanced security)
- WordPress HTTP/HTTPS ports
- Additional custom ports as needed

## What It Does

1. Prompts for configuration settings
2. Updates system packages
3. Installs Apache, MySQL, and PHP with required extensions
4. Configures Apache to run on your specified port
5. Sets up SSL with your chosen method
6. Configures MySQL with secure random passwords
7. Downloads and installs the latest WordPress
8. Sets up proper file permissions for security
9. Configures firewall rules if enabled
10. Saves all credentials and configuration to a protected log file

## After Installation

Once installation is complete:

- WordPress will be installed at `/var/www/html`
- Access your WordPress site at the configured HTTP/HTTPS URL
- Complete the WordPress setup by visiting your site in a browser
- All credentials are saved to `/root/wp_credentials.log`

## CloudFlare Configuration

If using CloudFlare, after running this script:

1. Log in to your CloudFlare dashboard
2. Ensure your domain's A record points to your server IP
3. Set SSL/TLS encryption mode to "Full" or "Full (strict)"
4. Enable "Always Use HTTPS" for best security

## License

This project is licensed under the MIT License - see the LICENSE file for details.
