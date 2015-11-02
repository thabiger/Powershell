Import-Module "THAStd"

$psfiles = Get-ChildItem -Recurse $PSScriptRoot -Include *.ps1
foreach ($psfile in $psfiles) { . $psfile.FullName }