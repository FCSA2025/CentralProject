-- ProcessESFileSQL step 6: Completed
DECLARE @SuccessYN char(1) = 'Y'
DECLARE @p_FileNameLoaded varchar(510)

SELECT @SuccessYN = UpdatedYN FROM t_ProcessingFilesListES WHERE ActiveWorkingFileYN = 'Y'

IF @SuccessYN = 'Y'
BEGIN
    UPDATE t_ProcessingFilesListES
    SET CompletedDate = GETDATE()
    WHERE ActiveWorkingFileYN = 'Y'
END
ELSE
BEGIN
    DECLARE @ErrorMessage VARCHAR(4000)
    DECLARE @ErrorSeverity INT = 16
    DECLARE @ErrorState INT = 1
    SET @ErrorMessage = 'We had an error in the output(6) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File')

    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)

    UPDATE t_ProcessingFilesListES
    SET ActiveWorkingFileYN = 'N'
    WHERE ActiveWorkingFileYN = 'Y'
END
