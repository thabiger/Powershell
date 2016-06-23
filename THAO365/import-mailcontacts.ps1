<#
.SYNOPSIS

Script imports contacts exported from an Outlook address book to the Exchange Online MailContacts

.SYNTAX

.DESCRIPTION

.EXAMPLE 

$Cred = Get-Credential
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell/ -Credential $Cred -Authentication Basic –AllowRedirection
Import-PSSession $Session

import-mailcontacts -csvfile C:\Users\thabiger\Documents\kontakty.csv -bulkmail_domain "example.com"

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: June 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>


function import-mailcontacts(){
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]   
        [string] $csvfile,
        [Parameter()]   
        [string] $bulkmail_domain = "example.com"
    )

    function cut-string(){
        param(
            [Parameter(Mandatory=$true)]   
            [string] $s,
            [Parameter()]   
            [int] $len = 64
        )

        $len =- 3
        if ($len -lt 0) {$len = 3}

        if ($s.Length -ge $len){
            $s.Substring(0, $len) + "..."
        } else {
            $s
        }
    }

    $tmpfile = [System.IO.Path]::GetTempFileName()
    Get-Content $csvfile | ForEach-Object {
        $_ -replace "%",""
    } | Set-Content -Encoding utf8 $tmpfile 
    $Contacts = Import-Csv $tmpfile

    foreach ($c in $Contacts) {

        $c.PSObject.Properties | Foreach-Object {$_.Value = $_.Value.Trim()} 

        $c.'Adres e-mail' = $c.'Adres e-mail' -replace " .*",""
        if ($c.'Firma') { $c.'Firma' = cut-string($c.'Firma') }

        $name = $($c.'Adres e-mail' -replace "@.*","")
        if (!$name)
        { 
            $name = $c.'Nazwa' -replace '\s+',"" -replace ",",""
            $c.'Adres e-mail' = "$([guid]::NewGuid())@$($bulkmail_domain)"   
        }

        $displayName = "$($c.'Imię') $($c.'Nazwisko')".trim() -or $name
        if (!$displayName) { continue }
 
        New-MailContact -Name $name -DisplayName $displayName -ExternalEmailAddress $c.'Adres e-mail' -FirstName $c.'Imię' -LastName $c.'Nazwisko'
        Get-MailContact | ? { $c.Name -eq $name } | Set-Contact -StreetAddress $c.'Adres Służbowy' `
            -Phone $c.'Telefon służbowy' `
            -MobilePhone $c.'Telefon komórkowy' `
            -Company $c.'Firma' `
            -Title $c.'Stanowisko' `
            -Fax $c.'Faks służbowy'
    }
}
