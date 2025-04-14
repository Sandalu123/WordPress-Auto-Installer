# MySQL Management Tool
# Author: Sandalu Pabasara Perera
# Description: A text-based UI for MySQL database management

param (
    [string]$CustomPath = ""
)

function Show-Header {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "          MySQL Database Management Tool       " -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Menu {
    param (
        [string]$Title,
        [array]$Options,
        [int]$DefaultOption = 0
    )
    
    Write-Host "$Title" -ForegroundColor Green
    Write-Host "-----------------------------------------------" -ForegroundColor Green
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        if ($i -eq $DefaultOption) {
            Write-Host "  [$($i+1)] $($Options[$i]) " -ForegroundColor Yellow -NoNewline
            Write-Host "(Default)" -ForegroundColor DarkYellow
        } else {
            Write-Host "  [$($i+1)] $($Options[$i])" -ForegroundColor White
        }
    }
    
    Write-Host "-----------------------------------------------" -ForegroundColor Green
    Write-Host "Select an option (1-$($Options.Count)): " -ForegroundColor Green -NoNewline
    
    $choice = Read-Host
    
    if ([string]::IsNullOrEmpty($choice)) {
        return $DefaultOption
    }
    
    try {
        $choiceNum = [int]$choice - 1
        if ($choiceNum -ge 0 -and $choiceNum -lt $Options.Count) {
            return $choiceNum
        } else {
            Write-Host "Invalid choice. Using default option." -ForegroundColor Red
            Start-Sleep -Seconds 1
            return $DefaultOption
        }
    } catch {
        Write-Host "Invalid input. Using default option." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return $DefaultOption
    }
}

function Get-MySQLInstallations {
    $mysqlPaths = @(
        "C:\Program Files\MySQL\MySQL Server 8.0",
        "C:\Program Files\MySQL\MySQL Server 5.7",
        "C:\Program Files\MySQL\MySQL Server 5.6",
        "C:\xampp\mysql",
        "C:\wamp\bin\mysql",
        "C:\wamp64\bin\mysql",
        "C:\laragon\bin\mysql"
    )
    
    $foundPaths = @()
    
    foreach ($path in $mysqlPaths) {
        if (Test-Path -Path "$path\bin\mysql.exe") {
            $foundPaths += $path
        }
    }
    
    return $foundPaths
}

function Test-Credentials {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    try {
        $cmdArgs = "--user=`"$Username`""
        if ($Password) {
            $cmdArgs += " --password=`"$Password`""
        }
        $cmdArgs += " --execute=`"SELECT 1;`""
        
        $process = Start-Process -FilePath "$MySQLPath\bin\mysql.exe" -ArgumentList $cmdArgs -NoNewWindow -PassThru -Wait
        return ($process.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Invoke-MySQLCommand {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password,
        [string]$Command,
        [string]$Database = "",
        [int]$MaxRetries = 3
    )
    
    $retry = 0
    $success = $false
    
    while (-not $success -and $retry -lt $MaxRetries) {
        try {
            $cmdArgs = "--user=`"$Username`""
            if ($Password) {
                $cmdArgs += " --password=`"$Password`""
            }
            if ($Database) {
                $cmdArgs += " --database=`"$Database`""
            }
            $cmdArgs += " --execute=`"$Command`""
            
            $process = Start-Process -FilePath "$MySQLPath\bin\mysql.exe" -ArgumentList $cmdArgs -NoNewWindow -PassThru -Wait
            $success = ($process.ExitCode -eq 0)
            
            if (-not $success) {
                $retry++
                Write-Host "Command failed. Retrying ($retry/$MaxRetries)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
        catch {
            $retry++
            Write-Host "Error: $_" -ForegroundColor Red
            Write-Host "Retrying ($retry/$MaxRetries)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
    
    return $success
}

function Get-MySQLDatabases {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    $output = & "$MySQLPath\bin\mysql.exe" --user="$Username" --password="$Password" --execute="SHOW DATABASES;" --skip-column-names 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        return ($output -split "`n" | Where-Object { $_ -ne "" -and $_ -ne "information_schema" -and $_ -ne "performance_schema" -and $_ -ne "mysql" -and $_ -ne "sys" })
    } else {
        return @()
    }
}

function Get-MySQLTables {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password,
        [string]$Database
    )
    
    $output = & "$MySQLPath\bin\mysql.exe" --user="$Username" --password="$Password" --database="$Database" --execute="SHOW TABLES;" --skip-column-names 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        return ($output -split "`n" | Where-Object { $_ -ne "" })
    } else {
        return @()
    }
}

