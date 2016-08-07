<#
.SYNOPSIS

Script makes a zip archive of every profile that account is disabled or does no longer exist in AD and removes it

.SYNTAX

.DESCRIPTION

.EXAMPLE 

Archive-Profile -ProfilePathBaseDir "E:\Users" `
    -ProfileArchiveBasePath "E:\ArchivedProfiles" `
    -Exclude ("Default", "User1") `
    -Verbose -Force

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: June 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Compress-Profile(){
    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact="High"
    )]
    param (
        [Parameter(Mandatory=$true)]   
        [string] $ProfilePathBaseDir,
        [Parameter(Mandatory=$true)]   
        [string] $ProfileArchiveBasePath,
        [Parameter()]   
        [string] $CompressionLevel = "Optimal",
        [Parameter()]   
        [string[]] $Exclude = @("Default"),
        [switch] $Force
    )

    function CompressProfile( $zipfilename, $sourcedir )
    {
       Add-Type -Assembly System.IO.Compression.FileSystem
       $compressionLevel = [System.IO.Compression.CompressionLevel]::$CompressionLevel
       [System.IO.Compression.ZipFile]::CreateFromDirectory($sourcedir,
            $zipfilename, $compressionLevel, $false)
    }

    function Remove-IfEmpty($path){
        if ((Get-ChildItem $path | Measure-Object).Count -eq 0) {
            Write-Verbose "Removing empty profile: $path"
            Remove-Item $path
            retun 1
        } 
        return 0
    }

    function Remove-ReparsePoints($path){
        Get-ChildItem $path -Attributes Directory+Hidden+ReparsePoint, Directory+ReparsePoint -Recurse | ForEach-Object {
            cmd /c rd "$($_.FullName)"
        }
    }

    function Archive(){
        [CmdletBinding(
            SupportsShouldProcess=$true,
            ConfirmImpact="High"
        )]
        param (
            [Parameter(Mandatory=$true)]   
            [string] $ProfilePath, 
            [Parameter(Mandatory=$true)]   
            [string] $ProfileArchivePath,
            [switch] $Force
        )

     if($Force -or $PSCmdlet.ShouldProcess("Processing: $($ProfilePath)")) {
        try {
            Remove-ReparsePoints($ProfilePath)
            Write-Verbose "Compressing: $($ProfilePath) to $($ProfileArchivePath).zip"
            CompressProfile "$($ProfileArchivePath).zip" $ProfilePath
        } catch {
            Write-Verbose "Fatal error while processing $($ProfilePath)"
            Break;
        }
        Remove-Item $ProfilePath -Recurse -Force
      }
    }


    Get-ChildItem $ProfilePathBaseDir -Directory | foreach {
    
        $ProfileName = $_ -replace "\..*", ""
        $ProfilePath = “{0}\{1}” -f $ProfilePathBaseDir, $_
        $ProfileArchivePath = “{0}\{1}” -f $ProfileArchiveBasePath, $_

        if (($ProfileName -notin $Exclude) -and (-not (Get-ADUser -Filter {SamAccountName -eq $ProfileName} ))){
            Write-Verbose "Orphaned profile: $($_)"
        } elseif (($ProfileName -notin $Exclude) -and (-not (Get-ADUser -Filter {SamAccountName -eq $ProfileName}).Enabled )){
            Write-Verbose "Disabled profile: $($_)"
        } else { continue }
        if ( -not (Remove-IfEmpty($ProfilePath))) {
            if ($Force) { Archive $ProfilePath $ProfileArchivePath -Force } 
                 else { Archive $ProfilePath $ProfileArchivePath } 
        }
    }
}

