#!/bin/bash
#
# WordPress Auto-Installation Script
# GitHub: https://github.com/Sandalu123/WordPress-Auto-Installer
#
# This script automatically installs WordPress, Apache, MySQL, and PHP
# with customizable port, HTTPS options (CloudFlare, custom SSL, self-signed), and firewall settings
#

# Exit on any error
set -e

# Variables
INSTALL_DIR="/var/www/html"
DB_NAME="wp$(date +%s)"
DB_USER=$DB_NAME
DB_PASSWORD=$(date | md5sum | cut -c '1-12')
MYSQL_ROOT_PASS=$(date | md5sum | cut -c '1-12')
LOG_FILE="/root/wp_credentials.log"

# Default ports
HTTP_PORT=80
HTTPS_PORT=443
SSH_PORT=22

# Default settings
ENABLE_HTTPS=false
ENABLE_FIREWALL=false
ADDITIONAL_PORTS=""
SSL_TYPE=""
SSL_EMAIL=""
SSL_DOMAIN=""
CF_API_KEY=""
CF_EMAIL=""
CUSTOM_CERT_PATH=""
CUSTOM_KEY_PATH=""

# Console colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}This script must be run as root${NC}" 1>&2
   exit 1
fi

# Banner function
function print_banner() {
    echo -e "${GREEN}"
    echo "===================================================="
    echo "      WordPress Auto-Installation Script"
    echo "===================================================="
    echo -e "${NC}"
}

# Step function to show progress
function step() {
    echo -e "${YELLOW}➜ $1${NC}"
}

# Success function
function success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Info function
function info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Error function
function error() {
    echo -e "${RED}✗ $1${NC}"
}

# Prompt for user input with a default value
function prompt_with_default() {
    local prompt_text=$1
    local default_value=$2
    local result_var_name=$3 # Name of the variable to store result
    local input

    # Print prompt to stderr
    echo -ne "${YELLOW}${prompt_text} [${default_value}]: ${NC}" >&2

    # Read input from stdin
    read input

    # Assign the input or default value to the variable name provided using printf -v
    printf -v "$result_var_name" '%s' "${input:-$default_value}"
}

# Check if a file exists and is readable
function validate_file() {
    local file_path=$1
    local file_type=$2
    
    if [ ! -f "$file_path" ]; then
        error "$file_type file not found at $file_path"
        return 1
    fi
    
    if [ ! -r "$file_path" ]; then
        error "$file_type file is not readable at $file_path"
        return 1
    fi
    
    success "$file_type file is valid"
    return 0
}

# Validate SSL certificate files
function validate_ssl_files() {
    local valid=true
    
    step "Validating SSL certificate files..."
    
    # Validate certificate file
    if ! validate_file "$CUSTOM_CERT_PATH" "SSL certificate"; then
        valid=false
    fi
    
    # Validate key file
    if ! validate_file "$CUSTOM_KEY_PATH" "SSL private key"; then
        valid=false
    fi
    
    # If both files exist, verify they match
    if $valid; then
        step "Verifying certificate and key match..."
        
        # Get certificate modulus
        local cert_modulus=$(openssl x509 -noout -modulus -in "$CUSTOM_CERT_PATH" | openssl md5)
        
        # Get key modulus
        local key_modulus=$(openssl rsa -noout -modulus -in "$CUSTOM_KEY_PATH" | openssl md5)
        
        if [ "$cert_modulus" != "$key_modulus" ]; then
            error "Certificate and key do not match"
            valid=false
        else
            success "Certificate and key match"
        fi
    fi
    
    if [ "$valid" = true ]; then
        return 0
    else
        return 1
    fi
}

