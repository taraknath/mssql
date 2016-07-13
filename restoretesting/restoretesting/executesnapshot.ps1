<#
 .Description
    Currently script needs to be executed on the secondary instance in which you want to attach the volume,
    Will restore 60days full backup of database.
    will restore 10days full/difftlog backup of a database.
    Create usp_getrestorecmdwrapper and usp_getrestorecmd in util database.

.NOTES
    File Name      : Attach_Snapshot_function.psm1
    Author         : Sandeep Puram, Taraknath.Bodepalli@infor.com
    Requires       : PowerShell V4
    Version 1      : 2015.12.16
    Version 1.1    : 2016.01.13
#>


Param( [Parameter(Mandatory=$true)] $primaryNode,
       [Parameter(Mandatory=$true)] $ownerTag,
       [Parameter(Mandatory=$true)] $dbname )

import-module "C:\salt\scripts\RestoreTesting\AttachSnapshot.psm1"
Get-AWSPowerShellVersion  > $null # This call is needed to instantiate the AWSPowerShell module
import-module "C:\salt\scripts\modules\InforLogging\InforLogging.psm1"

##Attaches the full snaphot which is 60 days ago
attachSnapshots "$primaryNode" "FULL" "44" "$ownertag" 
write-host "Full snaphot volume is restored and attached"
$AttachedDrive_60=get-content  "C:\salt\scripts\RestoreTesting\AddSnapshot_FULL_44.txt"

#Calling Restore function to restore the FULL database
write-host "volume attached is $AttachedDrive_60"
$date=(Get-Date).ToString('yyyyMMddhhmmss')
try
{
    $AttachedDrive_FULL_60="$AttachedDrive_60"+":"+"\$dbname"
    $fullbackup_60=Get-ChildItem -Path $AttachedDrive_FULL_60 | Where-Object {$_.LastWriteTime -lt (Get-Date).Adddays(-60)} |Sort-Object -Descending | Select-Object -First 1
    $full_60=$AttachedDrive_FULL_60+"\"+$fullbackup_60.Name
    $full_60
    $database=$dbname+"_testing_60days_$date"
    Write-host "Restoring process started for 60 days full backup ...."
    $fullbackuprestore="exec util.dbo.usp_getRestorecmdWrapper @mydbname='$database'
                                    ,@backupfile_FULL='$full_60',@backupfile_DIFF=NULL,@backupfile_log=null,@Restoretype='F'"

   #restores the  60days full backup for the database             
    Invoke-Sqlcmd -Query $fullbackuprestore -ServerInstance $env:COMPUTERNAME -QueryTimeout 0
    write-host "Restoring process completed for 60 days full backup ...."
}
catch
{
    write-host "Unable to resotre 60days fullbackup"
}

#getting the drive detailsfor 10 days snapshot test
#Getting the 10th day full file name
  $AttachedDrive_FULL_10="e:\backups01\full\$dbname"
  $fullbackup_FULL_10=Get-ChildItem -Path $AttachedDrive_FULL_10 | Where-Object {$_.LastWriteTime -lt (Get-Date).Adddays(-10)} |Sort-Object -Descending | Select-Object -First 1
  if(!$fullbackup_FULL_10)
  {
         Write-Host "No FULL backup file with the given condition"
    break
  }
  else
  {
    $full_10=$fullbackup_FULL_10.Name
    $full_10
    $d_full_10="$AttachedDrive_FULL_10"+"\"+$full_10
    $fullbackuptime_10=[datetime](Get-ItemProperty -Path $d_full_10 -Name LastWriteTime).lastwritetime
    
  }
#restore the 10days Differential Snapshot
    attachSnapshots "$primaryNode" "DIFF" "10" "$ownertag" 
    write-host "Diff snaphot volume is restored and attached"
    $AttachedDrive_D_10=get-content  "C:\salt\scripts\RestoreTesting\AddSnapshot_DIFF_10.txt"
    $AttachedDrive_DIFF_10="$AttachedDrive_D_10"+":"+"\$dbname"
    $DIFFbackup_DIFF_10=Get-ChildItem -Path $AttachedDrive_DIFF_10 | Where-Object {$_.LastWriteTime -ge $fullbackuptime_10} |Sort-Object -Descending  | Select-Object -First 1
    if(!$DIFFbackup_DIFF_10)
    {
        Write-Host "No DIFF backup file with the given condition"
        break
   }
else
{
    $DIFF_10=$DIFFbackup_DIFF_10.Name
    $DIFF_10
    $D_DIFF_10="$AttachedDrive_DIFF_10"+"\"+$DIFF_10
    $DIFFbackuptime_10= [datetime](Get-ItemProperty -Path $D_DIFF_10 -Name LastWriteTime).lastwritetime
}

#Get the 10th day LOG file name and restores thes Snapshot
    attachSnapshots "$primaryNode" "LOG" "7" "$ownertag"
    write-host "Log snaphot volume is restored and attached"
    $AttachedDrive_L_10=get-content  "C:\salt\scripts\RestoreTesting\AddSnapshot_LOG_7.txt"
    $AttachedDrive_LOG_10="$AttachedDrive_L_10"+":"+"\$dbname"
    $LOGbackup_LOG_10=Get-ChildItem -Path $AttachedDrive_LOG_10 | Where-Object {$_.LastWriteTime -ge $DIFFbackuptime_10}  | Select-Object -First 1
    if(!$LOGbackup_LOG_10)
      {
       Write-Host "No LOG backup file with the given condition"
       break
      }
   else
    {
    	$LOG_10=$LOGbackup_LOG_10.Name
        $LOG_10
	$D_LOG_10="$AttachedDrive_LOG_10"+"\"+$LOG_10
    	$LOGbackuptime_10=[datetime](Get-ItemProperty -Path $D_LOG_10 -Name LastWriteTime).lastwritetime
   }

try
{
    $database_P=$dbname+"_testing_10days$date"
    #resore 10days full/diff/log backups
    write-host "Restoring process started for 10days..."
    $fullbackuprestore_P="exec util.dbo.usp_getRestorecmdWrapper @mydbname='$database_P'
                                    ,@backupfile_FULL='$d_full_10',@backupfile_DIFF='$D_DIFF_10',@backupfile_log='$D_LOG_10',@Restoretype='P'"         
    Invoke-Sqlcmd -Query $fullbackuprestore_P -ServerInstance $env:COMPUTERNAME -QueryTimeout 0
    write-host "Restoring process Completed for 10days..."
}
catch
{
    write-host "Unable to Restore 10 days full/diff/log backups"
}
