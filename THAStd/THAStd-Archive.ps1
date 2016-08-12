<#
.SYNOPSIS

Function makes an zip archive from the specified directory

.SYNTAX

.DESCRIPTION

.EXAMPLE 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>

function Compress-IonicDirectory{
   [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$sourcedir,
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$zipfilename,
        [Parameter()] 
        [ValidateNotNullOrEmpty()]
        [ValidateSet("BestCompression","BestSpeed","Default","Level0","Level1","Level2","Level3","Level4","Level5","Level6","Level7","Level8","Level9","None")] 
        [string]$compressionLevel = "BestCompression",
        [Parameter()] 
        [switch]$preserve,
        [Parameter(
            HelpMessage="Maximum sie of the split in MB")] 
        [ValidateNotNullOrEmpty()]
        [ValidateRange(1,2048)]
        [int]$MaxOutputSegmentSize
    )

    process {

        [System.Reflection.Assembly]::LoadFrom("C:\Program Files\WindowsPowerShell\Modules\Ionic.Zip.dll") | Out-Null
        $zipfile = new-object Ionic.Zip.ZipFile;
        $zipfile.UseZip64WhenSaving = [Ionic.Zip.Zip64Option]::Always
        $zipfile.CompressionLevel =  [Ionic.Zlib.CompressionLevel]::$compressionLevel
        $zipfile.ParallelDeflateThreshold = -1

        if (! $zipfilename){
            $zipfilename = $sourcedir.FullName + ".zip"
        }
        if ($MaxOutputSegmentSize) { $zipfile.MaxOutputSegmentSize = $MaxOutputSegmentSize * 1024 * 1024 - 1 }
   
        try {
            $ErrorActionPreference = "Stop"
            $zipfile.AddDirectory($sourcedir.FullName)
            $zipfile.Save($zipfilename)
            $zipfile.Dispose()
        } catch {
                Write-Error $_.Exception.Message
                Break
        }

        if (! $preserve) {
            Remove-Item -Recurse -Force $sourcedir
        }

        get-item $zipfilename
    }
}


function Compress-Directory
{
    [CmdletBinding()] 
    param 
    ( 
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$sourcedir,
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [string]$zipfilename,
        [Parameter()] 
        [ValidateNotNullOrEmpty()] 
        [System.IO.Compression.CompressionLevel]$compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal,
        [Parameter()] 
        [switch]$preserve
    )
   
    process {

        if (! $zipfilename){
            $zipfilename = $sourcedir.FullName + ".zip"
        }

        Add-Type -Assembly System.IO.Compression.FileSystem
   
        try {
            $ErrorActionPreference = "Stop"
            [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir,
                $zipfilename, $compressionLevel, $false)
        } catch {
                Write-Error $_.Exception.Message
                Break
        }

        if (! $preserve) {
            Remove-Item -Recurse -Force $sourcedir
        }

        get-item $zipfilename
    }
}


<#
.SYNOPSIS

Function will flat the target directory by moving paths longer than 260 characters to the .flatten dir. 
It allows to make an archive of the directory. Operation can be undone by using the Remove-FlatDir function.

.SYNTAX

.DESCRIPTION

.EXAMPLE 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Add-FlatDir {
    [CmdletBinding()] 
    param 
    ( 
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$targetdir,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$logdir,
        [Parameter()] 
        [ValidateNotNullOrEmpty()]
        [string]$jobname = "unknown"
    )

    begin {
        $flattened = New-Object System.Collections.ArrayList
        $datetime_suffix = "_$(Get-Date -f yyyy.MM.dd-HH.mm)"
        $logfile = $logdir + $jobname + "-" + "flatlog$datetime_suffix.txt"
        $robocopyParams = @('/E','/B','/MOVE',"/LOG+:$logfile")
        $ErrorActionPreference = "Stop"
    }

    process {

        if (Test-Path $targetdir/.flattened -PathType Container) {
            $flatDir = Get-Item $targetdir/.flattened
        } else {
            $flatDir = New-Item -Path "$targetdir/.flattened" -ItemType Directory
        }

        $targetdir | Get-THATooLongPaths | ForEach-Object {
                $sufix = -join( 1..8 | % { ([char]((65..90) + (97..122) | Get-Random))})
                $object = Get-Item -LiteralPath $_.FullName -Force
                if ($object.GetType() -eq [System.IO.FileInfo]){
                    $object = if ($object.PSParentPath | Test-Path) { 
                        $object.PSParentPath | Get-Item
                    } else { 
                        continue   #that means that parent directory was already processed 
                    }
                }
                try {
                    ((robocopy $object.FullName "$flatDir\$($object.name)-$sufix" $robocopyParams)) | Out-Null
                    $object | Export-Clixml "$flatDir\$($object.name)-$sufix\.flatinfo.xml"
                } catch {
                    Write-Error "Something went wrong while flattening directory: $targetdir |  $($_.Exception.Message)"
                    Break
                }
        }
    }
}

<#
.SYNOPSIS

Function rollbacks the Add-FlatDir operation.

.SYNTAX

.DESCRIPTION

.EXAMPLE 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: August 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Remove-FlatDir {
    [CmdletBinding()] 
    param 
    ( 
        [Parameter(Mandatory,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ })] 
        [System.IO.FileSystemInfo]$targetdir,
        [Parameter(Mandatory)] 
        [ValidateNotNullOrEmpty()]
        [string]$logdir,
        [Parameter()] 
        [ValidateNotNullOrEmpty()]
        [string]$jobname = "unknown"
    )
    
    begin {
        $datetime_suffix = "_$(Get-Date -f yyyy.MM.dd-HH.mm)"
        $logfile = $logdir + $jobname + "-" + "unflatlog$datetime_suffix.txt"
        $robocopyParams = @('/E','/B','/MOVE',"/LOG+:$logfile")
    }

    process {
        Get-ChildItem $targetdir/.flattened | ? {$_.name -ne ".flattened"} | ForEach-Object {
            $object = Import-Clixml "$($_.FullName)/.flatinfo.xml"
            try {
                ((robocopy $_.FullName $object.Fullname $robocopyParams)) | Out-Null
                Remove-Item "$($object.FullName)/.flatinfo.xml"
            } catch {
                Write-Error "Something went wrong while unflattening directory: $targetdir |  $($_.Exception.Message)"
                Break
            }
        }
    }

}