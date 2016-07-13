 
<#
Currently script needs to be executed on the instance in which you want to attach the volume*
Finds a full/diff/tlog snapshot that is around a certain number of 44/10/6 days old respectively.
It creates a new volume, using the chosen snapshot, from a primary node passed in by the user
to be attached on the instance the script is initiated.
Script will prompt user to bring attached drive online and then updates name/letter automatically.
#>

#Function for getting the EBS Drive Letters
Function EBSDrives()
{
    # Create a hash table that maps each device to a SCSI target
    $Map = @{"0" = '/dev/sda1'} ;
    for($x = 1; $x -le 26; $x++) 
    {
        $Map.add($x.ToString(), [String]::Format("xvd{0}",[char](97 + $x)))
    }

    for($x = 78; $x -le 102; $x++)
    {
        $Map.add($x.ToString(), [String]::Format("xvdc{0}",[char](19 + $x)))
    }

    Try 
    {
        # Use the metadata service to discover which instance the script is running on
        $Id = (Invoke-WebRequest '169.254.169.254/latest/meta-data/instance-id').Content
        $AZ1 = (Invoke-WebRequest '169.254.169.254/latest/meta-data/placement/availability-zone').Content
        $Region1 = $AZ1.Substring(0, $AZ1.Length -1)

        #Get the volumes attached to this instance
        $BlockDeviceMappings = (Get-EC2Instance -Region $Region1 -Instance $Id).Instances.BlockDeviceMappings
        Write-Log -Message "found the instance $id in $az1" -MessageType INFO  
    }
    Catch
    {
         Write-Log -Message "Could not access the AWS API, therefore, VolumeId is not available. Verify that you provided your access keys." -MessageType "INFO" -Verbose
    }

    Get-WmiObject -Class Win32_DiskDrive | %{
        $Drive = $_
        # Find the partitions for this drive
        Get-WmiObject -Class Win32_DiskDriveToDiskPartition |  Where-Object {$_.Antecedent -eq $Drive.Path.Path} | %{
            $D2P = $_
            # Get details about each partition
            $Partition = Get-WmiObject -Class Win32_DiskPartition |  Where-Object {$_.Path.Path -eq $D2P.Dependent}
            # Find the drive that this partition is linked to
            $Disk = Get-WmiObject -Class Win32_LogicalDiskToPartition | Where-Object {$_.Antecedent -in $D2P.Dependent} | %{ 
                $L2P = $_
                #Get the drive letter for this partition, if there is one
                Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.Path.Path -in $L2P.Dependent}
            }
            $BlockDeviceMapping = $BlockDeviceMappings | Where-Object {$_.DeviceName -eq $Map[$Drive.SCSITargetId.ToString()]}
            
            $Map[$Drive.SCSITargetId.ToString()]
    
        }
    } | Sort-Object Disk, Partition

}

#################################################################################################################
#User function to be called passing the required parameters
#################################################################################################################

