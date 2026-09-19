# ============================================================
# AVD Golden Image - Common Applications V3
#
# Install / Upgrade / Verify / Cleanup
#
# Designed for:
# - Windows 10/11
# - Windows Enterprise multi-session / AVD
# - x64 Golden Images
#
# Main change from V2:
# - Architecture is NOT forced globally.
# - Architecture is specified per application only when needed.
#
# Run from elevated Windows PowerShell 5.1 or PowerShell 7.
# ============================================================

$ErrorActionPreference = "Stop"

# ============================================================
# Configuration
# ============================================================

$InstallODBC11       = $true
$InstallODBC17       = $true
$InstallODBC18       = $true

$InstallBigFiles     = $true
$InstallComparePlus  = $true

$SSMSVersion         = "20.2.1"

$WorkingRoot = "C:\Windows\Temp\AVD-AppInstall"

$Results = [System.Collections.Generic.List[object]]::new()


# ============================================================
# Helper - Result
# ============================================================

function Add-Result {

    param(
        [string]$Name,
        [string]$Status,
        [string]$Message
    )

    $Results.Add(
        [PSCustomObject]@{
            Application = $Name
            Status      = $Status
            Message     = $Message
        }
    )
}


# ============================================================
# Helper - Find winget.exe
# ============================================================

function Get-WingetPath {

    $Command = Get-Command winget.exe -ErrorAction SilentlyContinue

    if ($Command) {
        return $Command.Source
    }


    $Package = Get-AppxPackage Microsoft.DesktopAppInstaller `
        -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($Package) {

        $Exe = Join-Path $Package.InstallLocation "winget.exe"

        if (Test-Path $Exe) {
            return $Exe
        }
    }


    $Package = Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller `
        -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($Package) {

        $Exe = Join-Path $Package.InstallLocation "winget.exe"

        if (Test-Path $Exe) {
            return $Exe
        }
    }


    $Candidates = Get-ChildItem `
        "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe" `
        -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending


    if ($Candidates) {
        return $Candidates[0].FullName
    }


    return $null
}


# ============================================================
# Helper - Package installed?
# ============================================================

function Test-WingetPackageInstalled {

    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    try {

        $Output = & $Winget list `
            --id $Id `
            --exact `
            --accept-source-agreements `
            --disable-interactivity 2>&1


        if ($Output -match [regex]::Escape($Id)) {
            return $true
        }
    }
    catch {
    }

    return $false
}


# ============================================================
# Helper - Upgrade available?
# ============================================================

