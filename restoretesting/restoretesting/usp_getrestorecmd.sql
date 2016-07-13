USE [util]
GO

/****** Object:  StoredProcedure [dbo].[usp_getRestorecmd]    Script Date: 12/16/2015 2:42:32 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE procedure [dbo].[usp_getRestorecmd](@Mydbname sysname,@backuppath varchar(max),@Result  varchar(max) output)
as
begin
declare @mdfcount int
declare @ldfcount int
declare @count int=1
declare @finalcmd varchar(max)
declare @mdfcmd varchar(max)
declare @ldfcmd varchar(max)
declare @BackupName varchar(max)
declare @dbname varchar(200)
declare @fileextn varchar(10)
set @dbname=@Mydbname
set @BackupName=@backuppath

--print @finalcmd
set nocount on
----------------------------------------------------------------------------------------------
--Load the filelistonly output to a temporary table
-------------------------------------------------------------------------------------------------
BEGIN
            Declare @filesOnly table ( LogicalName nvarchar(128)
                                     , PhysicalName nvarchar(260)
                                     , Type char(1)
                                     , FileGroupName nvarchar(128)
                                     , Size numeric(20,0)
                                     , MaxSize numeric(20,0)
                                     , FileId tinyint
                                     , CreateLSN numeric(25,0)
                                     , DropLSN numeric(25, 0)
                                     , UniqueID uniqueidentifier
                                     , ReadOnlyLSN numeric(25,0)
                                     , ReadWriteLSN numeric(25,0)
                                     , BackupSizeInBytes bigint
                                     , SourceBlockSize int
                                     , FileGroupId int
                                     , LogGroupGUID uniqueidentifier
                                     , DifferentialBaseLSN numeric(25,0)
                                     , DifferentialBaseGUID uniqueidentifier
                                     , IsReadOnly bit
                                     , IsPresent bit
                                     , TDEThumbprint varbinary(32) )

--insert the output of filelistonly result in a temporary table
               BEGIN
                     INSERT INTO @filesOnly
                    EXEC ( 'RESTORE FILELISTONLY
                               FROM DISK = N'''+@BackupName+'''')
--

               END
    end
---------------------------------------------------------------------------------------------------------
--Get the count of MDF/NDF and LDF files in the backup
----------------------------------------------------------------------------------------------------------    
   select @mdfcount=count(Type) from @filesOnly where Type='D'
-- print @mdfcount
 select @ldfcount=count(Type) from @filesOnly where Type='L'
-- print @ldfcount
--------------------------------------------------------------------------------------------------------
 --get the logical file names for MDF  
-------------------------------------------------------------------------------------------------------- 
  declare @Logicalmdf table(mdf varchar(100))
  insert into @Logicalmdf select LogicalName from @filesOnly where Type='D'
  --select * from @Logicalmdf
  declare @mymdf varchar(100)
  
  while exists(select top 1 mdf from @Logicalmdf)
  begin
  set @mymdf=(select top 1 mdf from @Logicalmdf)
  select @fileextn=reverse(substring(REVERSE(PhysicalName),1,charindex('.',REVERSE(PhysicalName))-1)) from @filesOnly where LogicalName=@mymdf
  if(@count <= @mdfcount)
  begin
  set @mdfcmd=coalesce(@mdfcmd,'')+(' move '''+@mymdf+''' to ''E:\data01\DATA\'+@dbname+'_'+cast(@count as varchar)+'.'+@fileextn+''',')
  delete from @Logicalmdf where mdf=@mymdf
  set @count=@count+1
  set @fileextn=null
  end
  end
  --print 'data files are:'
  --print @mdfcmd
  -----------------------------------------------------------------------------------------
  --Get the logical file names of LDF
  -----------------------------------------------------------------------------------------
  set @count=1
  declare @Logicalldf table(ldf varchar(100))
  insert into @Logicalldf select LogicalName from @filesOnly where Type='L'
  --select * from @Logicalldf
  declare @myldf varchar(100)
  
  while exists(select top 1 ldf from @Logicalldf)
  begin
  set @myldf=(select top 1 ldf from @Logicalldf)
  select @fileextn=reverse(substring(REVERSE(PhysicalName),1,charindex('.',REVERSE(PhysicalName))-1)) from @filesOnly where LogicalName=@myldf
  if(@count <= @ldfcount)
  begin
  set @ldfcmd=coalesce(@ldfcmd,'')+(' move '''+@myldf+''' to ''E:\data01\DATA\'+@dbname+'_'+cast(@count as varchar)+'.'+@fileextn+''',')
  delete from @Logicalldf where ldf=@myldf
  set @count=@count+1
  set @fileextn=null
  end
  end
  --print 'log files are:'
  --print @ldfcmd
  --print 'complete command is:'
  --set @finalcmd= @finalcmd+@mdfcmd+@ldfcmd
  --print @finalcmd
  set @Result=@mdfcmd+@ldfcmd
  --exec(@finalcmd)
end
----------------------------------------------------------------------
--Execute the above procedure in the below format
/*declare @Result  varchar(max)
exec dba.dbo.usp_getRestorecmd 'Mytest','C:\data\taraktest.bak',@Result output
print @Result*/
----------------------------------------------------------------------



GO


