.<#
.SYNOPSIS

Set of functions providing file-level deduplication

.SYNTAX

.DESCRIPTION

.EXAMPLE

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Get-MD5 {
    [CmdletBinding()] 
    param (
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [String]$Path
    )
    # This Get-MD5 function sourced from: http://blogs.msdn.com/powershell/archive/2006/04/25/583225.aspx
    $HashAlgorithm = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        $HashByteArray = $HashAlgorithm.ComputeHash($Stream)
    } finally {
        $Stream.Dispose()
    }

    return [System.BitConverter]::ToString($HashByteArray).ToLowerInvariant() -replace '-',''
}


# This function is based on the solution described at: https://blog.stangroome.com/2007/10/13/find-duplicate-files-with-powershell/
function Get-DuplicatedFiles {
    [CmdletBinding()] 
    param (
        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$targetdir
    )

    # get current dir
    if (-not $targetdir) {
        if ((Get-Location).Provider.Name -ne 'FileSystem') {
            Write-Error 'Specify a file system path explicitly, or change the current location to a file system path.'
            return
        }
        $targetdir = (Get-Location).ProviderPath | Get-Item
    }

    $targetdir | Get-ChildItem -Recurse -File |
        ? { $_.Length -gt 0 } | Group -Property Length | ? { $_.Count -gt 1 } | % { $_.Group } |  #find all the files that are the same size
        % { $_ | Add-Member -MemberType NoteProperty -Name ContentHash -Value (Get-MD5 -Path $_.FullName) -PassThru } | # and count MD5 for them
        group -Property ContentHash | ? { $_.Count -gt 1 } # then group again by the ContentHash property an pick those that are duplicated

}

function Get-DuplicatedFilesSize {
    [CmdletBinding()] 
    param (
        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [Microsoft.PowerShell.Commands.GroupInfo[]]$duplicationList,
        [Parameter(HelpMessage = "Minimal size in MB for file to be deduped")] 
        [ValidateNotNullOrEmpty()]
        [Int]$MinSize = 0
    )

    begin {
        $overall_size = 0;
    }

    process {
        foreach ($duplicate in $duplicationList) {
            $count = 0
            foreach ($dfile in $duplicate.Group) {
                if (($dfile.Name -notmatch ".dedup$") -and ($dfile.Length -gt ($MinSize * 1024 * 1024))) {
                    if ($count -gt 0) {
                        $overall_size += $dfile.length
                    }
                    $count++
                } else {
                    continue
                }
            }
        }
    }

    end {
        "{0:N2}" -f ($overall_size / 1024 / 1024)
    }
}

function Convert-DuplicatedFilesToPlaceholders {
    [CmdletBinding()] 
    param (
        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [Array]$duplicationList,
        [Parameter(HelpMessage = "Minimal size in MB for file to be deduped")] 
        [ValidateNotNullOrEmpty()]
        [Int]$MinSize = 0
    )

    begin {
        $ErrorActionPreference = "Stop"
    }

    process {
        foreach ($duplicate in $duplicationList) {
            $count = 0
            foreach ($dfile in $duplicate.Group) {
                if (($dfile.Name -notmatch ".dedup$") -and ($dfile.Length -gt ($MinSize * 1024 * 1024))) {
                    if ($count -eq 0) {
                        $dfileinfo = $dfile | ConvertTo-Xml 
                    } else {
                        $dfileinfo.Save("$($dfile.Fullname).dedup")
                        $dfile | Remove-Item
                    }
                    $count++
                } else {
                    continue
                }
            }
        }
    }
}

function Convert-DedupPlaceholdersToFiles {
    [CmdletBinding()] 
    param (
        [Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$targetdir
    )

    begin {
        $ErrorActionPreference = "Stop"
    }

    process {
         Get-ChildItem -File $targetdir -Include @("*.dedup") -Recurse | % {
         
            $object = [XML] (Get-Content $_.FullName -Encoding UTF8)
            Copy-Item ($object.SelectSingleNode("/Objects/Object/Property[@Name='PSPath']").InnerText | get-item) ($_.FullName -replace ".dedup$")
            $_ | Remove-Item
         }
    }
}