function Test-WingetUpgradeAvailable {

    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    try {

        $Output = & $Winget list `
            --id $Id `
            --exact `
            --upgrade-available `
            --accept-source-agreements `
            --disable-interactivity 2>&1


        if ($Output -match [regex]::Escape($Id)) {
            return $true
        }
    }
    catch {
    }

    return $false
}


# ============================================================
# Helper - Install / Upgrade package
#
# IMPORTANT:
# $Architecture defaults to NULL.
# It will only be added when explicitly supplied.
# ============================================================

function InstallOrUpdate-WingetPackage {

    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Id,

        [string]$Version,

        [string]$Architecture,

        [string]$InstallerType
    )


    Write-Host ""
    Write-Host "=================================================="
    Write-Host "Processing : $Name"
    Write-Host "Package ID : $Id"

    if ($Architecture) {
        Write-Host "Architecture: $Architecture"
    }

    if ($Version) {
        Write-Host "Version    : $Version"
    }

    Write-Host "=================================================="


    try {

        # ----------------------------------------------------
        # Verify package exists in WinGet repository
        # ----------------------------------------------------

        $ShowArgs = @(
            "show"
            "--id", $Id
            "--exact"
            "--source", "winget"
            "--accept-source-agreements"
            "--disable-interactivity"
        )


        $ShowOutput = & $Winget @ShowArgs 2>&1
        $ShowExit   = $LASTEXITCODE


        if ($ShowExit -ne 0) {

            throw "Package not found in WinGet repository."
        }


        # ----------------------------------------------------
        # Installed?
        # ----------------------------------------------------

        $Installed = Test-WingetPackageInstalled -Id $Id


        # ====================================================
        # NOT INSTALLED
        # ====================================================

        if (-not $Installed) {

            Write-Host "[INFO] Not installed. Installing..."


            $Args = @(
                "install"
                "--id", $Id
                "--exact"
                "--source", "winget"
                "--silent"
                "--disable-interactivity"
                "--accept-source-agreements"
                "--accept-package-agreements"
            )


            if ($Architecture) {

                $Args += @(
                    "--architecture",
                    $Architecture
                )
            }


            if ($Version) {

                $Args += @(
                    "--version",
                    $Version
                )
            }


            if ($InstallerType) {

                $Args += @(
                    "--installer-type",
                    $InstallerType
                )
            }


            & $Winget @Args

            $ExitCode = $LASTEXITCODE


            if ($ExitCode -ne 0) {

                throw "Install returned exit code $ExitCode"
            }


            Write-Host "[OK] Installed."


            Add-Result `
                -Name $Name `
                -Status "Success" `
                -Message "Installed"

            return
        }


        # ====================================================
        # ALREADY INSTALLED
        # ====================================================

        Write-Host "[INFO] Already installed."


        # ----------------------------------------------------
        # Fixed version / pinned baseline
        #
        # Mainly used for SSMS 20.2.1.
        # ----------------------------------------------------

        if ($Version) {

            Write-Host "[INFO] Target baseline version: $Version"


            $Args = @(
                "upgrade"
                "--id", $Id
                "--exact"
                "--source", "winget"
                "--version", $Version
                "--silent"
                "--disable-interactivity"
                "--accept-source-agreements"
                "--accept-package-agreements"
            )


            if ($Architecture) {

                $Args += @(
                    "--architecture",
                    $Architecture
                )
            }


            if ($InstallerType) {

                $Args += @(
                    "--installer-type",
                    $InstallerType
                )
            }


            $Output = & $Winget @Args 2>&1
            $ExitCode = $LASTEXITCODE


            if ($ExitCode -eq 0) {

                Write-Host "[OK] Checked against baseline $Version."

                Add-Result `
                    -Name $Name `
                    -Status "Success" `
                    -Message "Target baseline $Version checked"

                return
            }


            # An already-installed pinned version may report
            # "No applicable upgrade found".
            # Do not mark that as failure.

            Write-Host "[OK] Installed; no applicable upgrade to baseline $Version."


            Add-Result `
                -Name $Name `
                -Status "Success" `
                -Message "Installed / pinned to $Version"

            return
        }


        # ====================================================
        # NORMAL UPDATE CHECK
        # ====================================================

        $UpgradeAvailable = `
            Test-WingetUpgradeAvailable -Id $Id


        if (-not $UpgradeAvailable) {

            Write-Host "[OK] Already up to date."


            Add-Result `
                -Name $Name `
                -Status "Success" `
                -Message "Already up to date"

            return
        }


        # ====================================================
        # UPGRADE
        # ====================================================

        Write-Host "[INFO] Update available. Upgrading..."


        $Args = @(
            "upgrade"
            "--id", $Id
            "--exact"
            "--source", "winget"
            "--silent"
            "--disable-interactivity"
            "--accept-source-agreements"
            "--accept-package-agreements"
        )


        if ($Architecture) {

            $Args += @(
                "--architecture",
                $Architecture
            )
        }


        if ($InstallerType) {

            $Args += @(
                "--installer-type",
                $InstallerType
            )
        }


        & $Winget @Args

        $ExitCode = $LASTEXITCODE


        if ($ExitCode -ne 0) {

            throw "Upgrade returned exit code $ExitCode"
        }


        Write-Host "[OK] Upgraded."


        Add-Result `
            -Name $Name `
            -Status "Success" `
            -Message "Upgraded"
    }
    catch {

        $ErrorMessage = $_.Exception.Message

        Write-Warning "$Name failed: $ErrorMessage"


        Add-Result `
            -Name $Name `
            -Status "Failed" `
            -Message $ErrorMessage
    }
}


