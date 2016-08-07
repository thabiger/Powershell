<#
.SYNOPSIS

Function makes a full or differential backup of a directory on a network share. Additional options are:
    - make an archive of the backed up folder,
    - encrypt the archive,
    - send the encrypted archive to the Azure as a blob.

Function requires THAStd and THAzure modules.

.SYNTAX

Start-THABackup -type {full|differential} -name <String> -source <String> -dstpath <String> -logdir <String> [-archDays <Int>] [-compress] [-preserveSrcDir]

Start-THABackup -type {full|differential} -name <String> -source <String> -dstpath <String> -logdir <String> [-archDays <Int>] [-compress] [-preserveSrcDir] [[-encrypt] -password <String>]

Start-THABackup -type {full|differential} -name <String> -source <String> -dstpath <String> -logdir <String> [-archDays <Int>] [-compress] [-preserveSrcDir] [[-encrypt] -recipient <String>]

Start-THABackup -type {full|differential} -name <String> -source <String> -dstpath <String> -logdir <String> [-archDays <Int>] [-compress] [-preserveSrcDir] [[-encrypt] -recipient <String>] [-password <String>]]

Start-THABackup -type {full|differential} -name <String> -source <String> -dstpath <String> -logdir <String> [-archDays <Int>] [-compress] [-preserveSrcDir] [[-encrypt] -recipient <String>] [-password <String>]] [[-Azure] -ConnectionString <String> -ContainerName <String> [-preserveSrcDir]]

Start-THABackup -type {full|differential} -name <String> -source <String> -dstpath <String> -logdir <String> [-archDays <Int>] [-compress] [-preserveSrcDir] [[-encrypt] -recipient <String>] [-password <String>]] [[-Azure] -StorageAccountName <String> -StorageAccountKey <String> -ContainerName <String> [-preserveSrcDir]]

.DESCRIPTION

.EXAMPLE 

