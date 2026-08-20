-- ProcessESFileSQL step 3: Import Data
-- ES has no usp_TSTransactionDefine equivalent.
DECLARE @SuccessYN char(1) = 'Y'
DECLARE @p_FileNameLoaded varchar(510)
DECLARE @Username varchar(125) = 'FCSA'

SELECT @p_FileNameLoaded = OriginalFilename, @SuccessYN = SelectedYN, @Username = Username
FROM t_ProcessingFilesListES
WHERE ActiveWorkingFileYN = 'Y'

IF @SuccessYN = 'Y'
BEGIN
    EXEC usp_ESImport @p_FileNameLoaded, @Username
END
ELSE
BEGIN
    DECLARE @ErrorMessage VARCHAR(4000)
    DECLARE @ErrorSeverity INT = 16
    DECLARE @ErrorState INT = 1
    SET @ErrorMessage = 'We had an error in the Insert(3) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File')

    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)
END