# ============================================================
# Preflight
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host " AVD Golden Image Application Maintenance V3"
Write-Host "=================================================="
Write-Host ""


# ------------------------------------------------------------
# Administrator check
# ------------------------------------------------------------

$Identity = `
    [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = `
    New-Object Security.Principal.WindowsPrincipal($Identity)

$IsAdmin = `
    $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )


if (-not $IsAdmin) {

    throw "Run this script from an elevated PowerShell session."
}


# ------------------------------------------------------------
# Architecture check
# ------------------------------------------------------------

$OS = Get-CimInstance Win32_OperatingSystem


if ($OS.OSArchitecture -notmatch "64") {

    throw "This script is designed for x64 Windows images."
}


Write-Host "Operating System : $($OS.Caption)"
Write-Host "Build            : $($OS.BuildNumber)"
Write-Host "Architecture     : $($OS.OSArchitecture)"


# ------------------------------------------------------------
# Working directory
# ------------------------------------------------------------

if (Test-Path $WorkingRoot) {

    Remove-Item `
        $WorkingRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
}


New-Item `
    -Path $WorkingRoot `
    -ItemType Directory `
    -Force |
    Out-Null


# ============================================================
# Locate WinGet
# ============================================================

$Winget = Get-WingetPath


if (-not $Winget) {

    throw @"

winget.exe was not found.

Check Microsoft Desktop App Installer:

Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller |
Select Name,PackageFullName,InstallLocation

"@
}


Write-Host ""
Write-Host "WinGet path: $Winget"

& $Winget --version


# ============================================================
# Refresh WinGet source
# ============================================================

Write-Host ""
Write-Host "Updating WinGet sources..."


try {

    & $Winget source update `
        --disable-interactivity `
        --accept-source-agreements
}
catch {

    Write-Warning "Unable to update WinGet sources."
}


# ============================================================
# General Utilities
# ============================================================

InstallOrUpdate-WingetPackage `
    -Name "7-Zip" `
    -Id "7zip.7zip" `
    -Architecture "x64"


InstallOrUpdate-WingetPackage `
    -Name "Notepad++" `
    -Id "Notepad++.Notepad++" `
    -Architecture "x64"


InstallOrUpdate-WingetPackage `
    -Name "Adobe Acrobat Reader 64-bit" `
    -Id "Adobe.Acrobat.Reader.64-bit" `
    -Architecture "x64"


# Do NOT force architecture
InstallOrUpdate-WingetPackage `
    -Name "Greenshot" `
    -Id "Greenshot.Greenshot"


# Firefox has native x64 build
InstallOrUpdate-WingetPackage `
    -Name "Mozilla Firefox" `
    -Id "Mozilla.Firefox" `
    -Architecture "x64"


# IMPORTANT:
# WinSCP stable installer should NOT be forced to x64.
InstallOrUpdate-WingetPackage `
    -Name "WinSCP" `
    -Id "WinSCP.WinSCP"


# Do not unnecessarily force architecture
InstallOrUpdate-WingetPackage `
    -Name "PuTTY" `
    -Id "PuTTY.PuTTY"


# ============================================================
# Microsoft Runtime
# ============================================================

InstallOrUpdate-WingetPackage `
    -Name "Microsoft Visual C++ 2015-2022 Redistributable x64" `
    -Id "Microsoft.VCRedist.2015+.x64" `
    -Architecture "x64"


InstallOrUpdate-WingetPackage `
    -Name ".NET Desktop Runtime 8 x64" `
    -Id "Microsoft.DotNet.DesktopRuntime.8" `
    -Architecture "x64"


# ============================================================
# PowerShell 7
#
# Prefer machine-wide MSI / WiX installation.
# ============================================================

InstallOrUpdate-WingetPackage `
    -Name "PowerShell 7" `
    -Id "Microsoft.PowerShell" `
    -Architecture "x64" `
    -InstallerType "wix"


# ============================================================
# Microsoft SQL Server ODBC Drivers
# ============================================================

if ($InstallODBC11) {

    InstallOrUpdate-WingetPackage `
        -Name "Microsoft ODBC Driver 11 for SQL Server x64" `
        -Id "Microsoft.msodbcsql.11" `
        -Architecture "x64"
}


