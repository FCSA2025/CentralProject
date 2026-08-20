-- ProcessESFileSQL step 5: Update File
DECLARE @SuccessYN CHAR(1) = 'Y'
DECLARE @p_FileNameLoaded VARCHAR(510)
DECLARE @Username varchar(125) = 'FCSA'
DECLARE @ErrorMessage VARCHAR(4000)
DECLARE @ErrorSeverity INT = 16
DECLARE @ErrorState INT = 1

SELECT @p_FileNameLoaded = OriginalFilename, @Username = Username, @SuccessYN = ValidatedYN
FROM t_ProcessingFilesListES
WHERE ActiveWorkingFileYN = 'Y'

IF @SuccessYN = 'Y'
BEGIN
    EXEC usp_ESUpdate @p_FileNameLoaded, @Username
END
ELSE
BEGIN
    SET @ErrorMessage = 'We had an error in the validate(4) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File') + ' for user ' + isNull(@Username, 'Unknown User') + '.'
    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)
    UPDATE t_ProcessingFilesListES
    SET ActiveWorkingFileYN = 'N'
    WHERE ActiveWorkingFileYN = 'Y'
END

SELECT @SuccessYN = UpdatedYN FROM t_ProcessingFilesListES WHERE ActiveWorkingFileYN = 'Y'

IF @SuccessYN = 'N'
BEGIN
    SET @ErrorMessage = 'We had an error in the update(5) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File') + ' for user ' + isNull(@Username, 'Unknown User') + '.'
    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)
    UPDATE t_ProcessingFilesListES
    SET ActiveWorkingFileYN = 'N'
    WHERE ActiveWorkingFileYN = 'Y'
END
