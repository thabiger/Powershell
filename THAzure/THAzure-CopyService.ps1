function Copy-AzureService{

<#
.SYNOPSIS

Function copies entire Cloud Service from one Azure subscription to another

.DESCRIPTION

Function copies all Cloud Service's VMs from one Azure subscription to another in the following steps:
1. Sub-Function Get-ServiceVM gets information about every VM working in the specified source Cloud Service/Subscription.
2. For each identified VM, sub-function Test-VMExistsAtDs checks if VM of the same name does not exist in the destined Cloud Service/Subscription. If it does, such VM is throwed away from collection.
3. Sub-Function Copy-VM copies blobs that belongs to collected VMs and registers Azure disks in the destined Cloud Service/Subscription under their original names. If blob of such name already exists whole process is given up.
4. Sub-Function Add-VM registers VM based on the original configuration in the destined Cloud Service/Subscription.

If VMs use Virtual Networks, Subnets or Internal Load Balancers, those network-related configurations need to be recreated at the destination before they are migrated.

.EXAMPLE 

Copy-AzureService -SrcServiceName "Source Service Name" `
                  -SrcSubscriptionName "Source Subscription Name" `
                  -DstServiceName "Destination Service Name" `
                  -DstSubscriptionName "Destination Subscription Name" `
                  -DstStorageAccountName "Destination Storage Account Name" `
                  -VNetName "Destionation Virtual Network Name" `
                  -ExcludedVMs "Excluded VM nr 1 Name", "Excluded VM nr 2 Name" `
                  -Verbose 

.NOTES

Author: Tomasz Habiger <tomasz.habiger@gmail.com>
Date: Oct 2015

The content of this script is copyrighted to the author. It is provided AS IS, and no warranty of ANY kind is provided. Use it at your own risk!

#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $SrcServiceName,
        [Parameter(Mandatory=$true)]
        [string]
        $DstServiceName,
        [Parameter(Mandatory=$true)]
        [string]
        $SrcSubscriptionName,
        [Parameter(Mandatory=$true)]
        [string]
        $DstSubscriptionName,
        [Parameter(Mandatory=$true)]
        [string]
        $DstStorageAccountName,
        [Parameter()]
        [string[]]
        $ExcludedVMs,
        [Parameter()]
        [string]
        $VNetName
    )
    
    function Get-ServiceVM{
    <#
    .SYNOPSIS

    Function collects information about virtual machines working in the specified Service/Subscription. It expands VM object on attributes:
        - related config file path(for further import),
        - name of the source subscription

    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string]
            $ServiceName,
            [Parameter(Mandatory=$true)]
            [string]
            $SubscriptionName,
            [Parameter()]
            [string[]]
            $ExcludedVMs
        )
        
        Select-AzureSubscription -SubscriptionName $SubscriptionName
        Get-AzureVM -ServiceName $ServiceName | ? { $ExcludedVMs -NotContains $_.Name } |
            Add-Member -MemberType NoteProperty -Name SrcSubscriptionName -Value $SubscriptionName -PassThru |
            ForEach-Object { 
                #get a vm config...
                $VMConfigFile = [System.IO.Path]::GetTempFileName()
                $r = $_ | Export-AzureVM -Path $VMConfigFile
                $_ | Add-Member -MemberType NoteProperty -Name ConfigFile -Value $VMConfigFile -PassThru
            }
    }
    
    function Test-VMExistsAtDst{
    <#
    .SYNOPSIS

    Function checks if VM of the same name does not exist in the destined Cloud Service/Subscription and removes it from the collection if it does. It expands VM object on attributes:
        - Destination: Subscription Name, Service Name, Storage Account Name

    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string]
            $ServiceName,
            [Parameter(Mandatory=$true)]
            [string]
            $SubscriptionName,
            [Parameter(Mandatory=$true)]
            [string]
            $StorageAccountName,
            [Parameter(Mandatory=$true, ValueFromPipeline = $true)]
            [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.ServiceOperationContext]
            $VM
        )

        begin {
            Select-AzureSubscription -SubscriptionName $SubscriptionName
            $DstVMs = Get-AzureVM -ServiceName $ServiceName | select Name -ExpandProperty Name
        }

        process {
            if ( $DstVMs -contains $_.Name ) { return }
            $_ | 
            Add-Member -MemberType NoteProperty -Name DstSubscriptionName -Value $SubscriptionName -PassThru |
            Add-Member -MemberType NoteProperty -Name DstServiceName -Value $ServiceName -PassThru |
            Add-Member -MemberType NoteProperty -Name DstStorageAccountName -Value $StorageAccountName -PassThru 
        }
    }
    
    function Add-VM {
    <#
    .SYNOPSIS

    Function registers VM based on the original configuration in the destined Cloud Service/Subscription

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline = $true)]
        [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.ServiceOperationContext]
        $VM,
        [Parameter()]
        [string]
        $VNetName
    )

        process {
            # create a vm from previously saved config
            $vmconfig = Import-AzureVM -Path $VM.ConfigFile
            if ($VNetName) {
                $r = New-AzureVM -ServiceName $VM.DstServiceName -VMs $vmconfig -VNetName $VNetName -WaitForBoot
            } else {
                $r = New-AzureVM -ServiceName $VM.DstServiceName -VMs $vmconfig -WaitForBoot
            }
            Remove-Item $VM.ConfigFile
        }
    }
        
    function Copy-VM{
    <#
    .SYNOPSIS

    Function Copy-VM copies blobs that belongs to the passed VMs and registers Azure disks in the destined Cloud Service/Subscription under their original names. If blob of such name already exists whole process is given up.

    #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true, ValueFromPipeline = $true)]
            [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.ServiceOperationContext]
            $VM,
            [Parameter()]
            [switch]
            $PassThrough
        )

        begin {

            function Get-VMDisk {
                [CmdletBinding()]
                param(
                        [Parameter(Mandatory=$true, ValueFromPipeline = $true)]
                        [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.ServiceOperationContext]
                        $VM
                )

                $VM | Get-AzureOSDisk
                $VM | Get-AzureDataDisk
            }

            function Stop-VM {
                [CmdletBinding()]
                param(
                        [Parameter(Mandatory=$true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName=$true)]
                        [string]
                        $Name,
                        [Parameter(Mandatory=$true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName=$true)]
                        [string]
                        $ServiceName
                )
        
                $vm = Get-AzureVM -Name $Name -ServiceName $ServiceName
                $vmstatus = $vm.Status
        
                if ($vmstatus -ne "StoppedDeallocated") { 
                    Write-Verbose "Shutting down VM: $Name@$ServiceName"
                    $vm | Stop-AzureVM 
                }
                while ($vmstatus -ne "StoppedDeallocated"){
                    Start-Sleep -s 30
                    $vmstatus = (Get-AzureVM -Name $Name -ServiceName $ServiceName).Status
                }
            }

            $counter = 1;

        }

        process {

            if ($counter -eq 1) {
                        Select-AzureSubscription -SubscriptionName $VM.DstSubscriptionName
                        $DstDiskNames = Get-AzureDisk | ? { $_.MediaLink.Host.Split('.')[0] -eq $VM.DstStorageAccountName } | select DiskName -ExpandProperty DiskName
            }

            #region Prepare the source and get the information about disks to copy

            Select-AzureSubscription -SubscriptionName $_.SrcSubscriptionName
        
            #get disks
            $vmdisks = $VM | Get-VMDisk | ? { $DstDiskNames -NotContains $_.DiskName } | Select -Property `
                    DiskName, OS, `
                    @{Name="SrcBlob";Expression={($_.MediaLink.Segments[-1])}}, ` 
                    @{Name="StorageAccount";Expression={($_.MediaLink.Host.Split('.')[0])}}, ` 
                    @{Name="Container";Expression={$_.MediaLink.Segments[1].Split(‘/’)[0]}}, `
                    @{Name="Context";Expression={New-AzureStorageContext -StorageAccountName ($_.MediaLink.Host.Split('.')[0]) `
                                                                         -StorageAccountKey (Get-AzureStorageKey $_.MediaLink.Host.Split('.')[0] | %{ $_.Primary })}}

            # then stop VM for the sake of image consistency
            $VM | Stop-VM

            #endregion

            #region Copy and run the resources at the destination
            Select-AzureSubscription -SubscriptionName $_.DstSubscriptionName
        
            $destStoreKey = Get-AzureStorageKey $VM.DstStorageAccountName | %{ $_.Primary }
            $destContext = New-AzureStorageContext -StorageAccountName $VM.DstStorageAccountName -StorageAccountKey $destStoreKey

            $vmdisks | ForEach-Object {
                    
                        # create container if does not exist
                        if (-not (get-AzureStorageContainer | where name -eq $_.Container)){
                            New-AzureStorageContainer -Name $_.Container -Context $destContext 
                        }
                    
                        #copy blob
                        $blobCopy = Start-AzureStorageBlobCopy -DestContainer $_.Container `
                            -DestContext $destContext `
                            -SrcBlob $_.SrcBlob `
                            -Context $_.Context `
                            -SrcContainer $_.Container
                    
                        #wait until it's done and show progres while waiting
                        $status = $blobCopy | Get-AzureStorageBlobCopyState
                        while($status.Status -eq "Pending")
                        {
                            Start-Sleep -s 30
                            $status = $blobCopy | Get-AzureStorageBlobCopyState
                            $progress = [math]::Round(($status.BytesCopied / $status.TotalBytes)*100)
                            Write-Progress -Activity "Copying blob: $($_.SrcBlob)" -status "progress: $progress%" -percentComplete $progress
                        }
                    
                        #create disk based on the blob                                        
                        $r = Add-AzureDisk -DiskName $_.DiskName `
                            -OS $_.OS `
                            -MediaLocation "$($destContext.BlobEndPoint)/$($_.Container)/$($blobCopy.Name)"
                        Write-Verbose $r
            }

            #endregion

            #region Closure

            if ($StartSrcVMafterCopy){
                Select-AzureSubscription -SubscriptionName $_.SrcSubscriptionName
                $r = $VM | Start-AzureVM
                Write-Verbose $r
            }
            
            #endregion

            if ($PassThrough) { $VM }
        
        $counter++
        }
    }

    # 1. Get source VM collection
    if ($ExcludedVMs ) {
        $vms = Get-ServiceVM -ServiceName $SrcServiceName -SubscriptionName $SrcSubscriptionName -ExcludedVMs $ExcludedVMs |
               Test-VMExistsAtDst -ServiceName $DstServiceName -SubscriptionName $DstSubscriptionName -StorageAccountName $DstStorageAccountName
    } else {
        $vms = Get-ServiceVM -ServiceName $SrcServiceName -SubscriptionName $SrcSubscriptionName |
               Test-VMExistsAtDst -ServiceName $DstServiceName -SubscriptionName $DstSubscriptionName -StorageAccountName $DstStorageAccountName
    }
    
    # 2. Copy their BLOBs
    $copied_vms = $vms | Copy-VM -PassThrough 
    
    # 3. Recreate the machines at the destination
    if ($VNetName ) {
           $copied_vms | Add-VM -VNetName $VNetName
    } else {
           $copied_vms | Add-VM            
    }
}