if ($InstallODBC17) {

    InstallOrUpdate-WingetPackage `
        -Name "Microsoft ODBC Driver 17 for SQL Server x64" `
        -Id "Microsoft.msodbcsql.17" `
        -Architecture "x64"
}


if ($InstallODBC18) {

    InstallOrUpdate-WingetPackage `
        -Name "Microsoft ODBC Driver 18 for SQL Server x64" `
        -Id "Microsoft.msodbcsql.18" `
        -Architecture "x64"
}


# ============================================================
# SQL Server Management Studio
#
# Baseline:
# SSMS 20.2.1
#
# Do not automatically move the Golden Image to a newer
# major SSMS version.
# ============================================================

InstallOrUpdate-WingetPackage `
    -Name "SQL Server Management Studio $SSMSVersion" `
    -Id "Microsoft.SQLServerManagementStudio" `
    -Version $SSMSVersion


# ============================================================
# Notepad++ Plugins
# ============================================================

$NppPath = "C:\Program Files\Notepad++"


if (-not (Test-Path "$NppPath\notepad++.exe")) {

    Write-Warning "Notepad++ not found. Plugin installation skipped."


    Add-Result `
        -Name "Notepad++ Plugins" `
        -Status "Skipped" `
        -Message "Notepad++ not installed"
}


# ============================================================
# ComparePlus Plugin
# ============================================================