# Configure SSL options
function configure_ssl_options() {
    echo ""
    echo -e "${BLUE}HTTPS Configuration:${NC}"
    echo "Please select your SSL configuration method:"
    echo "1) Self-signed certificate (quick setup, browser warnings)"
    echo "2) CloudFlare (using CloudFlare for SSL)"
    echo "3) Let's Encrypt (free trusted certificate, needs domain)"
    echo "4) Custom SSL certificate (use existing certificate files)"
    echo ""
    
    local ssl_option
    echo -ne "${YELLOW}Enter your choice (1-4): ${NC}"
    read ssl_option
    
    case $ssl_option in
        1)
            SSL_TYPE="self-signed"
            info "Self-signed certificate will be generated automatically"
            ;;
        2)
            SSL_TYPE="cloudflare"
            
            echo ""
            info "CloudFlare configuration steps:"
            echo "1. You'll need a CloudFlare account with your domain added"
            echo "2. Your DNS records should point to this server's IP"
            echo "3. SSL/TLS encryption mode should be set to Full or Full (strict)"
            echo ""
            
            prompt_with_default "Enter your domain (e.g., example.com)" "" SSL_DOMAIN
            
            if [ -z "$SSL_DOMAIN" ]; then
                error "Domain name is required for CloudFlare setup"
                return 1
            fi
            
            info "Optional: Enter CloudFlare API credentials for automatic setup"
            prompt_with_default "Enter CloudFlare email address (optional)" "" CF_EMAIL
            
            if [ -n "$CF_EMAIL" ]; then
                echo -ne "${YELLOW}Enter CloudFlare Global API Key (input will be hidden): ${NC}"
                read -s CF_API_KEY
                echo ""
            fi
            ;;
        3)
            SSL_TYPE="letsencrypt"
            
            echo ""
            info "Let's Encrypt configuration steps:"
            echo "1. You'll need a valid domain name pointing to this server's IP"
            echo "2. Port 80 must be open to the internet for verification"
            echo ""
            
            prompt_with_default "Enter your domain (e.g., example.com)" "" SSL_DOMAIN
            
            if [ -z "$SSL_DOMAIN" ]; then
                error "Domain name is required for Let's Encrypt"
                return 1
            fi
            
            # Verify domain points to this server
            local server_ip=$(hostname -I | awk '{print $1}' | tr -d '[:space:]')
            local domain_ip=$(dig +short "$SSL_DOMAIN" || echo "")
            
            if [ -z "$domain_ip" ]; then
                error "Could not resolve domain $SSL_DOMAIN"
                info "Make sure the domain has an A record pointing to this server's IP ($server_ip)"
                info "Continuing with Let's Encrypt, but certificate generation may fail"
            elif [ "$domain_ip" != "$server_ip" ]; then
                error "Domain $SSL_DOMAIN points to $domain_ip, not to this server ($server_ip)"
                info "Make sure the domain has an A record pointing to this server's IP"
                info "Continuing with Let's Encrypt, but certificate generation may fail"
            else
                success "Domain $SSL_DOMAIN correctly points to this server"
            fi
            
            prompt_with_default "Enter email address for Let's Encrypt notices" "admin@$SSL_DOMAIN" SSL_EMAIL
            ;;
        4)
            SSL_TYPE="custom"
            
            echo ""
            info "Custom SSL certificate configuration:"
            echo "You will need to provide paths to your existing certificate and key files."
            echo ""
            
            prompt_with_default "Enter path to SSL certificate file (.crt/.pem)" "" CUSTOM_CERT_PATH
            
            if [ -z "$CUSTOM_CERT_PATH" ]; then
                error "Certificate path is required"
                return 1
            fi
            
            prompt_with_default "Enter path to SSL private key file (.key)" "" CUSTOM_KEY_PATH
            
            if [ -z "$CUSTOM_KEY_PATH" ]; then
                error "Private key path is required"
                return 1
            fi
            
            # Validate certificate files
            if ! validate_ssl_files; then
                return 1
            fi
            
            SSL_DOMAIN=$(openssl x509 -noout -subject -in "$CUSTOM_CERT_PATH" | sed -n 's/.*CN *= *\([^ ]*\).*/\1/p')
            if [ -z "$SSL_DOMAIN" ]; then
                prompt_with_default "Could not determine domain from certificate. Please enter domain name" "" SSL_DOMAIN
            else
                info "Domain from certificate: $SSL_DOMAIN"
            fi
            ;;
        *)
            error "Invalid choice. Using self-signed certificate"
            SSL_TYPE="self-signed"
            ;;
    esac
    
    return 0
}