Start-THABackup -type full `
    -name "USERS" `
    -source C:\DSC `
    -dstpath \\fileserver\\Backup `
    -logdir C:\backup\logs\ `
    -archDays 15 `
    -encrypt -password "P@ssw0rd" `
    -Azure `
    -ConnectionString "DefaultEndpointsProtocol=https;AccountName=<account_name>;AccountKey=<key>" `
    -ContainerName "AzureStorageContainerName" `
    -preserveSrcDir

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Start-Backup {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] 
        [ValidateSet(“full”,”differential”)] 
        [string]$type,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$source,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$logdir,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$dstpath,
        [Parameter()] 
        [ValidateNotNullOrEmpty()]
        [int]$archDays = 0,
        [Parameter(ParameterSetName=’Compress’)] 
        [ValidateNotNullOrEmpty()]
        [switch]$compress,
        [Parameter(ParameterSetName=’Compress’)] 
        [Parameter(ParameterSetName=’Encrypt_AM1’)]
        [Parameter(ParameterSetName=’Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()]
        [switch]$preserveSrcDir,
        
        [Parameter(ParameterSetName=’Encrypt_AM1’)]
        [Parameter(ParameterSetName=’Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()]
        [switch]$encrypt,
        [Parameter(Mandatory,ParameterSetName=’Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Encrypt_AM2’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(Mandatory,ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()]
        [string]$password,
        [Parameter(ParameterSetName=’Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()]
        [string]$recipient,
        [Parameter(ParameterSetName=’Encrypt_AM1’)]
        [Parameter(ParameterSetName=’Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()]
        [switch]$preserveSrcArch,

        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()]
        [switch]$Azure,
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()] 
        [string]$StorageAccountName,
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()] 
        [string]$StorageAccountKey,
        [Parameter(Mandatory,ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()] 
        [string]$ConnectionString,
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(Mandatory,ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(Mandatory,ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()] 
        [string]$ContainerName,
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM1_Encrypt_AM2’)]
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM1’)] 
        [Parameter(ParameterSetName=’Azure_AM2_Encrypt_AM2’)]
        [ValidateNotNullOrEmpty()]
        [switch]$preserveSrcBlob
    )

    Write-Debug "Parameter set: $($PSCmdlet.ParameterSetName)"

    $backup =  Backup-Files -type $type `
            -name $name `
            -source $source `
            -dstpath $dstpath `
            -logdir $logdir `
            -archDays $archDays 
    $backup | Add-THAFlatDir -jobname $name -logdir $logdir 

    $Compress_A = @( { Compress-THADirectory } , { Compress-THADirectory -preserve } )[$preserveSrcDir.ToBool()]
        
    $Encrypt_AM1 = @( { Invoke-Command $Compress_A | Add-THAEncryption -password $password },
                      { Invoke-Command $Compress_A | Add-THAEncryption -password $password -preserve })[$preserveSrcArch.ToBool()]
  
    $Encrypt_AM2 = @( { Invoke-Command $Compress_A | Add-THAEncryption -recipient $recipient -password $password },
                      { Invoke-Command $Compress_A | Add-THAEncryption -recipient $recipient -password $password -preserve })[$preserveSrcArch.ToBool()]
  
    $Azure_AM1 = @( { Send-THABlobToAzure -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -ContainerName $ContainerName },
                    { Send-THABlobToAzure -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey -ContainerName $ContainerName -preserve })[$preserveSrcBlob.ToBool()]
  
    $Azure_AM2 = @( { Send-THABlobToAzure -ConnectionString $ConnectionString  -ContainerName $ContainerName },
                    { Send-THABlobToAzure -ConnectionString $ConnectionString  -ContainerName $ContainerName -preserve })[$preserveSrcBlob.ToBool()]

    $backup = switch ($PsCmdlet.ParameterSetName){
            "Compress" { $backup | Invoke-Command $Compress_A }
            "Encrypt_AM1" { $backup | Invoke-Command $Encrypt_AM1 }
            "Encrypt_AM2" { $backup | Invoke-Command $Encrypt_AM2 }
            "Azure_AM1_Encrypt_AM1" { $backup | Invoke-Command $Encrypt_AM1 | Invoke-Command $Azure_AM1 }
            "Azure_AM1_Encrypt_AM2" { $backup | Invoke-Command $Encrypt_AM2 | Invoke-Command $Azure_AM1 }   
            "Azure_AM2_Encrypt_AM1" { $backup | Invoke-Command $Encrypt_AM1 | Invoke-Command $Azure_AM2 }
            "Azure_AM2_Encrypt_AM2" { $backup | Invoke-Command $Encrypt_AM2 | Invoke-Command $Azure_AM2 }
    }   
}


<#
.SYNOPSIS

Function makes a full or differential backup of a directory on a network share

.SYNTAX

.DESCRIPTION

.EXAMPLE 

Backup-Files -type full `
    -name "DOCUMENTS" `
    -source C:\Documents `
    -dstpath \\fileserver\backup `
    -logdir C:\backup\logs\ `
    -archDays 15 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Backup-Files {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] 
        [ValidateSet(“full”,”differential”)] 
        [string]$type,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$name,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$source,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$logdir,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$dstpath,
        [Parameter()] 
        [ValidateNotNullOrEmpty()]
        [int]$archDays = 0
    )

    $Now = Get-Date 
    $LastWrite = $Now.AddDays(-$archDays)
    $Directories = Get-Childitem $dstpath | Where {$_.LastWriteTime -le "$LastWrite"}

    if ($archDays -gt 0){
        foreach ($Directory in $Directories) 
        {
	        if (($Directory) -and ($type -eq "full")) {
		        $delpath = $dstpath + "\" + $Directory
		        Write-Verbose "Usuwanie kopii: $delpath"
	    	    Remove-Item $delpath -Recurse -Force
	        }
        }
    }

    $cmds = New-Object System.Collections.ArrayList

    $datetime_suffix = "_$(Get-Date -f yyyy.MM.dd-HH.mm)"
    $dirname = $name + $datetime_suffix

    switch ($type) 
        {
	        differential {
			    $dirname += "-differential"
			    Write-Verbose "Creating differential backup $dirname..."
			    $dirname = $dstpath + "\" + $dirname
                New-Item -ItemType directory -Path $dirname 

			    $cmds.Add("robocopy " + $source + " $dirname\ /E /A /R:0 /W:0 /LOG+:" + $logdir + $name + "-" + "backuplog$datetime_suffix.txt") | out-null

		    } 
            full {
			    $dirname += "-full"
			    Write-Verbose "Creating full backup $dirname..."
			    $dirname = $dstpath + "\" + $dirname
			    New-Item -ItemType directory -Path $dirname 

			    $cmds.Add("attrib +A " + $source + "\*.* /S /D") | out-null
			    $cmds.Add("robocopy " + $source + " $dirname\ /E /M /R:0 /W:0 /LOG+:" + $logdir + $name + "-" + "backuplog$datetime_suffix.txt") | out-null
			} 
            default {
                Write-Error "Wrong type of backup provided"
            }
        }

        foreach ($cmd in $cmds) {
            Write-Verbose $cmd
            try {
                Invoke-Expression $cmd | out-null
            } 
            catch {
                Write-Error $_.Exception.Message 
            }
        }
        get-item $dirname
}


