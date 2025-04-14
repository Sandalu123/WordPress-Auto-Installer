# Linux & Windows Server Tools

This repository contains useful scripts for managing server environments on both Linux and Windows.

- **Linux:** An interactive Bash script for automatically installing and configuring WordPress with multiple SSL options, custom port configuration, and firewall settings.
- **Windows:** A PowerShell-based text UI tool for managing MySQL installations (service control, database/table/user listing, backups, restores, root password reset).

---

## 1. Linux: WordPress Auto-Installer

An interactive Bash script that automatically installs and configures WordPress on Debian/Ubuntu-based systems.

### Features

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

### Requirements

- Ubuntu or Debian-based Linux distribution
- Root access
- Internet connection
- Domain name (required for Let's Encrypt and recommended for CloudFlare)

### Quick Install (Run from URL)

Execute directly from GitHub (requires `curl`):

```bash
curl -L https://raw.githubusercontent.com/Sandalu123/MiniTools/refs/heads/main/Linux/auto-install-wordpress.sh | sudo bash
```

### Manual Installation

```bash
# Clone repository
git clone https://github.com/Sandalu123/WordPress-Auto-Installer.git

# Navigate to directory
cd WordPress-Auto-Installer/Linux

# Make script executable
chmod +x auto-install-wordpress.sh

# Run script as root
sudo ./auto-install-wordpress.sh
```

### SSL Configuration Options

(Details on Self-signed, CloudFlare, Let's Encrypt, Custom SSL - *same as original README*)

### Firewall Configuration

(Details on UFW configuration - *same as original README*)

### What It Does

(Details on the installation steps - *same as original README*)

### After Installation

(Details on accessing WordPress and credentials file - *same as original README*)

### CloudFlare Configuration

(Post-installation steps for CloudFlare - *same as original README*)

---

## 2. Windows: MySQL Management Tool

A text-based UI tool built with PowerShell for managing MySQL databases on Windows.

### Features

- **Auto-detect MySQL**: Finds common MySQL installation paths (Program Files, XAMPP, WAMP, Laragon).
- **Service Management**: Start, stop, restart, and check the status of the MySQL service.
- **User Management**: List MySQL users.
- **Database Management**:
    - List databases.
    - Create new databases.
    - Delete databases.
- **Table Management**: List tables within a selected database.
- **Backup & Restore**:
    - Backup individual databases.
    - Backup all databases.
    - Restore databases from `.sql` files.
- **Root Password Reset**: Utility to reset the MySQL root password using the `init-file` method.
- **Credential Testing**: Verify MySQL connection credentials.
- **Custom MySQL Path**: Option to specify a custom path to your MySQL installation.

### Requirements

- Windows Operating System
- PowerShell (usually included with Windows)
- MySQL installed on the system

### Quick Run (Run from URL)

Execute directly from GitHub using PowerShell:

```powershell
Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Sandalu123/MiniTools/refs/heads/main/Windows/mysql-manager.ps1')
```
*Note: You might need to adjust PowerShell execution policies (`Set-ExecutionPolicy`) if you encounter issues running scripts downloaded from the internet.*

### Manual Run

```powershell
# Clone repository (using Git or download ZIP)
git clone https://github.com/Sandalu123/WordPress-Auto-Installer.git

# Navigate to directory in PowerShell
cd WordPress-Auto-Installer\Windows

# Run the script
.\mysql-manager.ps1

# Optional: Specify a custom MySQL path
.\mysql-manager.ps1 -CustomPath "C:\path\to\your\mysql"
```

---

## License

This project is licensed under the MIT License.