# User configuration
function configure_user_settings() {
    print_banner
    echo "Welcome to WordPress Auto-Installer Setup"
    echo "Please provide the following configuration details:"
    echo ""
    
    # HTTP port configuration
    prompt_with_default "Which HTTP port would you like WordPress to run on" "80" HTTP_PORT
    
    # HTTPS configuration
    local https_choice
    echo -ne "${YELLOW}Would you like to enable HTTPS (y/n)? [n]: ${NC}"
    read https_choice
    if [[ "${https_choice,,}" == "y" ]]; then
        ENABLE_HTTPS=true
        prompt_with_default "Which HTTPS port would you like to use" "443" HTTPS_PORT
        
        # Configure SSL options
        configure_ssl_options || {
            error "SSL configuration failed. Disabling HTTPS."
            ENABLE_HTTPS=false
        }
    fi
    
    # Firewall configuration
    local firewall_choice
    echo -ne "${YELLOW}Would you like to enable and configure the firewall (y/n)? [n]: ${NC}"
    read firewall_choice
    if [[ "${firewall_choice,,}" == "y" ]]; then
        ENABLE_FIREWALL=true
        prompt_with_default "Which SSH port would you like to keep open" "22" SSH_PORT
        
        # Additional ports
        echo -ne "${YELLOW}Please enter any additional ports to open (comma-separated, e.g., 25,8080) or press Enter for none: ${NC}"
        read ADDITIONAL_PORTS
    fi
    
    # Show configuration summary
    echo ""
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "• WordPress HTTP port: $HTTP_PORT"
    if $ENABLE_HTTPS; then
        echo "• HTTPS enabled on port: $HTTPS_PORT"
        echo "• SSL Type: $SSL_TYPE"
        if [ -n "$SSL_DOMAIN" ]; then
            echo "• Domain: $SSL_DOMAIN"
        fi
    else
        echo "• HTTPS: Disabled"
    fi
    
    if $ENABLE_FIREWALL; then
        echo "• Firewall: Enabled"
        echo "• SSH port: $SSH_PORT"
        echo "• WordPress port(s): $HTTP_PORT" 
        if $ENABLE_HTTPS; then
            echo "• HTTPS port: $HTTPS_PORT"
        fi
        if [[ -n "$ADDITIONAL_PORTS" ]]; then
            echo "• Additional ports: $ADDITIONAL_PORTS"
        fi
    else
        echo "• Firewall: Disabled"
    fi
    
    echo ""
    local confirm
    echo -ne "${YELLOW}Proceed with installation using these settings (y/n)? [y]: ${NC}"
    read confirm
    if [[ "${confirm,,}" == "n" ]]; then
        echo "Installation aborted. Please run the script again to configure."
        exit 0
    fi
}

# Save credentials
function save_credentials() {
    cat << EOF > $LOG_FILE
==================================================
    WordPress Installation Credentials
==================================================
Installation Date: $(date)
Server IP: $(hostname -I | awk '{print $1}')

Database Name: $DB_NAME
Database User: $DB_USER
Database Password: $DB_PASSWORD
MySQL Root Password: $MYSQL_ROOT_PASS

WordPress URL: http://$(hostname -I | awk '{print $1}' | tr -d '[:space:]'):$HTTP_PORT/
WordPress Admin URL: http://$(hostname -I | awk '{print $1}' | tr -d '[:space:]'):$HTTP_PORT/wp-admin/

Server Configuration:
- HTTP Port: $HTTP_PORT
EOF

    if $ENABLE_HTTPS; then
        cat << EOF >> $LOG_FILE
- HTTPS Enabled on port: $HTTPS_PORT
- SSL Type: $SSL_TYPE
EOF

        if [ -n "$SSL_DOMAIN" ]; then
            echo "- Domain: $SSL_DOMAIN" >> $LOG_FILE
            echo "- Secure URL: https://$SSL_DOMAIN:$HTTPS_PORT/" >> $LOG_FILE
        else
            echo "- Secure URL: https://$(hostname -I | awk '{print $1}' | tr -d '[:space:]'):$HTTPS_PORT/" >> $LOG_FILE
        fi
    fi

    if $ENABLE_FIREWALL; then
        cat << EOF >> $LOG_FILE
- Firewall: Enabled
- Open ports: $SSH_PORT (SSH), $HTTP_PORT (HTTP)
EOF
        if $ENABLE_HTTPS; then
            echo "               $HTTPS_PORT (HTTPS)" >> $LOG_FILE
        fi
        if [[ -n "$ADDITIONAL_PORTS" ]]; then
            echo "               $ADDITIONAL_PORTS (Additional)" >> $LOG_FILE
        fi
    else
        echo "- Firewall: Disabled" >> $LOG_FILE
    fi

    echo "==================================================" >> $LOG_FILE
    chmod 600 $LOG_FILE
    success "Credentials saved to $LOG_FILE"
}

