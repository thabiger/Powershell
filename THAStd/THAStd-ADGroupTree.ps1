<#
.SYNOPSIS

Script displays Active Directory group tree with specified object's class members. It also marks groups that has a circular membership. 

.SYNTAX

.DESCRIPTION

.EXAMPLE 

Get-ADGroupTree -SearchBase "OU=Groups,DC=domain,DC=local" -ObjectClasss User

Get-ADGroupTree -ObjectClasss User,Computer

Possible result:

+ All Workers [CIRCULAR MEMBERSHIP!]
  + Jon Doe
  + Joan Doe
+ CAMs
  + Joan Doe
+ Technicians
  + Jon Doe
+ Manuals - view
  + Service Manuals - RW
  + Service Manuals - RO
  + ...

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: July 2016

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>
function Get-ADGroupTree {
    [CmdletBinding()] 
      param ( 
        [Parameter()] 
        [string] $SearchBase,
        [Parameter()] 
        [string[]] $ObjectClasss = @("none")
      ) 

    function ContainsObject($collection, $object){
        foreach ($o in $collection) {
            if (! (Compare-Object $o $object)){
                return $true
            }
        }
    }

    function Get-RootGroup{
      [CmdletBinding()] 
      param ( 
        [Parameter(ValueFromPipeline=$true)] 
        [Microsoft.ActiveDirectory.Management.ADPrincipal] $group,
        [Parameter()] 
        [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection] $parents = (New-Object -TypeName Microsoft.ActiveDirectory.Management.ADPropertyValueCollection)
      ) 
  
      process {
        if ($group.MemberOf) {
            if (!(ContainsObject $parents $group)) {
                $group.MemberOf | Get-ADGroup -Properties MemberOf | Get-RootGroup -parents (New-Object Microsoft.ActiveDirectory.Management.ADPropertyValueCollection(,($parents + $group)))
            } else {
                write-verbose "$($group.name) is circular"
                $group | Add-Member -MemberType NoteProperty -Name isCircular -Value $true -Force -PassThru
            }
        } else {
            $group
        }
      }
    }

    function Get-SubGroups{
      [CmdletBinding()] 
      param ( 
        [Parameter(ValueFromPipeline=$true)] 
        [Microsoft.ActiveDirectory.Management.ADPrincipal] $group,
        [Parameter()] 
        [System.Collections.Arraylist] $parents = (New-Object -TypeName System.Collections.Arraylist),
        [Parameter()] 
        [int] $level = 0
      ) 
  
      process {
          
          if (!(ContainsObject $parents $group)) {
            $group | Add-Member -MemberType NoteProperty -Name level -Value $level -Force -PassThru |
              Add-Member -MemberType NoteProperty -Name Members -Value ($group | Get-ADGroupMember) -Force -PassThru
            
            if ($group.isCircular) { return } 

            $parents.Add($group) | Out-Null
            $group | Get-ADGroupMember | ? { $_.objectClass -eq "group" } |
              Get-SubGroups -level ($level+1) -parents ($parents)
          }
      }
    }

    function Show-GroupTree{
      [CmdletBinding()] 
      param ( 
        [Parameter(ValueFromPipeline=$true)] 
        [Microsoft.ActiveDirectory.Management.ADPrincipal] $group,
        [Parameter()] 
        [string[]] $ObjectClasss
      ) 
  
      process {
       
          $line = "  " * $group.level + "+ $($group.name)"
          if ($group.isCircular) { $line += "[CIRCULAR MEMBERSHIP!]" }
          write-output $line
          foreach ($m in $group.Members) {
                if ($m.objectClass -in $ObjectClasss) {
                    $line = "  " * ($group.level + 1) + "+ $($m.name)"
                    write-output $line
                }
          }
      }
    }

    if ($SearchBase){
        Get-ADGroup -SearchBase $SearchBase -Filter "*" -Properties MemberOf |
          Get-RootGroup | Get-SubGroups | Show-GroupTree -ObjectClasss $ObjectClasss
    } else {
        Get-ADGroup -Filter "*" -Properties MemberOf |
          Get-RootGroup | Get-SubGroups | Show-GroupTree -ObjectClasss $ObjectClasss
    }
}
