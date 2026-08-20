IF OBJECT_ID(N'dbo.usp_ESSelect', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ESSelect;
GO

CREATE PROCEDURE [dbo].[usp_ESSelect] (@p_Directory varchar(510), @p_Username varchar(125), @p_FileNameLoaded varchar(510) OUTPUT)
AS

/*
We expect this procedure to only executed by SQL job
There should be only one active working file
Here we want to select a file to load next and place an entry in the t_ProcessingFIlesListES.
We want to output the name of the file loaded.
We want to take the directory searched as an input.
We need to populate the username here as well so we know who's file this is.
*/

BEGIN

	DECLARE @Cmd varchar(2012)
	DECLARE @WorkingFilesCount tinyint
	DECLARE @UnderscoreAt int

	SELECT @WorkingFilesCount = isNULL(count(*),0) from t_ProcessingFilesListES where ActiveWorkingFileYN = 'Y'

	DECLARE @rawfilestable table (ID int IDENTITY, FileName varchar(100))
	-- Restrict to this folder only (dir path *.txt also lists the SQL process current directory).
	SET @Cmd = 'dir "' + @p_Directory + '\*.txt" /A:-D /O:D /b'

	INSERT INTO @rawfilestable EXEC xp_cmdshell @Cmd

	DELETE FROM @rawfilestable
	WHERE FileName in ('NULL', 'File Not Found') or FileName is NULL
	or FileName LIKE '%cannot find%'
	or FileName LIKE '%Access is denied%'
	or FileName LIKE '%The system cannot find%'
	or filename in ( select distinct OriginalFileName from t_ProcessingFilesListES )

	DELETE FROM @rawfilestable
	WHERE FileName not in (Select top 1 filename from @rawfilestable order by ID ASC)

	DECLARE @RawFileCount tinyint
	SELECT @RawFileCount = isNULL(count(*),0) from @rawfilestable

	SELECT @p_FileNameLoaded = MAX(FileName) from @rawfilestable
	IF @WorkingFilesCount != 0
	BEGIN
		SET @p_FileNameLoaded = NULL
	END

	SET @UnderscoreAt = CASE WHEN @p_FileNameLoaded IS NULL THEN 0 ELSE charindex('_', @p_FileNameLoaded) END

	IF @@Error = 0 and @WorkingFilesCount = 0 and @RawFileCount = 1 and len(@p_FileNameLoaded) > 0 and @UnderscoreAt > 1
	BEGIN
		SET @p_Username = left(@p_FileNameLoaded, @UnderscoreAt - 1)

		INSERT INTO t_ProcessingFilesListES (OriginalFileName, Username, SelectedYN, ActiveWorkingFileYN)
		VALUES ( @p_FileNameLoaded, @p_Username, 'Y', 'Y')
	END
	ELSE IF @RawFileCount = 1 and @UnderscoreAt < 2
	BEGIN
		SET @p_FileNameLoaded = NULL
	END
END
GO

ALTER AUTHORIZATION ON [dbo].[usp_ESSelect] TO SCHEMA OWNER;
GO
