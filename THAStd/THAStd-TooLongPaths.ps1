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
        $childs = $targetdir | Get-ChildItem -Attributes Directory, Directory+Hidden, !Directory, !Directory+Hidden  | foreach {
            try {
                $item = Get-Item -LiteralPath "$($_.FullName)" -Force
                if (($item) -and ($item.GetType() -eq [System.IO.DirectoryInfo])){
                    $failedPaths += ($item | Get-TooLongPaths)
                }
            } catch {
                if ($_.CategoryInfo.Reason -eq "PathTooLongException") {
                    $failedPaths.Add($item)
                }
            }
        }
    }
    end {
        return $failedPaths
    }
}