function Get-MySQLUsers {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    $output = & "$MySQLPath\bin\mysql.exe" --user="$Username" --password="$Password" --execute="SELECT CONCAT(user, '@', host) FROM mysql.user;" --skip-column-names 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        return ($output -split "`n" | Where-Object { $_ -ne "" })
    } else {
        return @()
    }
}

function Manage-MySQLService {
    param (
        [string]$MySQLPath,
        [string]$Action
    )
    
    $serviceName = Get-Service | Where-Object { $_.Name -like "MySQL*" -or $_.Name -like "mysql*" } | Select-Object -First 1 -ExpandProperty Name
    
    if (-not $serviceName) {
        $binPath = "$MySQLPath\bin\mysqld.exe"
        if (Test-Path $binPath) {
            $serviceName = "MySQL"
        } else {
            Write-Host "MySQL service not found!" -ForegroundColor Red
            return $false
        }
    }
    
    try {
        switch ($Action) {
            "status" {
                $service = Get-Service -Name $serviceName
                return $service.Status
            }
            "stop" {
                Stop-Service -Name $serviceName -Force
                Write-Host "MySQL service stopped." -ForegroundColor Green
                return $true
            }
            "start" {
                Start-Service -Name $serviceName
                Write-Host "MySQL service started." -ForegroundColor Green
                return $true
            }
            "restart" {
                Restart-Service -Name $serviceName -Force
                Write-Host "MySQL service restarted." -ForegroundColor Green
                return $true
            }
        }
    } catch {
        Write-Host "Error managing MySQL service: $_" -ForegroundColor Red
        return $false
    }
}