# Install packages
function install_packages() {
    step "Updating system packages..."
    apt -y update
    apt -y upgrade
    
    step "Installing Apache web server..."
    apt -y install apache2
    
    step "Installing MySQL database server..."
    apt -y install mysql-server
    
    step "Installing PHP and required extensions..."
    apt -y install php php-bz2 php-mysqli php-curl php-gd php-intl php-common php-mbstring php-xml
    
    if $ENABLE_HTTPS; then
        step "Installing SSL packages..."
        apt -y install openssl
        
        case $SSL_TYPE in
            letsencrypt)
                apt -y install certbot python3-certbot-apache
                ;;
            cloudflare)
                apt -y install dnsutils
                if [ -n "$CF_API_KEY" ] && [ -n "$CF_EMAIL" ]; then
                    apt -y install python3-pip
                    pip3 install cloudflare
                fi
                ;;
        esac
    fi
    
    if $ENABLE_FIREWALL; then
        step "Installing firewall package..."
        apt -y install ufw
    fi
    
    # Install additional utilities
    apt -y install dnsutils curl wget
    
    success "All packages installed successfully"
}

# Configure Apache
function configure_apache() {
    step "Configuring Apache web server..."
    
    # Remove default index.html if it exists
    if [ -f $INSTALL_DIR/index.html ]; then
        rm $INSTALL_DIR/index.html
    fi
    
    # Enable mod_rewrite
    a2enmod rewrite
    
    # Configure port if not default
    if [ "$HTTP_PORT" != "80" ]; then
        step "Configuring Apache to listen on port $HTTP_PORT..."
        
        # Update ports.conf
        sed -i "s/Listen 80/Listen $HTTP_PORT/" /etc/apache2/ports.conf
        
        # Update default virtual host
        sed -i "s/*:80/*:$HTTP_PORT/" /etc/apache2/sites-available/000-default.conf
    fi
    
    # Configure .htaccess usage
    sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
    
    # If using a domain, create a virtual host
    if $ENABLE_HTTPS && [ -n "$SSL_DOMAIN" ]; then
        step "Creating virtual host for $SSL_DOMAIN..."
        
        cat << EOF > "/etc/apache2/sites-available/$SSL_DOMAIN.conf"
<VirtualHost *:$HTTP_PORT>
    ServerAdmin webmaster@$SSL_DOMAIN
    ServerName $SSL_DOMAIN
    DocumentRoot $INSTALL_DIR

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <Directory $INSTALL_DIR>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
        
        echo "DEBUG: SSL_DOMAIN value before a2ensite: [$SSL_DOMAIN]" >&2
        a2ensite "$SSL_DOMAIN"
        a2dissite 000-default
    fi
    
    # Enable and start Apache
    systemctl enable apache2
    systemctl restart apache2
    
    success "Apache configured successfully"
}

