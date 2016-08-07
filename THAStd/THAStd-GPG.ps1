<#
.SYNOPSIS

Set of functions providing GNU GPG support

.SYNTAX

.DESCRIPTION

.EXAMPLE 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Install-GnuPg 
{ 
    [CmdletBinding()] 
    param 
    ( 
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$DownloadUrl = 'https://files.gpg4win.org/gpg4win-vanilla-2.3.2.exe' 
         
    ) 
        if ([float]$PSVersionTable.PSVersion.Major -ge 5){
            $installFile = New-TemporaryFile
        } else {
            $installFile = $env:TMP + "\" + [System.Guid]::NewGuid()
        }

        if (! (Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | ? {$_.DisplayName -match "Gpg4win" })){
            try 
            { 
                Write-Verbose -Message "Downloading [$($DownloadUrl)] $($installFile)"  
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $installFile
            
                Write-Verbose -Message 'Attempting to install GPG4Win...' 
                Start-Process -FilePath $installFile -ArgumentList '/S' -NoNewWindow -Wait -PassThru 
                Write-Verbose -Message 'GPG4Win installed'
                Remove-Item $installFile 
            } 
            catch 
            { 
                Write-Error $_.Exception.Message 
            } 
        } else {
                Write-Verbose -Message 'Gpg4win already installed!'
        }
} 

function Add-Encryption 
{     
    [CmdletBinding()]
    param 
    ( 
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileInfo]$FileInfo, 

        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$recipient,
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$password,
     
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$GpgPath = 'C:\Program Files (x86)\GNU\GnuPG\gpg2.exe',
        [Parameter()] 
        [switch]$preserve  
    )
    process { 
        Write-Verbose "Encrypting $($FileInfo)"
        try 
        { 
                $startProcParams = @{ 
                    'FilePath' = $GpgPath 
                    'ArgumentList' = "--batch --yes -c $($FileInfo.Fullname)"  
                    'Wait' = $true 
                    'NoNewWindow' = $true 
                } 
                if ($recipient) { $startProcParams.ArgumentList = "-r '$recipient' " + $startProcParams.ArgumentList }
                if ($password) { $startProcParams.ArgumentList = "--passphrase $password "  + $startProcParams.ArgumentList }
                Start-Process @startProcParams -ErrorAction Stop
        } 
        catch 
        { 
            Write-Error $_.Exception.Message 
            Break
        } 

        if (! $preserve) {
            Remove-Item $FileInfo
        }

        Get-Item "$($FileInfo.Fullname).gpg"
    } 
} 

function Remove-Encryption 
{ 
    [CmdletBinding()] 
    param 
    ( 
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$FileInfo, 
         
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$recipient,
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$password,
         
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$GpgPath = 'C:\Program Files (x86)\GNU\GnuPG\gpg2.exe' 
    ) 
    process 
    { 
        try 
        { 
                $decryptFilePath = ($($FileInfo.Fullname) -replace '.gpg') + ".enc"
                Write-Verbose -Message "Decrypting [$($FileInfo.FullName)] to [$($decryptFilePath)]" 
                
                $startProcParams = @{ 
                    'FilePath' = $GpgPath 
                    'ArgumentList' = "--batch --yes -o $decryptFilePath -d $($FileInfo.FullName)"  
                    'Wait' = $true 
                    'NoNewWindow' = $true 
                } 
                if ($recipient) { $startProcParams.ArgumentList = "-r '$recipient' " + $startProcParams.ArgumentList }
                if ($password) { $startProcParams.ArgumentList = "--passphrase $password "  + $startProcParams.ArgumentList }

                Start-Process @startProcParams 
        } 
        catch 
        { 
            Write-Error $_.Exception.Message 
        } 
    } 
}