function Reset-RootPassword {
    param (
        [string]$MySQLPath
    )
    
    Show-Header
    Write-Host "Reset MySQL Root Password" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------" -ForegroundColor Yellow
    
    $newPassword = Read-Host "Enter new root password"
    
    if ([string]::IsNullOrEmpty($newPassword)) {
        Write-Host "Password cannot be empty!" -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return
    }
    
    $initFile = [System.IO.Path]::GetTempFileName()
    "ALTER USER 'root'@'localhost' IDENTIFIED BY '$newPassword';" | Out-File -FilePath $initFile -Encoding ASCII
    "FLUSH PRIVILEGES;" | Out-File -FilePath $initFile -Encoding ASCII -Append
    
    Write-Host "Stopping MySQL service..." -ForegroundColor Yellow
    Manage-MySQLService -MySQLPath $MySQLPath -Action "stop"
    
    Write-Host "Starting MySQL in safe mode to reset password..." -ForegroundColor Yellow
    $safeProcess = Start-Process -FilePath "$MySQLPath\bin\mysqld.exe" -ArgumentList "--skip-grant-tables --init-file=`"$initFile`"" -NoNewWindow -PassThru
    
    Write-Host "Waiting for password reset to complete..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    Write-Host "Stopping MySQL safe mode..." -ForegroundColor Yellow
    Stop-Process -Id $safeProcess.Id -Force
    
    Write-Host "Starting MySQL service normally..." -ForegroundColor Yellow
    Manage-MySQLService -MySQLPath $MySQLPath -Action "start"
    
    Remove-Item -Path $initFile -Force
    
    Write-Host "Password reset completed successfully!" -ForegroundColor Green
    Write-Host "New root password is: $newPassword" -ForegroundColor Green
    
    Read-Host "Press Enter to continue"
}

function Manage-Users {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    $continueManagingUsers = $true
    
    while ($continueManagingUsers) {
        Show-Header
        Write-Host "MySQL User Management" -ForegroundColor Yellow
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow
        
        $users = Get-MySQLUsers -MySQLPath $MySQLPath -Username $Username -Password $Password
        
        if ($users.Count -gt 0) {
            Write-Host "Current MySQL Users:" -ForegroundColor Cyan
            foreach ($user in $users) {
                Write-Host "  - $user" -ForegroundColor White
            }
        } else {
            Write-Host "Failed to retrieve users or no users found." -ForegroundColor Red
        }
        
        Write-Host ""
        $userOptions = @(
            "Create New User",
            "Change User Password",
            "Delete User",
            "Return to Main Menu"
        )
        
        $userChoice = Show-Menu -Title "User Management Options" -Options $userOptions -DefaultOption 0
        
        switch ($userChoice) {
            0 { # Create New User
                $newUsername = Read-Host "Enter new username"
                $newHost = Read-Host "Enter host (default: localhost)"
                if ([string]::IsNullOrEmpty($newHost)) {
                    $newHost = "localhost"
                }
                $newPassword = Read-Host "Enter password for the new user"
                
                $createUserCmd = "CREATE USER '$newUsername'@'$newHost' IDENTIFIED BY '$newPassword';"
                $grantCmd = "GRANT ALL PRIVILEGES ON *.* TO '$newUsername'@'$newHost' WITH GRANT OPTION;"
                
                $success = Invoke-MySQLCommand -MySQLPath $MySQLPath -Username $Username -Password $Password -Command "$createUserCmd $grantCmd FLUSH PRIVILEGES;"
                
                if ($success) {
                    Write-Host "User '$newUsername'@'$newHost' created successfully!" -ForegroundColor Green
                } else {
                    Write-Host "Failed to create user." -ForegroundColor Red
                }
                
                Read-Host "Press Enter to continue"
            }
            1 { # Change User Password
                if ($users.Count -gt 0) {
                    $targetUser = Read-Host "Enter user to change password for (format: user@host)"
                    $newPassword = Read-Host "Enter new password"
                    
                    $userParts = $targetUser -split '@'
                    if ($userParts.Count -eq 2) {
                        $targetUsername = $userParts[0]
                        $targetHost = $userParts[1]
                        
                        $alterUserCmd = "ALTER USER '$targetUsername'@'$targetHost' IDENTIFIED BY '$newPassword';"
                        
                        $success = Invoke-MySQLCommand -MySQLPath $MySQLPath -Username $Username -Password $Password -Command "$alterUserCmd FLUSH PRIVILEGES;"
                        
                        if ($success) {
                            Write-Host "Password for '$targetUser' changed successfully!" -ForegroundColor Green
                        } else {
                            Write-Host "Failed to change password." -ForegroundColor Red
                        }
                    } else {
                        Write-Host "Invalid user format. Use the format 'user@host'." -ForegroundColor Red
                    }
                } else {
                    Write-Host "No users available to modify." -ForegroundColor Red
                }
                
                Read-Host "Press Enter to continue"
            }
            2 { # Delete User
                if ($users.Count -gt 0) {
                    $targetUser = Read-Host "Enter user to delete (format: user@host)"
                    
                    $userParts = $targetUser -split '@'
                    if ($userParts.Count -eq 2) {
                        $targetUsername = $userParts[0]
                        $targetHost = $userParts[1]
                        
                        $confirmation = Read-Host "Are you sure you want to delete '$targetUser'? (y/n)"
                        
                        if ($confirmation -eq "y") {
                            $dropUserCmd = "DROP USER '$targetUsername'@'$targetHost';"
                            
                            $success = Invoke-MySQLCommand -MySQLPath $MySQLPath -Username $Username -Password $Password -Command "$dropUserCmd FLUSH PRIVILEGES;"
                            
                            if ($success) {
                                Write-Host "User '$targetUser' deleted successfully!" -ForegroundColor Green
                            } else {
                                Write-Host "Failed to delete user." -ForegroundColor Red
                            }
                        } else {
                            Write-Host "User deletion canceled." -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "Invalid user format. Use the format 'user@host'." -ForegroundColor Red
                    }
                } else {
                    Write-Host "No users available to delete." -ForegroundColor Red
                }
                
                Read-Host "Press Enter to continue"
            }
            3 { # Return to Main Menu
                $continueManagingUsers = $false
            }
        }
    }
}

function Manage-Tables {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    $continueManagingTables = $true
    
    while ($continueManagingTables) {
        Show-Header
        Write-Host "MySQL Table Management" -ForegroundColor Yellow
        Write-Host "-----------------------------------------------" -ForegroundColor Yellow
        
        $databases = Get-MySQLDatabases -MySQLPath $MySQLPath -Username $Username -Password $Password
        
        if ($databases.Count -gt 0) {
            Write-Host "Available Databases:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $databases.Count; $i++) {
                Write-Host "  [$($i+1)] $($databases[$i])" -ForegroundColor White
            }
            
            Write-Host ""
            $dbChoice = Read-Host "Select a database (1-$($databases.Count))"
            
            try {
                $dbIndex = [int]$dbChoice - 1
                if ($dbIndex -ge 0 -and $dbIndex -lt $databases.Count) {
                    $selectedDb = $databases[$dbIndex]
                    
                    $tables = Get-MySQLTables -MySQLPath $MySQLPath -Username $Username -Password $Password -Database $selectedDb
                    
                    Show-Header
                    Write-Host "Database: $($selectedDb)" -ForegroundColor Cyan
                    Write-Host "-----------------------------------------------" -ForegroundColor Yellow
                    
                    if ($tables.Count -gt 0) {
                        Write-Host "Tables in $($selectedDb):" -ForegroundColor Cyan
                        foreach ($table in $tables) {
                            Write-Host "  - $table" -ForegroundColor White
                        }
                    } else {
                        Write-Host "No tables found in $($selectedDb)." -ForegroundColor Yellow
                    }
                    
                    Write-Host ""
                    $tableOptions = @(
                        "Create New Table",
                        "Drop Table",
                        "Return to Database Selection"
                    )
                    
                    $tableChoice = Show-Menu -Title "Table Management Options" -Options $tableOptions -DefaultOption 0
                    
                    switch ($tableChoice) {
                        0 { # Create New Table
                            $tableName = Read-Host "Enter new table name"
                            
                            Write-Host "Enter table structure (e.g., id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255)):"
                            $tableStructure = Read-Host
                            
                            $createTableCmd = "CREATE TABLE $tableName ($tableStructure);"
                            
                            $success = Invoke-MySQLCommand -MySQLPath $MySQLPath -Username $Username -Password $Password -Database $selectedDb -Command $createTableCmd
                            
                            if ($success) {
                                Write-Host "Table '$tableName' created successfully!" -ForegroundColor Green
                            } else {
                                Write-Host "Failed to create table." -ForegroundColor Red
                            }
                            
                            Read-Host "Press Enter to continue"
                        }
                        1 { # Drop Table
                            if ($tables.Count -gt 0) {
                                for ($i = 0; $i -lt $tables.Count; $i++) {
                                    Write-Host "  [$($i+1)] $($tables[$i])" -ForegroundColor White
                                }
                                
                                $tableChoice = Read-Host "Select a table to drop (1-$($tables.Count))"
                                
                                try {
                                    $tableIndex = [int]$tableChoice - 1
                                    if ($tableIndex -ge 0 -and $tableIndex -lt $tables.Count) {
                                        $targetTable = $tables[$tableIndex]
                                        
                                        $confirmation = Read-Host "Are you sure you want to drop '$targetTable'? (y/n)"
                                        
                                        if ($confirmation -eq "y") {
                                            $dropTableCmd = "DROP TABLE $targetTable;"
                                            
                                            $success = Invoke-MySQLCommand -MySQLPath $MySQLPath -Username $Username -Password $Password -Database $selectedDb -Command $dropTableCmd
                                            
                                            if ($success) {
                                                Write-Host "Table '$targetTable' dropped successfully!" -ForegroundColor Green
                                            } else {
                                                Write-Host "Failed to drop table." -ForegroundColor Red
                                            }
                                        } else {
                                            Write-Host "Table drop canceled." -ForegroundColor Yellow
                                        }
                                    } else {
                                        Write-Host "Invalid table selection." -ForegroundColor Red
                                    }
                                } catch {
                                    Write-Host "Invalid input." -ForegroundColor Red
                                }
                            } else {
                                Write-Host "No tables available to drop." -ForegroundColor Red
                            }
                            
                            Read-Host "Press Enter to continue"
                        }
                        2 { # Return to Database Selection
                            # Just continue the loop
                        }
                    }
                } else {
                    Write-Host "Invalid database selection." -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                }
            } catch {
                Write-Host "Invalid input." -ForegroundColor Red
                Read-Host "Press Enter to continue"
            }
        } else {
            Write-Host "No databases found or failed to retrieve databases." -ForegroundColor Red
            $continueManagingTables = $false
            Read-Host "Press Enter to continue"
        }
        
        if ($continueManagingTables) {
            $continueOption = Read-Host "Continue managing tables? (y/n)"
            $continueManagingTables = ($continueOption -eq "y")
        }
    }
}

function Create-Backup {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    Show-Header
    Write-Host "MySQL Database Backup" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------" -ForegroundColor Yellow
    
    $databases = Get-MySQLDatabases -MySQLPath $MySQLPath -Username $Username -Password $Password
    
    if ($databases.Count -gt 0) {
        Write-Host "Available Databases:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $databases.Count; $i++) {
            Write-Host "  [$($i+1)] $($databases[$i])" -ForegroundColor White
        }
        Write-Host "  [A] All Databases" -ForegroundColor White
        
        Write-Host ""
        $dbChoice = Read-Host "Select a database to backup (1-$($databases.Count) or A for all)"
        
        $targetDbs = @()
        
        if ($dbChoice -eq "A" -or $dbChoice -eq "a") {
            $targetDbs = $databases
            $backupFileName = "all_databases_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
        } else {
            try {
                $dbIndex = [int]$dbChoice - 1
                if ($dbIndex -ge 0 -and $dbIndex -lt $databases.Count) {
                    $targetDbs = @($databases[$dbIndex])
                    $backupFileName = "$($databases[$dbIndex])_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
                } else {
                    Write-Host "Invalid database selection." -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                    return
                }
            } catch {
                Write-Host "Invalid input." -ForegroundColor Red
                Read-Host "Press Enter to continue"
                return
            }
        }
        
        $backupPath = Read-Host "Enter backup directory path (default: current directory)"
        
        if ([string]::IsNullOrEmpty($backupPath)) {
            $backupPath = Get-Location
        }
        
        if (-not (Test-Path -Path $backupPath)) {
            Write-Host "Creating directory: $backupPath" -ForegroundColor Yellow
            New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
        }
        
        $fullBackupPath = Join-Path -Path $backupPath -ChildPath $backupFileName
        
        Write-Host "Starting backup process..." -ForegroundColor Yellow
        
        try {
            $mysqlDump = "$MySQLPath\bin\mysqldump.exe"
            
            if ($targetDbs.Count -eq 1) {
                $cmdArgs = "--user=`"$Username`" --password=`"$Password`" --databases $($targetDbs[0]) --result-file=`"$fullBackupPath`""
            } else {
                $cmdArgs = "--user=`"$Username`" --password=`"$Password`" --all-databases --result-file=`"$fullBackupPath`""
            }
            
            $process = Start-Process -FilePath $mysqlDump -ArgumentList $cmdArgs -NoNewWindow -PassThru -Wait
            
            if ($process.ExitCode -eq 0) {
                Write-Host "Backup completed successfully!" -ForegroundColor Green
                Write-Host "Backup saved to: $fullBackupPath" -ForegroundColor Green
            } else {
                Write-Host "Backup process failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Error creating backup: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "No databases found or failed to retrieve databases." -ForegroundColor Red
    }
    
    Read-Host "Press Enter to continue"
}

# Main Script Execution
$global:MySQLPath = ""
$global:Username = ""
$global:Password = ""

# Select MySQL Installation
Show-Header
Write-Host "Searching for MySQL installations..." -ForegroundColor Yellow

$mysqlInstallations = Get-MySQLInstallations

if ($CustomPath -ne "") {
    if (Test-Path -Path "$CustomPath\bin\mysql.exe") {
        $mysqlInstallations += $CustomPath
    } else {
        Write-Host "Custom path does not contain a valid MySQL installation." -ForegroundColor Red
    }
}

if ($mysqlInstallations.Count -eq 0) {
    Write-Host "No MySQL installations found!" -ForegroundColor Red
    Write-Host "Please enter a custom MySQL installation path:" -ForegroundColor Yellow
    $customPath = Read-Host
    
    if (Test-Path -Path "$customPath\bin\mysql.exe") {
        $global:MySQLPath = $customPath
    } else {
        Write-Host "Invalid MySQL path. Exiting." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Found MySQL installations:" -ForegroundColor Green
    for ($i = 0; $i -lt $mysqlInstallations.Count; $i++) {
        Write-Host "  [$($i+1)] $($mysqlInstallations[$i])" -ForegroundColor White
    }
    Write-Host "  [C] Enter Custom Path" -ForegroundColor White
    
    $choice = Read-Host "Select MySQL installation"
    
    if ($choice -eq "C" -or $choice -eq "c") {
        $customPath = Read-Host "Enter MySQL installation path"
        
        if (Test-Path -Path "$customPath\bin\mysql.exe") {
            $global:MySQLPath = $customPath
        } else {
            Write-Host "Invalid MySQL path. Exiting." -ForegroundColor Red
            exit 1
        }
    } else {
        try {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $mysqlInstallations.Count) {
                $global:MySQLPath = $mysqlInstallations[$index]
            } else {
                Write-Host "Invalid selection. Exiting." -ForegroundColor Red
                exit 1
            }
        } catch {
            Write-Host "Invalid input. Exiting." -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host "Selected MySQL Path: $global:MySQLPath" -ForegroundColor Green

# Login
Show-Header
Write-Host "MySQL Login" -ForegroundColor Yellow
Write-Host "-----------------------------------------------" -ForegroundColor Yellow

$loginAttempts = 0
$maxLoginAttempts = 3
$loggedIn = $false

while (-not $loggedIn -and $loginAttempts -lt $maxLoginAttempts) {
    $global:Username = Read-Host "Enter MySQL Username (default: root)"
    
    if ([string]::IsNullOrEmpty($global:Username)) {
        $global:Username = "root"
    }
    
    $passwordSecure = Read-Host "Enter MySQL Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passwordSecure)
    $global:Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    Write-Host "Testing connection..." -ForegroundColor Yellow
    $loggedIn = Test-Credentials -MySQLPath $global:MySQLPath -Username $global:Username -Password $global:Password
    
    if ($loggedIn) {
        Write-Host "Login successful!" -ForegroundColor Green
    } else {
        $loginAttempts++
        if ($loginAttempts -lt $maxLoginAttempts) {
            Write-Host "Login failed. Attempts remaining: $($maxLoginAttempts - $loginAttempts)" -ForegroundColor Red
        } else {
            Write-Host "Maximum login attempts reached. Would you like to reset the root password? (y/n)" -ForegroundColor Yellow
            $resetChoice = Read-Host
            
            if ($resetChoice -eq "y") {
                Reset-RootPassword -MySQLPath $global:MySQLPath
                # Restart login process
                $loginAttempts = 0
            } else {
                Write-Host "Exiting..." -ForegroundColor Red
                exit 1
            }
        }
    }
}

# Main Menu Loop
$exitApplication = $false

while (-not $exitApplication) {
    Show-Header
    
    $serviceStatus = Manage-MySQLService -MySQLPath $global:MySQLPath -Action "status"
    Write-Host "MySQL Service Status: " -NoNewline
    
    if ($serviceStatus -eq "Running") {
        Write-Host $serviceStatus -ForegroundColor Green
    } else {
        Write-Host $serviceStatus -ForegroundColor Red
    }
    
    Write-Host "Connected to: $global:MySQLPath" -ForegroundColor Cyan
    Write-Host "User: $global:Username" -ForegroundColor Cyan
    Write-Host ""
    
    $mainOptions = @(
        "User Management",
        "Table Management",
        "Create Database Backup",
        "MySQL Service Control",
        "Reset Root Password",
        "Exit"
    )
    
    $mainChoice = Show-Menu -Title "Main Menu" -Options $mainOptions -DefaultOption 0
    
    switch ($mainChoice) {
        0 { # User Management
            Manage-Users -MySQLPath $global:MySQLPath -Username $global:Username -Password $global:Password
        }
        1 { # Table Management
            Manage-Tables -MySQLPath $global:MySQLPath -Username $global:Username -Password $global:Password
        }
        2 { # Create Database Backup
            Create-Backup -MySQLPath $global:MySQLPath -Username $global:Username -Password $global:Password
        }
        3 { # MySQL Service Control
            Show-Header
            Write-Host "MySQL Service Control" -ForegroundColor Yellow
            Write-Host "-----------------------------------------------" -ForegroundColor Yellow
            
            $serviceOptions = @(
                "Start MySQL Service",
                "Stop MySQL Service",
                "Restart MySQL Service",
                "Return to Main Menu"
            )
            
            $serviceChoice = Show-Menu -Title "Service Control Options" -Options $serviceOptions -DefaultOption 0
            
            switch ($serviceChoice) {
                0 { # Start MySQL Service
                    Manage-MySQLService -MySQLPath $global:MySQLPath -Action "start"
                }
                1 { # Stop MySQL Service
                    Manage-MySQLService -MySQLPath $global:MySQLPath -Action "stop"
                }
                2 { # Restart MySQL Service
                    Manage-MySQLService -MySQLPath $global:MySQLPath -Action "restart"
                }
                3 { # Return to Main Menu
                    # Just continue the loop
                }
            }
            
            Read-Host "Press Enter to continue"
        }
        4 { # Reset Root Password
            Reset-RootPassword -MySQLPath $global:MySQLPath
        }
        5 { # Exit
            $exitApplication = $true
        }
    }
}

Write-Host "Thank you for using MySQL Database Management Tool!" -ForegroundColor Cyan
Start-Sleep -Seconds 2
