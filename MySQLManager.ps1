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
    
    # First check if the MySQL path is valid
    if (-not (Test-Path -Path "$MySQLPath\bin\mysql.exe")) {
        Write-Host "Error: MySQL client not found at $MySQLPath\bin\mysql.exe" -ForegroundColor Red
        return $false
    }
    
    try {
        # Build command arguments
        $args = @("--user=`"$Username`"")
        
        if (-not [string]::IsNullOrEmpty($Password)) {
            $args += "--password=`"$Password`""
        }
        
        $args += "--execute=`"SELECT 1;`""
        
        # Create process info
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "$MySQLPath\bin\mysql.exe"
        $pinfo.Arguments = $args -join " "
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        
        # Start the process
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo
        $process.Start() | Out-Null
        
        # Capture output
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        # Return success based on exit code
        return ($process.ExitCode -eq 0)
    }
    catch {
        Write-Host "Error testing MySQL credentials: $_" -ForegroundColor Red
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
    Write-Host "Using init-file method for MySQL password reset" -ForegroundColor Cyan
    
    $newPassword = Read-Host "Enter new root password"
    
    if ([string]::IsNullOrEmpty($newPassword)) {
        Write-Host "Password cannot be empty!" -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return
    }
    
    # Get service name
    $mysqlService = Get-Service | Where-Object { $_.Name -like "MySQL*" -or $_.Name -like "mysql*" } | Select-Object -First 1
    
    if (-not $mysqlService) {
        Write-Host "Could not find MySQL service. Please ensure MySQL is installed as a Windows service." -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return
    }
    
    $serviceName = $mysqlService.Name
    Write-Host "Found MySQL service: $serviceName" -ForegroundColor Green
    
    # Step 1: Stop the MySQL service
    Write-Host "Step 1: Stopping MySQL service..." -ForegroundColor Yellow
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    
    # Wait to ensure service is stopped
    $timeoutCounter = 0
    while ((Get-Service -Name $serviceName).Status -ne 'Stopped' -and $timeoutCounter -lt 10) {
        Start-Sleep -Seconds 1
        $timeoutCounter++
    }
    
    if ((Get-Service -Name $serviceName).Status -ne 'Stopped') {
        Write-Host "Could not stop MySQL service properly. Attempting to force stop..." -ForegroundColor Red
        $mysqlProcesses = Get-Process -Name mysql* -ErrorAction SilentlyContinue
        foreach ($process in $mysqlProcesses) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }
    
    Write-Host "MySQL service stopped." -ForegroundColor Green
    
    # Step 2: Create initialization file
    Write-Host "Step 2: Creating password reset file..." -ForegroundColor Yellow
    $initFile = "C:\mysql-init.txt"
    "ALTER USER 'root'@'localhost' IDENTIFIED BY '$newPassword';" | Out-File -FilePath $initFile -Encoding ASCII -Force
    
    Write-Host "Created password reset file at: $initFile" -ForegroundColor Green
    
    # Step 3: Find mysqld path
    Write-Host "Step 3: Locating mysqld executable..." -ForegroundColor Yellow
    $mysqldPath = "$MySQLPath\bin\mysqld.exe"
    
    if (-not (Test-Path -Path $mysqldPath)) {
        # Try to find it
        $standardPaths = @(
            "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqld.exe",
            "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqld.exe",
            "C:\Program Files (x86)\MySQL\MySQL Server 8.0\bin\mysqld.exe",
            "C:\xampp\mysql\bin\mysqld.exe",
            "C:\wamp\bin\mysql\mysql8.0\bin\mysqld.exe",
            "C:\wamp64\bin\mysql\mysql8.0\bin\mysqld.exe"
        )
        
        foreach ($path in $standardPaths) {
            if (Test-Path -Path $path) {
                $mysqldPath = $path
                Write-Host "Found mysqld at: $mysqldPath" -ForegroundColor Green
                break
            }
        }
        
        if (-not (Test-Path -Path $mysqldPath)) {
            Write-Host "Could not find mysqld.exe. Please provide the full path to mysqld.exe:" -ForegroundColor Yellow
            $userPath = Read-Host
            
            if (-not [string]::IsNullOrEmpty($userPath) -and (Test-Path -Path $userPath)) {
                $mysqldPath = $userPath
            } else {
                Write-Host "Invalid path. Password reset requires mysqld.exe." -ForegroundColor Red
                Remove-Item -Path $initFile -Force -ErrorAction SilentlyContinue
                Read-Host "Press Enter to continue"
                return
            }
        }
    }
    
    # Step 4: Find my.ini path
    Write-Host "Step 4: Checking for MySQL configuration file..." -ForegroundColor Yellow
    $defaultsFile = $null
    
    try {
        $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
        if ($wmiService) {
            $pathToExecutable = $wmiService.PathName
            
            if ($pathToExecutable -match "--defaults-file=([^\""\s]+)") {
                $defaultsFile = $matches[1]
                $defaultsFile = $defaultsFile -replace "\\\\", "\"
                Write-Host "Found defaults-file from service: $defaultsFile" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "Could not retrieve service configuration. Will proceed without defaults-file." -ForegroundColor Yellow
    }
    
    if (-not $defaultsFile) {
        # Try common locations
        $possiblePaths = @(
            "C:\ProgramData\MySQL\MySQL Server 8.0\my.ini",
            "C:\ProgramData\MySQL\MySQL Server 5.7\my.ini",
            "$MySQLPath\my.ini"
        )
        
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $defaultsFile = $path
                Write-Host "Found configuration file at: $defaultsFile" -ForegroundColor Green
                break
            }
        }
    }
    
    # Step 5: Run mysqld with init-file
    Write-Host "Step 5: Starting MySQL with password reset file..." -ForegroundColor Yellow
    
    try {
        # Create command arguments
        $resetArgs = "--init-file=`"$initFile`" --console"
        if ($defaultsFile) {
            $resetArgs = "--defaults-file=`"$defaultsFile`" $resetArgs"
        }
        
        # Prepare a PowerShell command that will start mysqld in a new window
        $commandLine = "Start-Process -FilePath '$mysqldPath' -ArgumentList '$resetArgs' -Wait -NoNewWindow"
        
        # Create batch file to run the command
        $batchFile = "$env:TEMP\mysql_reset.bat"
@"
@echo off
echo MySQL Password Reset
echo Running: $mysqldPath $resetArgs
echo.
echo Press Ctrl+C when you see MySQL Server is ready for connections
echo.
"$mysqldPath" $resetArgs
"@ | Out-File -FilePath $batchFile -Encoding ASCII -Force
        
        # Execute the batch file
        Write-Host "Starting MySQL with reset parameters..." -ForegroundColor Yellow
        Write-Host "An admin command prompt will open and run MySQL in reset mode." -ForegroundColor Yellow
        Write-Host "Wait until you see 'ready for connections' then press Ctrl+C to stop it." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to continue"
        
        # Start process with admin rights
        Start-Process "cmd.exe" -ArgumentList "/c $batchFile" -Verb RunAs -Wait
        
        # Clean up
        Remove-Item -Path $batchFile -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "Error running MySQL with reset parameters: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual reset instruction:" -ForegroundColor Yellow
        Write-Host "1. Open an admin command prompt" -ForegroundColor Yellow
        Write-Host "2. Navigate to MySQL bin directory: cd $MySQLPath\bin" -ForegroundColor Yellow
        if ($defaultsFile) {
            Write-Host "3. Run: mysqld --defaults-file=`"$defaultsFile`" --init-file=`"$initFile`" --console" -ForegroundColor Yellow
        } else {
            Write-Host "3. Run: mysqld --init-file=`"$initFile`" --console" -ForegroundColor Yellow
        }
        Write-Host "4. Once you see MySQL is ready for connections, press Ctrl+C" -ForegroundColor Yellow
        
        $manualConfirm = Read-Host "Do you want to try manual execution now? (y/n)"
        if ($manualConfirm -eq "y") {
            # Let user manually open command prompt
            Write-Host "Please follow the instructions above in a separate command prompt window." -ForegroundColor Yellow
            Read-Host "Press Enter once you've completed the manual reset"
        }
    }
    
    # Step 6: Clean up init file
    Write-Host "Step 6: Cleaning up..." -ForegroundColor Yellow
    Remove-Item -Path $initFile -Force -ErrorAction SilentlyContinue
    
    # Step 7: Start MySQL service normally
    Write-Host "Step 7: Starting MySQL service normally..." -ForegroundColor Yellow
    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    # Wait for service to start
    $timeoutCounter = 0
    while ((Get-Service -Name $serviceName).Status -ne 'Running' -and $timeoutCounter -lt 20) {
        Start-Sleep -Seconds 1
        $timeoutCounter++
    }
    
    if ((Get-Service -Name $serviceName).Status -eq 'Running') {
        Write-Host "MySQL service started successfully." -ForegroundColor Green
    } else {
        Write-Host "Warning: MySQL service did not start automatically. Trying to start it manually..." -ForegroundColor Yellow
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        
        if ((Get-Service -Name $serviceName).Status -eq 'Running') {
            Write-Host "MySQL service started successfully." -ForegroundColor Green
        } else {
            Write-Host "MySQL service could not be started. Please start it manually from Services." -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Password reset process completed!" -ForegroundColor Green
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

if (-not (Test-Path -Path "$global:MySQLPath\bin\mysql.exe")) {
    Write-Host "Error: Invalid MySQL path detected - $global:MySQLPath does not contain bin\mysql.exe" -ForegroundColor Red
    
    # Attempt to find common MySQL installations
    $commonPaths = @(
        "C:\Program Files\MySQL\MySQL Server 8.0",
        "C:\Program Files\MySQL\MySQL Server 5.7",
        "C:\xampp\mysql",
        "C:\wamp64\bin\mysql\mysql8.0"
    )
    
    $validPaths = @()
    foreach ($path in $commonPaths) {
        if (Test-Path -Path "$path\bin\mysql.exe") {
            $validPaths += $path
        }
    }
    
    if ($validPaths.Count -gt 0) {
        Write-Host "Found valid MySQL installations:" -ForegroundColor Green
        for ($i = 0; $i -lt $validPaths.Count; $i++) {
            Write-Host "  [$($i+1)] $($validPaths[$i])" -ForegroundColor White
        }
        
        $validChoice = Read-Host "Select a valid MySQL installation (1-$($validPaths.Count))"
        try {
            $validIndex = [int]$validChoice - 1
            if ($validIndex -ge 0 -and $validIndex -lt $validPaths.Count) {
                $global:MySQLPath = $validPaths[$validIndex]
                Write-Host "MySQL path updated to: $global:MySQLPath" -ForegroundColor Green
            }
        } catch {
            # Continue to manual entry
        }
    }
    
    if (-not (Test-Path -Path "$global:MySQLPath\bin\mysql.exe")) {
        Write-Host "Please enter the FULL path to your MySQL installation (e.g., C:\Program Files\MySQL\MySQL Server 8.0):" -ForegroundColor Yellow
        $manualPath = Read-Host
        
        if (Test-Path -Path "$manualPath\bin\mysql.exe") {
            $global:MySQLPath = $manualPath
            Write-Host "MySQL path updated to: $global:MySQLPath" -ForegroundColor Green
        } else {
            Write-Host "Invalid MySQL path. The script cannot continue without a valid MySQL client." -ForegroundColor Red
            Write-Host "Exiting..." -ForegroundColor Red
            exit 1
        }
    }
}

# Verify MySQL client works
try {
    $versionOutput = & "$global:MySQLPath\bin\mysql" --version
    Write-Host "MySQL client found: $versionOutput" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not get MySQL version information." -ForegroundColor Yellow
}

Write-Host "Using MySQL installation at: $global:MySQLPath" -ForegroundColor Cyan

# Login
Show-Header
Write-Host "MySQL Login" -ForegroundColor Yellow
Write-Host "-----------------------------------------------" -ForegroundColor Yellow

$loginAttempts = 0
$maxLoginAttempts = 3
$loggedIn = $false

function Test-Credentials {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    try {
        # Build command for display (masked password)
        $displayCmd = "$MySQLPath\bin\mysql.exe --user=`"$Username`" --password=******** --execute=`"SELECT 1;`""
        Write-Host "Executing command (displaying masked password): $displayCmd" -ForegroundColor Gray
        
        # Build actual command
        $mysqlExe = "$MySQLPath\bin\mysql.exe"
        $cmdArgs = "--user=`"$Username`""
        
        if (-not [string]::IsNullOrEmpty($Password)) {
            $cmdArgs += " --password=`"$Password`""
        }
        
        $cmdArgs += " --execute=`"SELECT 1;`""
        
        # Show full command with real password for debugging (uncomment if needed)
        Write-Host "Full command: $mysqlExe $cmdArgs" -ForegroundColor Gray
        
        # Create process with output capture
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $mysqlExe
        $psi.Arguments = $cmdArgs
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        # Show detailed output
        Write-Host "Exit Code: $($process.ExitCode)" -ForegroundColor Gray
        Write-Host "Standard Output: '$stdout'" -ForegroundColor Gray
        Write-Host "Standard Error: '$stderr'" -ForegroundColor Gray
        
        return ($process.ExitCode -eq 0)
    }
    catch {
        Write-Host "Exception occurred: $_" -ForegroundColor Red
        return $false
    }
}

function Test-Credentials {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    try {
        # Build command for display (masked password)
        $displayCmd = "$MySQLPath\bin\mysql.exe --user=`"$Username`" --password=******** --execute=`"SELECT 1;`""
        Write-Host "Executing command (displaying masked password): $displayCmd" -ForegroundColor Gray
        
        # Build actual command
        $mysqlExe = "$MySQLPath\bin\mysql.exe"
        $cmdArgs = "--user=`"$Username`""
        
        if (-not [string]::IsNullOrEmpty($Password)) {
            $cmdArgs += " --password=`"$Password`""
        }
        
        $cmdArgs += " --execute=`"SELECT 1;`""
        
        # Show full command with real password for debugging (uncomment if needed)
        Write-Host "Full command: $mysqlExe $cmdArgs" -ForegroundColor Gray
        
        # Create process with output capture
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $mysqlExe
        $psi.Arguments = $cmdArgs
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        # Show detailed output
        Write-Host "Exit Code: $($process.ExitCode)" -ForegroundColor Gray
        Write-Host "Standard Output: '$stdout'" -ForegroundColor Gray
        Write-Host "Standard Error: '$stderr'" -ForegroundColor Gray
        
        return ($process.ExitCode -eq 0)
    }
    catch {
        Write-Host "Exception occurred: $_" -ForegroundColor Red
        return $false
    }
}

# Login section with additional debugging
while (-not $loggedIn -and $loginAttempts -lt $maxLoginAttempts) {
    $global:Username = Read-Host "Enter MySQL Username (default: root)"
    
    if ([string]::IsNullOrEmpty($global:Username)) {
        $global:Username = "root"
    }
    
    # Allow for plain text password for simplicity during debugging
    $global:Password = Read-Host "Enter MySQL Password"
    
    Write-Host "Testing connection..." -ForegroundColor Yellow
    Write-Host "MySQL Path: $global:MySQLPath" -ForegroundColor Gray
    
    # Try the traditional approach
    $loggedIn = Test-Credentials -MySQLPath $global:MySQLPath -Username $global:Username -Password $global:Password
    
    if (-not $loggedIn) {
        Write-Host "Trying alternative connection methods..." -ForegroundColor Yellow
        
        # Try approach without quotes around password parameter
        Write-Host "Attempt #2: Without quotes around password" -ForegroundColor Gray
        $mysqlExe = "$global:MySQLPath\bin\mysql.exe"
        $noQuotesCmd = "$mysqlExe --user=`"$global:Username`" --password=$global:Password --execute=`"SELECT 1;`""
        
        try {
            $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $noQuotesCmd -NoNewWindow -PassThru -Wait
            if ($process.ExitCode -eq 0) {
                Write-Host "Success with no quotes approach!" -ForegroundColor Green
                $loggedIn = $true
            } else {
                Write-Host "Failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Exception: $_" -ForegroundColor Red
        }
        
        # If still not logged in, try alternative approach with direct command line
        if (-not $loggedIn) {
            Write-Host "Attempt #3: Direct command line" -ForegroundColor Gray
            try {
                $cmdText = "echo SELECT 1; | $mysqlExe --user=`"$global:Username`" --password=`"$global:Password`""
                $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmdText -NoNewWindow -PassThru -Wait
                if ($process.ExitCode -eq 0) {
                    Write-Host "Success with direct command line approach!" -ForegroundColor Green
                    $loggedIn = $true
                } else {
                    Write-Host "Failed with exit code: $($process.ExitCode)" -ForegroundColor Red
                }
            } catch {
                Write-Host "Exception: $_" -ForegroundColor Red
            }
        }
    }
    
    if ($loggedIn) {
        Write-Host "Login successful!" -ForegroundColor Green
    } else {
        $loginAttempts++
        if ($loginAttempts -lt $maxLoginAttempts) {
            Write-Host "Login failed. Attempts remaining: $($maxLoginAttempts - $loginAttempts)" -ForegroundColor Red
        } else {
            Write-Host "Maximum login attempts reached." -ForegroundColor Red
            
            # Try with no password as last resort
            Write-Host "Last attempt: Trying with no password..." -ForegroundColor Yellow
            $loggedIn = Test-Credentials -MySQLPath $global:MySQLPath -Username $global:Username -Password ""
            
            if ($loggedIn) {
                Write-Host "Success with empty password!" -ForegroundColor Green
            } else {
                Write-Host "Authentication failed with all methods." -ForegroundColor Red
                Write-Host "Would you like to reset the root password? (y/n)" -ForegroundColor Yellow
                $resetChoice = Read-Host
                
                if ($resetChoice -eq "y") {
                    Reset-RootPassword -MySQLPath $global:MySQLPath
                    $loginAttempts = 0
                } else {
                    Write-Host "Exiting..." -ForegroundColor Red
                    exit 1
                }
            }
        }
    }
}function Test-Credentials {
    param (
        [string]$MySQLPath,
        [string]$Username,
        [string]$Password
    )
    
    try {
        # Build command for display (masked password)
        $displayCmd = "$MySQLPath\bin\mysql.exe --user=`"$Username`" --password=******** --execute=`"SELECT 1;`""
        Write-Host "Executing command (displaying masked password): $displayCmd" -ForegroundColor Gray
        
        # Build actual command
        $mysqlExe = "$MySQLPath\bin\mysql.exe"
        $cmdArgs = "--user=`"$Username`""
        
        if (-not [string]::IsNullOrEmpty($Password)) {
            $cmdArgs += " --password=`"$Password`""
        }
        
        $cmdArgs += " --execute=`"SELECT 1;`""
        
        # Show full command with real password for debugging (uncomment if needed)
        Write-Host "Full command: $mysqlExe $cmdArgs" -ForegroundColor Gray
        
        # Create process with output capture
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $mysqlExe
        $psi.Arguments = $cmdArgs
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        # Show detailed output
        Write-Host "Exit Code: $($process.ExitCode)" -ForegroundColor Gray
        Write-Host "Standard Output: '$stdout'" -ForegroundColor Gray
        Write-Host "Standard Error: '$stderr'" -ForegroundColor Gray
        
        return ($process.ExitCode -eq 0)
    }
    catch {
        Write-Host "Exception occurred: $_" -ForegroundColor Red
        return $false
    }
}

# Login section with additional debugging
while (-not $loggedIn -and $loginAttempts -lt $maxLoginAttempts) {
    $global:Username = Read-Host "Enter MySQL Username (default: root)"
    
    if ([string]::IsNullOrEmpty($global:Username)) {
        $global:Username = "root"
    }
    
    # Allow for plain text password for simplicity during debugging
    $global:Password = Read-Host "Enter MySQL Password"
    
    Write-Host "Testing connection..." -ForegroundColor Yellow
    Write-Host "MySQL Path: $global:MySQLPath" -ForegroundColor Gray
    
    # Try the traditional approach
    $loggedIn = Test-Credentials -MySQLPath $global:MySQLPath -Username $global:Username -Password $global:Password
    
    if (-not $loggedIn) {
        Write-Host "Trying alternative connection methods..." -ForegroundColor Yellow
        
        # Try approach without quotes around password parameter
        Write-Host "Attempt #2: Without quotes around password" -ForegroundColor Gray
        $mysqlExe = "$global:MySQLPath\bin\mysql.exe"
        $noQuotesCmd = "$mysqlExe --user=`"$global:Username`" --password=$global:Password --execute=`"SELECT 1;`""
        
        try {
            $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $noQuotesCmd -NoNewWindow -PassThru -Wait
            if ($process.ExitCode -eq 0) {
                Write-Host "Success with no quotes approach!" -ForegroundColor Green
                $loggedIn = $true
            } else {
                Write-Host "Failed with exit code: $($process.ExitCode)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Exception: $_" -ForegroundColor Red
        }
        
        # If still not logged in, try alternative approach with direct command line
        if (-not $loggedIn) {
            Write-Host "Attempt #3: Direct command line" -ForegroundColor Gray
            try {
                $cmdText = "echo SELECT 1; | $mysqlExe --user=`"$global:Username`" --password=`"$global:Password`""
                $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmdText -NoNewWindow -PassThru -Wait
                if ($process.ExitCode -eq 0) {
                    Write-Host "Success with direct command line approach!" -ForegroundColor Green
                    $loggedIn = $true
                } else {
                    Write-Host "Failed with exit code: $($process.ExitCode)" -ForegroundColor Red
                }
            } catch {
                Write-Host "Exception: $_" -ForegroundColor Red
            }
        }
    }
    
    if ($loggedIn) {
        Write-Host "Login successful!" -ForegroundColor Green
    } else {
        $loginAttempts++
        if ($loginAttempts -lt $maxLoginAttempts) {
            Write-Host "Login failed. Attempts remaining: $($maxLoginAttempts - $loginAttempts)" -ForegroundColor Red
        } else {
            Write-Host "Maximum login attempts reached." -ForegroundColor Red
            
            # Try with no password as last resort
            Write-Host "Last attempt: Trying with no password..." -ForegroundColor Yellow
            $loggedIn = Test-Credentials -MySQLPath $global:MySQLPath -Username $global:Username -Password ""
            
            if ($loggedIn) {
                Write-Host "Success with empty password!" -ForegroundColor Green
            } else {
                Write-Host "Authentication failed with all methods." -ForegroundColor Red
                Write-Host "Would you like to reset the root password? (y/n)" -ForegroundColor Yellow
                $resetChoice = Read-Host
                
                if ($resetChoice -eq "y") {
                    Reset-RootPassword -MySQLPath $global:MySQLPath
                    $loginAttempts = 0
                } else {
                    Write-Host "Exiting..." -ForegroundColor Red
                    exit 1
                }
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
