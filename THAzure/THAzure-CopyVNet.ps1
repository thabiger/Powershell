function Copy-AzureVNet {
<#
.SYNOPSIS

Function reads the content of the specified VNet from one Subscription and merges it with another Subscription's Network Configuration

.DESCRIPTION

Function reads the content of the specified VNet from one Subscription and merges it with another Subscription's Network Configuration

.EXAMPLE 

Copy-VNet -SrcSubscriptionName "Source Subscription Name" `
          -DstSubscriptionName "Destination Subscription Name" `
          -VNetName "Source VNet name" 
          -BackupPath "Backup path on local drive"

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: Oct 2015

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $SrcSubscriptionName,
        [Parameter(Mandatory=$true)]
        [string]
        $DstSubscriptionName,
        [Parameter(Mandatory=$true)]
        [string]
        $VNetName,
        [Parameter()]
        [string]
        $BackupPath
    )
    
    function Get-VNetXML {
    <#
    .SYNOPSIS

    Function returns XML with VNet config from specified Subscription with the addition of the Namespace

    #>
        param(
            [Parameter(Mandatory=$true)]
            [string]
            $SubscriptionName
        )

        Select-AzureSubscription -SubscriptionName $SubscriptionName
        $xml = [xml](Get-AzureVNetConfig).XMLConfiguration
        if ($xml -ne $null){
            $ns = New-Object XML.XMLNamespaceManager $xml.NameTable
            $ns.AddNamespace("x", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")    
        } else {
            #TODO            
            Write-Verbose "There is no VNET configured in the subscription"
            break
        }
        $xml  | Add-Member -MemberType NoteProperty -Name ns -Value $ns -PassThru
    }

    function Join-VNetElements {
    <#
    .SYNOPSIS

    Function merges the first VNet configuration(os1) with the second one (os2)

    #>
        param(
            [Parameter(Mandatory=$true)]
            [System.Xml.XmlNode]
            $os1,
            [Parameter(Mandatory=$true)]
            [System.Xml.XmlNode]
            $os2,
            [Parameter(Mandatory=$true)]
            [string]
            $VNetName,
            [Parameter()]
            [switch]
            $PassThrough
        )

        #check if the VNet of such name does not exist at the destinat
        if ($os2.SelectSingleNode("//x:VirtualNetworkSite[@name='$($VNetName)']", $os2.ns)) {
            Write-Verbose "VNet $VNetName already exists at the destination!"
            break
        }

        $i_VNETSite = $os1.SelectSingleNode("//x:VirtualNetworkSite[@name='$($VNetName)']", $os1.ns)
        $r = $os2.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.AppendChild($os2.ImportNode($i_VNETSite, $true));

        # Add DNS records
        if (-not ($nodeDns = $os2.NetworkConfiguration.VirtualNetworkConfiguration.dns.DnsServers)){
            $nodeDns = $os2.CreateNode("element", "DnsServers", ($os2.ns).LookupNamespace("x"));
            $nodeNew = $true
        }
        foreach ($ref in $i_VNETSite.DnsServersRef.ChildNodes){
            # if DNS server of such name doesn't exist at the destination already
            if (-not $os2.SelectSingleNode("//x:DnsServer[@name='$($ref.name)']", $os2.ns)) {
                $import = $os1.SelectSingleNode("//x:DnsServer[@name='$($ref.name)']", $os1.ns)
                $r = $nodeDns.AppendChild($os2.ImportNode($import, $true));
            }
        }
        if ($nodeNew) { $r = $os2.SelectSingleNode("//x:Dns", $os2.ns).AppendChild($os2.ImportNode($nodeDns, $true)) }

        # Add LocalNetwork records
        if (-not ($nodeLocalNetworkSites = $os2.NetworkConfiguration.VirtualNetworkConfiguration.LocalNetworkSites)){
            $nodeLocalNetworkSites = $os2.CreateNode("element", "LocalNetworkSites", ($os2.ns).LookupNamespace("x"));
            $nodeNew = $true
        }
        foreach ($ref in $i_VNETSite.Gateway.ConnectionsToLocalNetwork.ChildNodes){
            if (-not $os2.SelectSingleNode("//x:LocalNetworkSite[@name='$($ref.name)']", $os2.ns)){
                $import = $os1.SelectSingleNode("//x:LocalNetworkSite[@name='$($ref.name)']", $os1.ns)
                $r = $nodeLocalNetworkSites.AppendChild($os2.ImportNode($import, $true));
            }
        }
        $os2.SelectSingleNode("//x:VirtualNetworkConfiguration", $os2.ns).InsertAfter($nodeLocalNetworkSites, $os2.SelectSingleNode("//x:Dns", $os2.ns)) | Out-Null

        if ($PassThrough) { $os2 }
    }

    # Do the backup if path provided
    $os2 = Get-VNetXML -SubscriptionName $DstSubscriptionName
    if ($BackupPath) { 
        $filename = "{0}\{1}-{2}.xml" -f $BackupPath, $VNetName, (Get-Date -Format o | foreach { $_ -replace ":", "."})
        $os2.Save($filename)
    }
     
    $os2 = Join-VNetElements -os1 (Get-VNetXML -SubscriptionName $SrcSubscriptionName) `
                      -os2 $os2 `
                      -VNetName $VNetName `
                      -PassThrough
    
    $VNetConfigFile = [System.IO.Path]::GetTempFileName()
    $os2.Save($VNetConfigFile)
    Select-AzureSubscription -SubscriptionName $DstSubscriptionName
    Set-AzureVNetConfig -ConfigurationPath $VNetConfigFile
    Remove-Item $VNetConfigFile
}