# Configure HTTPS with CloudFlare
function configure_cloudflare() {
    step "Configuring CloudFlare SSL..."
    
    if [ -n "$CF_API_KEY" ] && [ -n "$CF_EMAIL" ]; then
        info "Attempting to configure CloudFlare automatically..."
        
        # This would require a more complex Python script to interact with CloudFlare API
        # For simplicity, we'll provide instructions instead
        
        info "Automatic CloudFlare setup is beyond the scope of this script"
    fi
    
    info "Please follow these steps in your CloudFlare dashboard:"
    echo "1. Log in to your CloudFlare account"
    echo "2. Select your domain: $SSL_DOMAIN"
    echo "3. Go to SSL/TLS section"
    echo "4. Set SSL/TLS encryption mode to 'Full' or 'Full (strict)'"
    echo "5. Ensure your DNS records point to this server: $(hostname -I | awk '{print $1}' | tr -d '[:space:]')"
    
    # Configure Apache for CloudFlare
    a2enmod ssl
    a2enmod headers
    
    # SSL config for Apache
    cat << EOF > /etc/apache2/sites-available/$SSL_DOMAIN-ssl.conf
<IfModule mod_ssl.c>
    <VirtualHost *:$HTTPS_PORT>
        ServerAdmin webmaster@$SSL_DOMAIN
        ServerName $SSL_DOMAIN
        DocumentRoot $INSTALL_DIR

        ErrorLog \${APACHE_LOG_DIR}/error-ssl.log
        CustomLog \${APACHE_LOG_DIR}/access-ssl.log combined

        SSLEngine on
        SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
        SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key
        
        # Add CloudFlare headers
        RequestHeader set X-Forwarded-Proto "https"
        
        <Directory $INSTALL_DIR>
            Options FollowSymLinks
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>
</IfModule>
EOF
    
    # Generate self-signed certificate for origin
    mkdir -p /etc/ssl/private
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/apache-selfsigned.key \
        -out /etc/ssl/certs/apache-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$SSL_DOMAIN"
    
    a2ensite $SSL_DOMAIN-ssl
    
    # Add CloudFlare IP ranges to Apache config
    step "Adding CloudFlare IP ranges to Apache configuration..."
    
    cat << EOF > /etc/apache2/conf-available/cloudflare.conf
# CloudFlare IP Ranges
# IPv4
RemoteIPHeader CF-Connecting-IP
RemoteIPTrustedProxy 173.245.48.0/20
RemoteIPTrustedProxy 103.21.244.0/22
RemoteIPTrustedProxy 103.22.200.0/22
RemoteIPTrustedProxy 103.31.4.0/22
RemoteIPTrustedProxy 141.101.64.0/18
RemoteIPTrustedProxy 108.162.192.0/18
RemoteIPTrustedProxy 190.93.240.0/20
RemoteIPTrustedProxy 188.114.96.0/20
RemoteIPTrustedProxy 197.234.240.0/22
RemoteIPTrustedProxy 198.41.128.0/17
RemoteIPTrustedProxy 162.158.0.0/15
RemoteIPTrustedProxy 172.64.0.0/13
RemoteIPTrustedProxy 131.0.72.0/22

# IPv6
RemoteIPTrustedProxy 2400:cb00::/32
RemoteIPTrustedProxy 2606:4700::/32
RemoteIPTrustedProxy 2803:f800::/32
RemoteIPTrustedProxy 2405:b500::/32
RemoteIPTrustedProxy 2405:8100::/32
RemoteIPTrustedProxy 2a06:98c0::/29
RemoteIPTrustedProxy 2c0f:f248::/32
EOF
    
    a2enmod remoteip
    a2enconf cloudflare
    
    success "CloudFlare origin SSL configured"
    info "Use the CloudFlare dashboard to complete the setup"
}

# Configure HTTPS with Let's Encrypt
function configure_letsencrypt() {
    step "Configuring Let's Encrypt SSL..."
    
    # Stop Apache temporarily to allow certbot to bind to port 80
    systemctl stop apache2
    
    # Get certificate with certbot
    certbot certonly --standalone --non-interactive --agree-tos \
        --email "$SSL_EMAIL" --domains "$SSL_DOMAIN" \
        --preferred-challenges http
    
    local cert_status=$?
    
    # Start Apache again
    systemctl start apache2
    
    if [ $cert_status -ne 0 ]; then
        error "Let's Encrypt certificate generation failed"
        info "Check that your domain ($SSL_DOMAIN) points to this server and port 80 is open"
        return 1
    fi
    
    # Create SSL virtual host
    cat << EOF > /etc/apache2/sites-available/$SSL_DOMAIN-ssl.conf
<IfModule mod_ssl.c>
    <VirtualHost *:$HTTPS_PORT>
        ServerAdmin webmaster@$SSL_DOMAIN
        ServerName $SSL_DOMAIN
        DocumentRoot $INSTALL_DIR

        ErrorLog \${APACHE_LOG_DIR}/error-ssl.log
        CustomLog \${APACHE_LOG_DIR}/access-ssl.log combined

        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/$SSL_DOMAIN/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/$SSL_DOMAIN/privkey.pem
        
        <Directory $INSTALL_DIR>
            Options FollowSymLinks
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>
</IfModule>
EOF
    
    a2enmod ssl
    a2ensite $SSL_DOMAIN-ssl
    
    # Set up auto renewal
    step "Setting up certificate auto-renewal..."
    echo "0 3 * * * root certbot renew --quiet --post-hook 'systemctl reload apache2'" > /etc/cron.d/certbot-renew
    
    success "Let's Encrypt SSL configured successfully"
}

