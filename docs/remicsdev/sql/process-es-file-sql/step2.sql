-- ProcessESFileSQL step 2: Load File Raw
DECLARE @SuccessYN char(1) = 'Y'
DECLARE @p_Directory varchar(510)
DECLARE @p_FileNameLoaded varchar(510)
DECLARE @Username varchar(125) = 'FCSA'

SELECT @p_FileNameLoaded = OriginalFilename, @SuccessYN = SelectedYN, @Username = Username
FROM t_ProcessingFilesListES
WHERE ActiveWorkingFileYN = 'Y'

SET @p_Directory = '\\10.0.0.39\d$\updates\primary\UnprocessedESFiles'

IF @SuccessYN = 'Y'
BEGIN
    DELETE FROM t_ESLoadRaw WHERE Username = @Username AND OriginalFileName = @p_FileNameLoaded
    EXEC usp_ESLoad @p_Directory, @p_FileNameLoaded
END
ELSE
BEGIN
    DECLARE @ErrorMessage VARCHAR(4000)
    DECLARE @ErrorSeverity INT = 16
    DECLARE @ErrorState INT = 1
    SET @ErrorMessage = 'We had an error in the Load(2) step of the ES load job on file ' + isNull(@p_FileNameLoaded, 'Unknown File')

    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)
END
