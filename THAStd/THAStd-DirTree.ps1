<#
.SYNOPSIS

Scripts calculates growth of subdirectories in the tree

.SYNTAX

.DESCRIPTION

.EXAMPLE 

measure-tree -root d:\ -depth 0 -startDate "05/10/2016" -endDate "05/12/2016"

if ($o = measure-tree -root d:\home -depth 0 -minGrowth 1 -minSize (500*1024*1024) -cmpObjPath d:\home.xml -overwrite |
    select -Property @{Name="Username";Expression={$_.name}}, @{Name="Size (MB)";Expression={[math]::round($_.size / 1Mb)}}, @{Name="Growth (%)";Expression={$_.growth}}) 
{
	Send-MailMessage -To $recipients -Subject $subject -from $sender -SmtpServer $SmtpServer -BodyAsHtml `
	-Body ([system.String]::Join("", ($o | ConvertTo-HTML)))  -Encoding ([System.Text.Encoding]::UTF8)
}

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: May 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>

function measure-tree(){
        [CmdletBinding()]
        param (
            [Parameter()]   
            [int] $depth = 0,
            [Parameter()]   
            [string] $root,
            [Parameter()]   
            [DateTime] $startDate,
            [Parameter()]   
            [DateTime] $endDate = (get-date),
            [Parameter()]   
            [string] $cmpObjPath,
            [Parameter()]   
            [switch] $overwrite,
            [Parameter()]   
            [int] $minGrowth = 0,
            [Parameter()]   
            [int] $minSize = 0
        )

    function measure-dir(){
        [CmdletBinding()]
        param (
            [Parameter()]   
            [string] $name,
            [Parameter()]   
            [int] $depth,
            [Parameter()]   
            [DateTime] $startDate,
            [Parameter()]   
            [DateTime] $endDate
        )

        Get-ChildItem $name | ? {$_.PSIsContainer} | ForEach-Object {
            if ($startDate){
                $cobjs = Get-ChildItem $_.FullName -recurse -force | where { $_.CreationTime -gt $startDate -and $_.CreationTime -lt $endDate}
                $_ | Add-Member -Type NoteProperty –Name growth –Value (($cobjs | Measure-Object -property length -sum).Sum)
            }
            $cobjs = Get-ChildItem $_.FullName -recurse -force
            $_ | Add-Member -Type NoteProperty –Name size –Value (($cobjs | Measure-Object -property length -sum).Sum) -PassThru
            $d = $depth
            if ($d) {
                $d--
                measure-dir -name $_.FullName -depth $d -startDate $startDate -endDate $endDate
            }
        }
    }

    if ($startDate){
        $r = measure-dir -name $root -depth $depth -startDate $startDate -endDate $endDate
    } else {
        $r = measure-dir -name $root -depth $depth
    }

    if ($cmpObjPath -and (Test-Path $cmpObjPath)) {
        $ir = Import-Clixml $cmpObjPath
        $r = Compare-Object $r $ir | ForEach-Object {
            if ($_.sideindicator -eq '<=') {
                $inputObject = $_.InputObject
                $old_size = ($ir | ? { $_.FullName -eq $inputObject.FullName}).size
                if ($old_size) { $growth = [math]::round(($inputObject.size / $old_size * 100) - 100)}
                $inputObject | Add-Member -Type NoteProperty –Name growth –Value $growth -PassThru
            }
        }
    }
    if ($overwrite -and $cmpObjPath) {
        $r | Export-Clixml $cmpObjPath
    }
    $r | ? { [math]::abs($_.growth) -ge $minGrowth -and $_.size -gt $minSize}
}