# Configure HTTPS with self-signed certificate
function configure_selfsigned() {
    step "Configuring self-signed SSL certificate..."
    
    # Generate self-signed certificate
    mkdir -p /etc/ssl/private
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/apache-selfsigned.key \
        -out /etc/ssl/certs/apache-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$(hostname -I | awk '{print $1}' | tr -d '[:space:]')"
    
    # Create SSL virtual host
    local server_name
    if [ -n "$SSL_DOMAIN" ]; then
        server_name="ServerName $SSL_DOMAIN"
    else
        server_name="# ServerName not specified"
    fi
    
    cat << EOF > /etc/apache2/sites-available/default-ssl.conf
<IfModule mod_ssl.c>
    <VirtualHost *:$HTTPS_PORT>
        ServerAdmin webmaster@localhost
        $server_name
        DocumentRoot $INSTALL_DIR

        ErrorLog \${APACHE_LOG_DIR}/error-ssl.log
        CustomLog \${APACHE_LOG_DIR}/access-ssl.log combined

        SSLEngine on
        SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
        SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key
        
        <Directory $INSTALL_DIR>
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>
</IfModule>
EOF
    
    a2enmod ssl
    a2ensite default-ssl
    
    success "Self-signed SSL certificate configured"
    info "Note: Browsers will show a warning about the self-signed certificate. This is normal."
}

# Configure HTTPS with custom certificate
function configure_custom_ssl() {
    step "Configuring custom SSL certificate..."
    
    # Create directory structure if it doesn't exist
    mkdir -p /etc/ssl/private
    
    # Copy certificate files to standard locations
    cp "$CUSTOM_CERT_PATH" /etc/ssl/certs/custom-cert.pem
    cp "$CUSTOM_KEY_PATH" /etc/ssl/private/custom-key.pem
    
    # Set proper permissions
    chmod 644 /etc/ssl/certs/custom-cert.pem
    chmod 600 /etc/ssl/private/custom-key.pem
    
    # Create SSL virtual host
    local server_name
    if [ -n "$SSL_DOMAIN" ]; then
        server_name="ServerName $SSL_DOMAIN"
    else
        server_name="# ServerName not specified"
    fi
    
    cat << EOF > /etc/apache2/sites-available/custom-ssl.conf
<IfModule mod_ssl.c>
    <VirtualHost *:$HTTPS_PORT>
        ServerAdmin webmaster@localhost
        $server_name
        DocumentRoot $INSTALL_DIR

        ErrorLog \${APACHE_LOG_DIR}/error-ssl.log
        CustomLog \${APACHE_LOG_DIR}/access-ssl.log combined

        SSLEngine on
        SSLCertificateFile /etc/ssl/certs/custom-cert.pem
        SSLCertificateKeyFile /etc/ssl/private/custom-key.pem
        
        <Directory $INSTALL_DIR>
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>
</IfModule>
EOF
    
    a2enmod ssl
    a2ensite custom-ssl
    
    success "Custom SSL certificate configured"
}

# Configure HTTPS
function configure_https() {
    if $ENABLE_HTTPS; then
        step "Configuring HTTPS..."
        
        # Update ports.conf for HTTPS if non-standard port
        if [ "$HTTPS_PORT" != "443" ]; then
            if grep -q "Listen 443" /etc/apache2/ports.conf; then
                sed -i "s/Listen 443/Listen $HTTPS_PORT/" /etc/apache2/ports.conf
            else
                echo "Listen $HTTPS_PORT" >> /etc/apache2/ports.conf
            fi
        fi
        
        # Configure SSL based on selected type
        case $SSL_TYPE in
            cloudflare)
                configure_cloudflare
                ;;
            letsencrypt)
                configure_letsencrypt
                ;;
            custom)
                configure_custom_ssl
                ;;
            self-signed|*)
                configure_selfsigned
                ;;
        esac
        
        # Restart Apache to apply changes
        systemctl restart apache2
    fi
}

