-- ProcessESFileSQL step 1: SelectFile
DECLARE @p_Directory varchar(510)
DECLARE @p_FileNameLoaded varchar(510)
DECLARE @SuccessYN char(1) = 'Y'
DECLARE @Username varchar(125) = 'FCSA'

SET @p_Directory = '\\10.0.0.39\d$\updates\primary\UnprocessedESFiles'

EXEC usp_ESSelect @p_Directory, @Username, @p_FileNameLoaded OUTPUT

-- Do not steal rewrite DbUpdate files already queued for MeUpdate.
IF @p_FileNameLoaded IS NOT NULL
AND OBJECT_ID('adm.t_UpdateQueue_local') IS NOT NULL
AND EXISTS (
    SELECT 1
    FROM adm.t_UpdateQueue_local
    WHERE staging_file = @p_FileNameLoaded
      AND [status] IN ('N', 'P')
)
BEGIN
    DELETE FROM t_ProcessingFilesListES
    WHERE OriginalFileName = @p_FileNameLoaded
      AND ActiveWorkingFileYN = 'Y'
    SET @p_FileNameLoaded = NULL
END

IF @p_FileNameLoaded IS NULL
BEGIN
    DECLARE @ErrorMessage VARCHAR(4000)
    DECLARE @ErrorSeverity INT = 16
    DECLARE @ErrorState INT = 1
    SET @ErrorMessage = 'We had no file in the Select(1) step of the ES load job on file or we already had an activeWorkingFile ' + isNull(@p_FileNameLoaded, 'No File to Load')

    RAISERROR (@ErrorMessage,
               @ErrorSeverity,
               @ErrorState)
END