#param ex. amsi03-a, FULL, 60, email@infor.com
function attachSnapshots()
{
 <#
 .SYNOPSIS
    This script creates FULL,DIFF,TLOG Volume using snapshots of primaryd AWS MS SQL Servers.
    
 .DESCRIPTION
    This script does 3 validation checks before completing.
    Check #1 looks to see if grain has been set, if true it exits.
    Check #2 verifies the 3 node path exists, if true, it writes the grain and exits.
    If all checks complete, it pulls the Instance-Type from AWS EC2 meta-data,
    configures the disk and logs the results at C:\salt\var\log\diskconflog.txt
.NOTES
    File Name  : diskconfig3.ps1
    Author     : Sandeep Puram, Taraknath.Bodepalli@infor.com
    Requires   : PowerShell V4
    Version    : 2015.12.16
.LINK
 #>
Param( [Parameter(Mandatory=$true)] $primaryNode,
       [Parameter(Mandatory=$true)] [string]$backupType, 
       [Parameter(Mandatory=$true)] $numDaysOld, 
       [Parameter(Mandatory=$true)] $ownerTag )



#------------------------------------------------------------------------------------------
cd C:\salt\scripts

Get-AWSPowerShellVersion  > $null # This call is needed to instantiate the AWSPowerShell module
import-module "C:\salt\scripts\modules\InforLogging\InforLogging.psm1"

$logFile = New-LogFile -Folder "C:\salt\scripts\restoretesting\" -FilePrefix "Adding snapshot" -FileExtension "log" -SetEnvLogFile 1 -Verbose
#Param variables
$instance   = ($env:COMPUTERNAME).ToLower()
$fullDate  = (Get-Date -Hour 0 -Minute 0 -Second -0)
$fullDate = $fullDate.AddDays(-$numDaysOld)

#get the existing drive numbers attached
$GetDisk_Before=$null
$GetDisk_After=$null
$GetDisk_Before = New-Object System.Collections.ArrayList
$GetDisk_Before=Get-Disk | %{ $_.Number}

if($backupType -eq "full")
{
    #Hashtable for adjusting to sunday
    $daysOfWeek = @{Sunday = 0
                ; Monday = -1
                ; Tuesday = -2
                ; Wednesday = -3
                ; Thursday = -4
                ; Friday = -5
                ; Saturday = -6}
    
    
    $fullDate = $fullDate.AddDays($daysOfWeek[$fullDate.DayOfWeek.ToString()])
}
try 
{
    #get this computers az, region, and instance id
     $AZ = (New-Object System.Net.WebClient).DownloadString("http://169.254.169.254/latest/meta-data/placement/availability-zone")
    $region = $AZ.substring(0,$AZ.length-1)
    $myInstanceID = (New-Object System.Net.WebClient).DownloadString("http://169.254.169.254/latest/meta-data/instance-id")

    #this sets up to get a snapshot for 'a'
    $snapDesc = $primaryNode.ToUpper() + "-" + $backupType.ToUpper()
    $fullDate
    #Get the primary node snapshot based on the description provided
    $chosenSnap = (Get-EC2Snapshot -Region $region | where {$_.Description -eq $snapDesc} | Sort-Object StartTime  | where {$_.StartTime -gt $fullDate} | Select-Object -First 1)
    if(!$chosenSnap)
    {
    Write-Log -Message "There are no snapshots with the given conditions" -MessageType INFO -Verbose 
    break
    }
   
    $chosenSnap.SnapshotId
    #Find all current drive device mappings
    $Mappings = EBSDrives

    #split out this into an array
    $Mappings1 = $Mappings.Split("`r`n") | ForEach-Object{$_ }
    Write-Log -Message "Found the required detials of $az in $region intanceid  $myinstanceid with description $snapdesc" -MessageType INFO 
    
}
catch
{
       Write-Log -Message "Unable to find the $myinstanceid in the $region" -MessageType "INFO" 
}

#For each existing drive mapping, find the device letter
foreach ($vol in $Mappings1)
    {
        $ReservedDev+= $vol.Substring($vol.Length-1,1)
        #Write-Log -Message "Existing Drive mappings are $ReservedDev" -MessageType INFO 
        $vol=$null        

    }

   
#Split out the characters into an array
$ResDev =($ReservedDev.ToCharArray())| Sort-Object


#Build the list of device letters that AWS can use
$FreeDev = New-Object System.Collections.ArrayList
$FreeDev.Add('f')
$FreeDev.Add('g')
$FreeDev.Add('h')
$FreeDev.Add('i')
$FreeDev.Add('j')
$FreeDev.Add('k')
$FreeDev.Add('l')
$FreeDev.Add('m')
$FreeDev.Add('n')
$FreeDev.Add('o')
$FreeDev.Add('p')
$FreeDev.Add('q')
$FreeDev.Add('r')
$FreeDev.Add('s')
$FreeDev.Add('t')
$FreeDev.Add('u')
$FreeDev.Add('v')


#Loop for each used device letter, and remove the letters already is use by this server
foreach($Dev in $ResDev)
    {
        if ($Dev -in $FreeDev)
            {
               
                $FreeDev.Remove("$Dev")
            }
    }


#We need one letter to use to mount the backup volumes
if ($FreeDev.Count -ge 1)
    {
        #Convert the device letters found to chars  
        [char]$dev1 = $FreeDev.Item(0)
              
        
        #Load up the device ids needed
        $devices = @{"$backupType" = "/dev/xvd$dev1"}
    }
else
    {
       Write-Log -Message "There are not eough remaining device letters to use!!!" -MessageType INFO -Verbose  
       Break
    }
try 
{
    $AppName = $instance.Substring(0,$instance.Length -4)
    $CompName = $instance.Substring(0, $instance.Length-2)
    $TagName = "$AppName`:$CompName`:$instance"

    $tagfilter = (New-Object Amazon.EC2.Model.Filter)
    $tagfilter.Name = "tag:Name"
    $tagfilter.Value = $TagName

    #Write-Host $chosenSnap.SnapshotId
    $snaphotid_attached=$chosenSnap.SnapshotId
    write-log -Message "$snaphotid_attached is ready to attached" -MessageType "INFO"
    #create a new volume from the snap
    $Volume = New-EC2Volume -Region $Region -AvailabilityZone $AZ -VolumeType 'gp2' -SnapshotId $chosenSnap.SnapshotId
    $volumeid=$Volume.VolumeId
    write-log -Message "Volume id is $volumeid" -MessageType "INFO" 
}
catch
{ 
    Write-Log -Message "Unable to attach the $chosenSnap.SnapshotId to the $myinstance  " -MessageType "INFO"
}
#waiting for the volume to become available
do
{
    Sleep -Seconds 2
}while((Get-EC2Volume -VolumeIds $Volume.VolumeId -Region $Region).state.Value -ne "available")

Write-Log -Message "Finished volume creation.." -MessageType "INFO" 
$SNAPTag = New-Object Amazon.EC2.Model.Tag
$dateString = $chosenSnap.StartTime.ToString("yyyyMMdd")

#adding appropriate tags on the volume
try
    {

        $SNAPTag.Key = "Name"
        $SNAPTag.Value = $TagName + ":" + $backupType.ToUpper() + "_from_" + $dateString
        New-EC2Tag -Region $Region -Resources $Volume.VolumeId -Tags $SNAPTag

        $SNAPTag.Key = "Product"
        $SNAPTag.Value = $AppName
        New-EC2Tag -Region $Region -Resources $Volume.VolumeId -Tags $SNAPTag

        $SNAPTag.Key = "Owner"
        $SNAPTag.Value = $ownerTag
        New-EC2Tag -Region $Region -Resources $Volume.VolumeId -Tags $SNAPTag

        $SNAPTag.Key = "Restored"
        $SNAPTag.Value = Get-Date -Format "yyyyMMdd"
        New-EC2Tag -Region $Region -Resources $Volume.VolumeId -Tags $SNAPTag

        $SNAPTag.Key = "Service"
        $SNAPTag.Value = $AppName + ":db-mssql"
        New-EC2Tag -Region $Region -Resources $Volume.VolumeId -Tags $SNAPTag

    }
catch
    {
        #Write-Host "Error writing tags"
        Write-Log -Message "Error writing tags" -MessageType "INFO" -Verbose
        #Write-Host $_.Exception|format-list -force
    }


Write-Log -Message "Finished tagging..." -MessageType "INFO"

#attach the volume to the running instance
$devices.Get_Item($backupType.ToUpper())
$Volume = Add-EC2Volume -InstanceID $MyInstanceID -VolumeId $Volume.VolumeId -Region $Region -Device $devices.Get_Item($backupType.ToUpper())
$volumeid=$Volume.VolumeId
do
{
    ##Write-Host ("Attaching volume... " + $Volume.VolumeId)
    Write-Log -Message "Attaching volume... $Volumeid" -MessageType "INFO" 
    Sleep -Seconds 3 #block until volume is attached
}while((Get-EC2Volume -VolumeIds $Volumeid -Region $Region).State -ne "in-use")

#############################################################################################################
##Remove the existing drive Letters from the array to map new drives
#############################################################################################################

$GetDrive = New-Object System.Collections.ArrayList
$GetDrive.Add('F')
$GetDrive.Add('G')
$GetDrive.Add('H')
$GetDrive.Add('I')
$GetDrive.Add('J')
$GetDrive.Add('K')
$GetDrive.Add('L')
$GetDrive.Add('M')
$GetDrive.Add('N')
$GetDrive.Add('O')
$GetDrive.Add('P')
$GetDrive.Add('Q')
$GetDrive.Add('R')
$GetDrive.Add('S')
$GetDrive.Add('T')
$GetDrive.Add('U')
$GetDrive.Add('V')

  
$device=Get-WmiObject -Class Win32_LogicalDisk | %{ $_.DeviceID }

foreach($dr in $device)
{
$dvc=$dr[($dr.count)-1]
if($dvc -in $GetDrive)
{

$GetDrive.Remove("$dvc")

}
}
if($GetDrive -ge 1)
{
$newDriveLetter = [char]$GetDrive.Item(0)
}

else
{
 Write-Log -Message "All drives are already mapped.Clear some to attach new!!!" -MessageType INFO -Verbose  
 Break
 }

Sleep -Seconds 3

#Find attached volume

#Get drive numbers after attaching new volume
$GetDisk_After = New-Object System.Collections.ArrayList
$GetDisk_After=Get-Disk | %{ $_.Number}


#compare previous and after numbers to get the newly attached device
$volumeToMount=compare-object -referenceobject $GetDisk_Before -differenceobject $GetDisk_After -PassThru

#bring created disk  online
if((Get-Disk | Where-Object Number -EQ $volumeToMount).OperationalStatus -ne "Online")
{
if(get-disk -Number $volumeToMount | %{$_.IsReadOnly})
{
Set-Disk -Number $volumeToMount -IsReadonly $false
}
Set-Disk -Number $volumeToMount -IsOffline $false

sleep -Seconds 3
}

#Get Drive Letter

$driveLetter1=((Get-Partition -DiskNumber $volumeToMount).DriveLetter)
$driveLetter = $driveLetter1[($driveLetter1.count)-1]
#set up new label with concatenated temp
$currFileSysLabel=(Get-Volume -DriveLetter $driveLetter).FileSystemLabel
$newFileSysLabel = $currFileSysLabel.Substring(0, $currFileSysLabel.Length-1) + "_temp\"
#$newFileSysLabel=$currFileSysLabel+"_temp\"

$condition=$null

$condition=read-host "restored drive is:$driveLetter. This will renamed as :$newDriveLetter and will be labelleled as:$newFileSysLabel. Do you want to continue(yes/no):"


try{

if($condition.ToLower() -eq 'yes')
{

            #Updates label and drive letter
        if($driveLetter -ne $newDriveLetter)
        {
            Set-Partition -DriveLetter $driveLetter -NewDriveLetter $newDriveLetter
        }

        #show for easy debugging if an error happens
        Set-Volume -DriveLetter $newDriveLetter -NewFileSystemLabel $newFileSysLabel
        Write-Log -Message "Updating label to $newFileSysLabel and drive letter to $newDriveLetter " -MessageType "INFO"
        #return the drive letter recently attached
        $d=Get-Volume -DriveLetter $newDriveLetter | %{$_.DriveLetter}
        $backupType=$backupType.ToUpper()
        $filepath="C:\salt\scripts\RestoreTesting\AddSnapshot_$backupType"+"_"+"$numDaysOld.txt"
        $D | Out-File -FilePath $filepath 
        Write-Log -Message "volume attached is $D.This is created from volume:$Volumeid which in turn created from snapshot:$snaphotid_attached" -MessageType "INFO" 
       
}

else
{
Write-Host "Terminating execution"
break
}      
}
catch
{
        Write-Log -Message "Unable to update label and drive letter" -MessageType "INFO" -Verbose
}

}