# Configure Firewall
function configure_firewall() {
    if $ENABLE_FIREWALL; then
        step "Configuring firewall..."
        
        # Reset firewall rules
        ufw --force reset
        
        # Default policies
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH
        ufw allow $SSH_PORT/tcp comment 'SSH'
        
        # Allow WordPress HTTP
        ufw allow $HTTP_PORT/tcp comment 'WordPress HTTP'
        
        # Allow WordPress HTTPS if enabled
        if $ENABLE_HTTPS; then
            ufw allow $HTTPS_PORT/tcp comment 'WordPress HTTPS'
        fi
        
        # Allow additional ports if specified
        if [[ -n "$ADDITIONAL_PORTS" ]]; then
            IFS=',' read -ra PORTS <<< "$ADDITIONAL_PORTS"
            for port in "${PORTS[@]}"; do
                ufw allow ${port}/tcp comment 'Custom port'
            done
        fi
        
        # Enable firewall
        ufw --force enable
        
        success "Firewall configured and enabled"
    fi
}

# Configure MySQL
function configure_mysql() {
    step "Configuring MySQL database server..."
    
    # Start MySQL
    systemctl enable mysql
    systemctl start mysql
    
    # Check if MySQL is already secured (root password set)
    if mysql -u root -e "SELECT 1" &>/dev/null; then
        # Root has no password, set it
        mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS';"
        mysql -e "FLUSH PRIVILEGES;"
    else
        # Root already has a password, prompt for it
        local current_pass
        echo -ne "${YELLOW}Enter current MySQL root password: ${NC}"
        read -s current_pass
        echo ""
        
        # Verify password works
        if ! mysql -u root -p"$current_pass" -e "SELECT 1" &>/dev/null; then
            error "Invalid MySQL root password. Please run the script again with the correct password."
            exit 1
        fi
        
        # Set new root password
        mysql -u root -p"$current_pass" -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASS';"
        mysql -u root -p"$current_pass" -e "FLUSH PRIVILEGES;"
    fi
    
    # Create MySQL config for root
    touch /root/.my.cnf
    chmod 640 /root/.my.cnf
    cat << EOF > /root/.my.cnf
[client]
user=root
password=$MYSQL_ROOT_PASS
EOF
    
    # Use the .my.cnf file for authentication in future commands
    
    # Create WordPress database and user
    mysql -e "CREATE DATABASE $DB_NAME;"
    mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_PASSWORD';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    
    success "MySQL configured successfully"
}

