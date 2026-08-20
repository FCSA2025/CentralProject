-- ProcessESFileSQL step 4: Validate
DECLARE @SuccessYN CHAR(1) = 'Y'
DECLARE @p_FileNameLoaded VARCHAR(510)
DECLARE @Username varchar(125) = 'FCSA'
DECLARE @ErrorMessage VARCHAR(4000)
DECLARE @ErrorSeverity INT = 16
DECLARE @ErrorState INT = 1

SELECT @p_FileNameLoaded = OriginalFilename, @SuccessYN = ImportedYN, @Username = Username
FROM t_ProcessingFilesListES
WHERE ActiveWorkingFileYN = 'Y'

IF @SuccessYN = 'Y'
BEGIN
    EXEC usp_ESValidate @p_FileNameLoaded, @Username, @SuccessYN OUTPUT
END
ELSE
BEGIN
    SET @ErrorMessage = 'We had an error in the Import (3) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File')

    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)
END

SELECT @p_FileNameLoaded = OriginalFilename, @SuccessYN = ValidatedYN, @Username = Username
FROM t_ProcessingFilesListES
WHERE ActiveWorkingFileYN = 'Y'

IF @SuccessYN = 'N'
BEGIN
    SET @ErrorMessage = 'We had an error in the Validate(4) bottom step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File') + ' for user ' + isNull(@Username, 'Unknown User') + '.'

    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)

    UPDATE t_ProcessingFilesListES
    SET ActiveWorkingFileYN = 'N'
    WHERE ActiveWorkingFileYN = 'Y'
END
