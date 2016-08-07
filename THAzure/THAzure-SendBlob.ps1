<#
.SYNOPSIS

Function sends a blob to the Azure storage container

.SYNTAX

.DESCRIPTION

.EXAMPLE 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Send-BlobToAzure {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$FileInfo, 

        [Parameter(ParameterSetName=’AuthMethod1’,Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [string]$StorageAccountName,
        [Parameter(ParameterSetName=’AuthMethod1’,Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [string]$StorageAccountKey,
        [Parameter(ParameterSetName=’AuthMethod2’,Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [string]$ConnectionString,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()] 
        [string]$ContainerName,

        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$timeout = 30,

        [Parameter()] 
        [switch]$preserve
    )

    begin {
        switch ($PsCmdlet.ParameterSetName){
            "AuthMethod1" { $ctx = New-AzureStorageContext `
                            -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey }
            "AuthMethod2" { $ctx = New-AzureStorageContext `
                            -ConnectionString $ConnectionString }
        }
    }

    process {
        $stop = $false
        do {
            try {
                Set-AzureStorageBlobContent -File $FileInfo.FullName -Container $ContainerName `
                    -Blob $FileInfo.Name -Context $ctx -ErrorAction Stop
                $stop = $true
            }
            catch {
                if ($retry_count -gt 3){
                    Write-Error "Could not upload to the Azure. Giving up..."
                    $stop = $true
                } else {
                    Write-Warning "Problem occured while uploading to the Azure. Retry in $timeout seconds"
                    Start-Sleep $timeout
                    $retry_count++
                }
            }
        } while (! $stop)

        if (! $preserve) {
            Remove-Item $FileInfo
        }
    }
}