# Install WordPress
function install_wordpress() {
    step "Downloading and installing WordPress..."
    
    # Download latest WordPress
    if [ -f /tmp/latest.tar.gz ]; then
        echo "WordPress is already downloaded"
    else
        cd /tmp/ && wget "https://wordpress.org/latest.tar.gz"
    fi
    
    # Clean install directory and extract WordPress
    rm -rf $INSTALL_DIR/*
    tar -C $INSTALL_DIR -zxf /tmp/latest.tar.gz --strip-components=1
    
    # Set proper ownership
    chown www-data:www-data $INSTALL_DIR -R
    
    success "WordPress downloaded and extracted"
}

# Configure WordPress
function configure_wordpress() {
    step "Configuring WordPress..."
    
    # Create and configure wp-config.php
    cp $INSTALL_DIR/wp-config-sample.php $INSTALL_DIR/wp-config.php
    
    # Update database settings
    sed -i "s/database_name_here/$DB_NAME/g" $INSTALL_DIR/wp-config.php
    sed -i "s/username_here/$DB_USER/g" $INSTALL_DIR/wp-config.php
    sed -i "s/password_here/$DB_PASSWORD/g" $INSTALL_DIR/wp-config.php
    
    # Add direct filesystem method
    sed -i "/That's all, stop editing/i define('FS_METHOD', 'direct');" $INSTALL_DIR/wp-config.php
    
    # If HTTPS is enabled with domain, configure WordPress site URL
    if $ENABLE_HTTPS && [ -n "$SSL_DOMAIN" ]; then
        local site_url
        if [ "$HTTPS_PORT" == "443" ]; then
            site_url="https://$SSL_DOMAIN"
        else
            site_url="https://$SSL_DOMAIN:$HTTPS_PORT"
        fi
        
        sed -i "/That's all, stop editing/i define('WP_SITEURL', '$site_url');" $INSTALL_DIR/wp-config.php
        sed -i "/That's all, stop editing/i define('WP_HOME', '$site_url');" $INSTALL_DIR/wp-config.php
        
        if [ "$SSL_TYPE" == "cloudflare" ]; then
            # Add CloudFlare settings
            sed -i "/That's all, stop editing/i if (isset(\$_SERVER['HTTP_CF_VISITOR']) && strpos(\$_SERVER['HTTP_CF_VISITOR'], 'https') !== false) { \$_SERVER['HTTPS'] = 'on'; }" $INSTALL_DIR/wp-config.php
        else
            # Standard HTTPS settings
            sed -i "/That's all, stop editing/i define('FORCE_SSL_ADMIN', true);" $INSTALL_DIR/wp-config.php
        fi
    fi
    
    # Generate and add security salts
    step "Generating security keys..."
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    sed -i "/put your unique phrase here/d" $INSTALL_DIR/wp-config.php
    printf '%s\n' "$(awk '/AUTH_KEY/,/NONCE_SALT/ {print $0}' $INSTALL_DIR/wp-config.php)" | sed -i -e '/put your unique phrase here/d' $INSTALL_DIR/wp-config.php
    sed -i "/#@-/a $SALTS" $INSTALL_DIR/wp-config.php
    
    # Create .htaccess for pretty permalinks
    cat << EOF > $INSTALL_DIR/.htaccess
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
EOF
    
    # If using CloudFlare, add CloudFlare specific .htaccess rules
    if [ "$SSL_TYPE" == "cloudflare" ]; then
        cat << EOF >> $INSTALL_DIR/.htaccess

# BEGIN CloudFlare
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{HTTP:CF-Visitor} '"scheme":"https"'
    RewriteRule ^(.*)$ https://%{HTTP_HOST}/$1 [L]
</IfModule>
# END CloudFlare
EOF
    fi
    
    # Set final permissions
    chown www-data:www-data $INSTALL_DIR -R
    find $INSTALL_DIR -type d -exec chmod 755 {} \;
    find $INSTALL_DIR -type f -exec chmod 644 {} \;
    
    success "WordPress installed and configured successfully"
}

# Main installation function
function install() {
    # Get user configuration
    configure_user_settings
    
    # Start installation
    step "Starting WordPress installation..."
    
    # Install required packages
    install_packages
    
    # Configure Apache
    configure_apache
    
    # Configure HTTPS if enabled
    if $ENABLE_HTTPS; then
        configure_https
    fi
    
    # Configure MySQL
    configure_mysql
    
    # Install WordPress
    install_wordpress
    
    # Configure WordPress
    configure_wordpress
    
    # Configure firewall if enabled
    if $ENABLE_FIREWALL; then
        configure_firewall
    fi
    
    # Save credentials
    save_credentials
    
    # Installation complete
    echo ""
    echo -e "${GREEN}===================================================="
    echo "      WordPress Installation Complete!"
    echo "====================================================${NC}"
    echo ""
    echo -e "${BLUE}WordPress URL:${NC} http://$(hostname -I | awk '{print $1}' | tr -d '[:space:]'):$HTTP_PORT/"
    
    if $ENABLE_HTTPS; then
        if [ -n "$SSL_DOMAIN" ]; then
            echo -e "${BLUE}Secure URL:${NC} https://$SSL_DOMAIN:$HTTPS_PORT/"
        else
            echo -e "${BLUE}Secure URL:${NC} https://$(hostname -I | awk '{print $1}' | tr -d '[:space:]'):$HTTPS_PORT/"
        fi
    fi
    
    echo -e "${BLUE}WordPress Admin:${NC} http://$(hostname -I | awk '{print $1}' | tr -d '[:space:]'):$HTTP_PORT/wp-admin/"
    echo -e "${BLUE}Credentials:${NC} Saved to $LOG_FILE"
    echo ""
}

# Execute the script
install
