-- ProcessESFileSQL step 7: Completion (archive + delete inbox file)
DECLARE @SuccessYN char(1)
DECLARE @p_FileNameLoaded varchar(510)
DECLARE @Username varchar(125) = 'FCSA'
DECLARE @ErrorMessage VARCHAR(4000)
DECLARE @ErrorSeverity INT = 16
DECLARE @ErrorState INT = 1

SELECT @p_FileNameLoaded = OriginalFilename, @SuccessYN = UpdatedYN, @Username = Username
FROM t_ProcessingFilesListES
WHERE ActiveWorkingFileYN = 'Y'

IF @SuccessYN = 'Y'
BEGIN
    EXEC usp_ESComplete @p_FileNameLoaded, @Username
END
ELSE
BEGIN
    SET @ErrorMessage = 'We had an error in the compltion(7) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File')
    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)
END

SELECT @SuccessYN = CompletedYN
FROM t_ProcessingFilesListES
WHERE OriginalFilename = @p_FileNameLoaded
  AND ID = (SELECT MAX(ID) FROM t_ProcessingFilesListES)

IF @SuccessYN = 'Y'
BEGIN
    DECLARE @Source Varchar(2055) = 'copy \\10.0.0.39\d$\updates\primary\UnprocessedESFiles\' + @p_FileNameLoaded + ' '
    DECLARE @Destination Varchar(2055) = '\\10.0.0.39\d$\updates\primary\UnprocessedESFiles\RelCompleted\' + @p_FileNameLoaded
    DECLARE @SQLCopyCommand Varchar(4300) = @Source + @Destination
    EXEC master..xp_cmdshell @SQLCopyCommand

    DECLARE @SQLDelCommand Varchar(4300) = 'del \\10.0.0.39\d$\updates\primary\UnprocessedESFiles\' + @p_FileNameLoaded + ' '
    EXEC master..xp_cmdshell @SQLDelCommand

    DELETE FROM t_ESLoadRaw WHERE OriginalFileName = @p_FileNameLoaded AND Username = @Username

    UPDATE t_ProcessingFilesListES
    SET ActiveWorkingFileYN = 'N'
    WHERE ActiveWorkingFileYN = 'Y'
END
ELSE
BEGIN
    SET @ErrorMessage = 'We had an error late in the compltion(7) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File')
    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)

    UPDATE t_ProcessingFilesListES
    SET ActiveWorkingFileYN = 'N'
    WHERE ActiveWorkingFileYN = 'Y'
END

IF NOT EXISTS (SELECT * FROM t_ESLoadRaw)
BEGIN
    DBCC CHECKIDENT ('[t_ESLoadRaw]', RESEED, 0)
END
