USE [util]
GO

/****** Object:  StoredProcedure [dbo].[usp_getRestorecmdWrapper]    Script Date: 12/16/2015 2:43:17 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE procedure [dbo].[usp_getRestorecmdWrapper](@mydbname sysname,@backupfile_FULL varchar(max),@backupfile_DIFF varchar(max),@backupfile_LOG varchar(max),@Restoretype char)
as
begin
declare @dbname sysname
declare @BackupName varchar(max)
declare @MRestoreType char
declare @finalcmd_FULL_F varchar(max)
declare @finalcmd_FULL_P varchar(max)
declare @finalcmd_DIFF_P varchar(max)
declare @finalcmd_LOG_P varchar(max)
declare @Mbackupfile_FULL varchar(max)
declare @Mbackupfile_DIFF varchar(max)
declare @Mbackupfile_LOG varchar(max)
declare @Result  varchar(max)

set @dbname=@mydbname
set @Mbackupfile_FULL=@backupfile_FULL
set @Mbackupfile_DIFF=@backupfile_DIFF
set @Mbackupfile_LOG=@backupfile_LOG
set @MRestoreType=@Restoretype

if(@MRestoreType = 'F')
begin
set @finalcmd_FULL_F='restore database '+@dbname+' from disk='''+@Mbackupfile_FULL+''' with'
--declare @Result  varchar(max)
exec util.dbo.usp_getRestorecmd @dbname,@Mbackupfile_FULL,@Result output
set @finalcmd_FULL_F=@finalcmd_FULL_F+@Result+'recovery,NOUNLOAD,REPLACE,STATS = 2'
print @finalcmd_FULL_F
exec(@finalcmd_FULL_F)
end

if(@MRestoreType = 'P')
begin
---Restore command for FULL Partial
set @finalcmd_FULL_P='restore database '+@dbname+' from disk='''+@Mbackupfile_FULL+''' with'
--declare @Result  varchar(max)
exec util.dbo.usp_getRestorecmd @dbname,@Mbackupfile_FULL,@Result output
set @finalcmd_FULL_P=@finalcmd_FULL_P+@Result+'norecovery,NOUNLOAD,REPLACE,STATS = 2'
print @finalcmd_FULL_P
exec(@finalcmd_FULL_P)

---Restore command for FULL Partial
set @finalcmd_DIFF_P='restore database '+@dbname+' from disk='''+@Mbackupfile_DIFF+''' with'
--declare @Result  varchar(max)
exec util.dbo.usp_getRestorecmd @dbname,@Mbackupfile_DIFF,@Result output
set @finalcmd_DIFF_P=@finalcmd_DIFF_P+@Result+'norecovery,NOUNLOAD,REPLACE,STATS = 2'
print @finalcmd_DIFF_P
exec(@finalcmd_DIFF_P)


---Restore command for FULL Partial
set @finalcmd_LOG_P='restore LOG '+@dbname+' from disk='''+@Mbackupfile_LOG+''' with'
--declare @Result  varchar(max)
exec util.dbo.usp_getRestorecmd @dbname,@Mbackupfile_LOG,@Result output
set @finalcmd_LOG_P=@finalcmd_LOG_P+@Result+'recovery,NOUNLOAD,REPLACE,STATS = 2'
print @finalcmd_LOG_P
exec(@finalcmd_LOG_P)

end
end



GO