if (
    $InstallComparePlus -and
    (Test-Path "$NppPath\notepad++.exe")
) {

    Write-Host ""
    Write-Host "=================================================="
    Write-Host "Processing Notepad++ ComparePlus"
    Write-Host "=================================================="


    try {

        $Release = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/pnedev/comparePlus/releases/latest" `
            -UseBasicParsing


        $Asset = $Release.assets |
            Where-Object {

                $_.name -match "\.zip$" -and
                $_.name -match "(x64|64bit|64)"
            } |
            Select-Object -First 1


        if (-not $Asset) {

            throw "No x64 ComparePlus ZIP package found."
        }


        $Zip = `
            Join-Path $WorkingRoot $Asset.name


        Invoke-WebRequest `
            -Uri $Asset.browser_download_url `
            -OutFile $Zip `
            -UseBasicParsing


        $Extract = `
            Join-Path $WorkingRoot "ComparePlus"


        if (Test-Path $Extract) {

            Remove-Item `
                $Extract `
                -Recurse `
                -Force
        }


        Expand-Archive `
            -Path $Zip `
            -DestinationPath $Extract `
            -Force


        $Dll = Get-ChildItem `
            $Extract `
            -Filter "ComparePlus.dll" `
            -Recurse |
            Select-Object -First 1


        if (-not $Dll) {

            throw "ComparePlus.dll not found in downloaded archive."
        }


        $Destination = `
            "$NppPath\plugins\ComparePlus"


        if (Test-Path $Destination) {

            Remove-Item `
                $Destination `
                -Recurse `
                -Force
        }


        New-Item `
            -Path $Destination `
            -ItemType Directory `
            -Force |
            Out-Null


        Copy-Item `
            "$($Dll.Directory.FullName)\*" `
            $Destination `
            -Recurse `
            -Force


        Write-Host "[OK] ComparePlus installed/updated."


        Add-Result `
            -Name "Notepad++ ComparePlus" `
            -Status "Success" `
            -Message "Installed/updated $($Release.tag_name)"
    }
    catch {

        $Message = $_.Exception.Message

        Write-Warning "ComparePlus failed: $Message"


        Add-Result `
            -Name "Notepad++ ComparePlus" `
            -Status "Failed" `
            -Message $Message
    }
}


# ============================================================
# BigFiles Plugin
# ============================================================

if (
    $InstallBigFiles -and
    (Test-Path "$NppPath\notepad++.exe")
) {

    Write-Host ""
    Write-Host "=================================================="
    Write-Host "Processing Notepad++ BigFiles"
    Write-Host "=================================================="


    try {

        $BigFilesURL = `
            "https://raw.githubusercontent.com/superolmo/BigFiles/master/x64/Release/BigFiles.dll"


        $Destination = `
            "$NppPath\plugins\BigFiles"


        New-Item `
            -Path $Destination `
            -ItemType Directory `
            -Force |
            Out-Null


        Invoke-WebRequest `
            -Uri $BigFilesURL `
            -OutFile "$Destination\BigFiles.dll" `
            -UseBasicParsing


        if (-not (Test-Path "$Destination\BigFiles.dll")) {

            throw "BigFiles.dll was not downloaded."
        }


        Write-Host "[OK] BigFiles installed/updated."


        Add-Result `
            -Name "Notepad++ BigFiles" `
            -Status "Success" `
            -Message "Installed/updated"
    }
    catch {

        $Message = $_.Exception.Message

        Write-Warning "BigFiles failed: $Message"


        Add-Result `
            -Name "Notepad++ BigFiles" `
            -Status "Failed" `
            -Message $Message
    }
}


# ============================================================
# Application Verification
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host " Application Verification"
Write-Host "=================================================="


$Verification = [ordered]@{

    "7-Zip" = @(
        "C:\Program Files\7-Zip\7z.exe"
    )

    "Notepad++" = @(
        "C:\Program Files\Notepad++\notepad++.exe"
    )

    "Adobe Acrobat Reader" = @(
        "C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe",
        "C:\Program Files\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
        "C:\Program Files (x86)\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
    )

    "Greenshot" = @(
        "C:\Program Files\Greenshot\Greenshot.exe",
        "C:\Program Files (x86)\Greenshot\Greenshot.exe"
    )

    "Firefox" = @(
        "C:\Program Files\Mozilla Firefox\firefox.exe",
        "C:\Program Files (x86)\Mozilla Firefox\firefox.exe"
    )

    "WinSCP" = @(
        "C:\Program Files\WinSCP\WinSCP.exe",
        "C:\Program Files (x86)\WinSCP\WinSCP.exe"
    )

    "PuTTY" = @(
        "C:\Program Files\PuTTY\putty.exe",
        "C:\Program Files (x86)\PuTTY\putty.exe"
    )

    "PowerShell 7" = @(
        "C:\Program Files\PowerShell\7\pwsh.exe"
    )
}


foreach ($Entry in $Verification.GetEnumerator()) {

    $Found = $false


    foreach ($Path in $Entry.Value) {

        if (Test-Path $Path) {

            $Version = `
                (Get-Item $Path).VersionInfo.ProductVersion


            Write-Host "[OK] $($Entry.Key)"
            Write-Host "     Path   : $Path"

            if ($Version) {

                Write-Host "     Version: $Version"
            }


            $Found = $true

            break
        }
    }


    if (-not $Found) {

        Write-Warning `
            "$($Entry.Key) executable not found in expected paths."
    }
}


# ============================================================
# Verify Notepad++ Plugins
# ============================================================

Write-Host ""
Write-Host "Notepad++ plugins:"


$PluginVerification = @(

    "$NppPath\plugins\ComparePlus\ComparePlus.dll",

    "$NppPath\plugins\BigFiles\BigFiles.dll"
)


foreach ($Plugin in $PluginVerification) {

    if (Test-Path $Plugin) {

        Write-Host "[OK] $Plugin"
    }
    else {

        Write-Warning "Plugin not found: $Plugin"
    }
}


# ============================================================
# Verify ODBC Drivers
# ============================================================

Write-Host ""
Write-Host "Installed SQL Server ODBC drivers:"


Get-OdbcDriver |
    Where-Object {

        $_.Name -match "SQL Server"
    } |
    Select-Object `
        Name,
        Platform,
        Version |
    Sort-Object `
        Name,
        Platform |
    Format-Table -AutoSize


# ============================================================
# Verify SSMS
# ============================================================

Write-Host ""
Write-Host "Checking SSMS..."


$SSMSCandidates = @(

    "C:\Program Files (x86)\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe",

    "C:\Program Files\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe"
)


$SSMSFound = $false


foreach ($Path in $SSMSCandidates) {

    if (Test-Path $Path) {

        $FileVersion = `
            (Get-Item $Path).VersionInfo.FileVersion


        Write-Host "[OK] SSMS"
        Write-Host "     Path   : $Path"
        Write-Host "     Version: $FileVersion"


        $SSMSFound = $true

        break
    }
}


