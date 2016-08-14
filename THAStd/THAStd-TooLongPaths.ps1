<#
.SYNOPSIS

Function returns file paths that are longer than 260 characters.

.SYNTAX

.DESCRIPTION

.EXAMPLE 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>

function Get-TooLongPaths{
[CmdletBinding()] 
    param 
    ( 
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [System.IO.DirectoryInfo]$targetdir
    )

    begin {
        $failedPaths = New-Object System.Collections.ArrayList
        $ErrorActionPreference = "Stop"
    }
    process {
        try {
            foreach ($item in ($targetdir.GetDirectories() + $targetdir.GetFiles())) {
               if (($item.FullName) -and (Get-Item -LiteralPath $($item.FullName) -Force)){ 
                  if ($item.GetType() -eq [System.IO.DirectoryInfo]){
                    [System.Collections.ArrayList]$failedPaths += ($item | Get-TooLongPaths)   #if it's a directory, go deeper
                  }
               } else {
                  if (($targetdir.FullName.Length + $item.Name.Length + 1) -ge 260){
                    $failedPaths.Add($targetdir) | Out-Null
                  }
                  # if could not get fullname, its failed, TODO
               }
            }
        } catch {
            if  ($_.FullyQualifiedErrorId -eq "PathTooLongException") {
                $failedPaths.Add($targetdir) | out-null
            } else {
                Write-Error  "Something went wrong while getting the deepest paths of $targetdir | $($_.Exception.Message)"
                break
            }
        }
    }
    end {
        return ($failedPaths | Get-Unique)
    }
}