if (-not $SSMSFound) {

    Write-Warning "SSMS executable was not found in expected SSMS 20 paths."
}


# ============================================================
# Golden Image Cleanup
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host " Golden Image Cleanup"
Write-Host "=================================================="


# ------------------------------------------------------------
# Remove script working folder
# ------------------------------------------------------------

if (Test-Path $WorkingRoot) {

    Remove-Item `
        $WorkingRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue


    Write-Host "[OK] Removed installation working directory."
}


# ------------------------------------------------------------
# Clean current user TEMP
# ------------------------------------------------------------

Write-Host "Cleaning current user TEMP..."


Get-ChildItem `
    $env:TEMP `
    -Force `
    -ErrorAction SilentlyContinue |
    Remove-Item `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue


# ------------------------------------------------------------
# Clean Windows TEMP
# ------------------------------------------------------------

Write-Host "Cleaning Windows TEMP..."


Get-ChildItem `
    "$env:SystemRoot\Temp" `
    -Force `
    -ErrorAction SilentlyContinue |
    Remove-Item `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue


# ------------------------------------------------------------
# Clear WinGet diagnostic logs
# ------------------------------------------------------------

$WingetPackageRoot = `
    "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"


$WingetLogs = `
    "$WingetPackageRoot\LocalState\DiagOutputDir"


if (Test-Path $WingetLogs) {

    Remove-Item `
        "$WingetLogs\*" `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue


    Write-Host "[OK] Cleared WinGet diagnostic logs."
}


# ------------------------------------------------------------
# Empty Recycle Bin
# ------------------------------------------------------------

try {

    Clear-RecycleBin `
        -Force `
        -ErrorAction SilentlyContinue


    Write-Host "[OK] Recycle Bin cleared."
}
catch {
}


# ------------------------------------------------------------
# DISM component cleanup
#
# Do NOT use /ResetBase.
# Keep ability to uninstall current Windows updates.
# ------------------------------------------------------------

Write-Host ""
Write-Host "Running DISM StartComponentCleanup..."


$DISM = Start-Process `
    -FilePath "dism.exe" `
    -ArgumentList @(
        "/Online"
        "/Cleanup-Image"
        "/StartComponentCleanup"
        "/NoRestart"
    ) `
    -Wait `
    -PassThru `
    -NoNewWindow


if ($DISM.ExitCode -eq 0) {

    Write-Host "[OK] DISM cleanup completed."
}


if ($DISM.ExitCode -ne 0) {

    Write-Warning `
        "DISM cleanup returned exit code $($DISM.ExitCode)"
}


# ============================================================
# Final Summary
# ============================================================

Write-Host ""
Write-Host "=================================================="
Write-Host " Installation / Upgrade Summary"
Write-Host "=================================================="
Write-Host ""


$Results |
    Format-Table `
        Application,
        Status,
        Message `
        -AutoSize


$Failures = @(
    $Results |
        Where-Object {
            $_.Status -eq "Failed"
        }
)


Write-Host ""


if ($Failures.Count -gt 0) {

    Write-Warning `
        "$($Failures.Count) application operation(s) failed."

    exit 1
}


Write-Host "Golden Image application maintenance completed successfully."

exit 0
