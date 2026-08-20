-- ProcessESFileSQL step 8: Error + notify submitter
-- Agent T-SQL defaults QUOTED_IDENTIFIER OFF; filtered index on t_EmailQueue_local requires ON.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @p_FileNameLoaded varchar(510)
DECLARE @Username varchar(125)
DECLARE @ValidatedYN char(1)
DECLARE @UpdatedYN char(1)
DECLARE @UserEmail nvarchar(500)
DECLARE @OriginalEmail nvarchar(500)
DECLARE @MailTo nvarchar(500)
DECLARE @MailCC nvarchar(500)
DECLARE @MailSubject nvarchar(100)
DECLARE @MailBody nvarchar(max)
DECLARE @ErrDetails nvarchar(max)
DECLARE @AlwaysCc nvarchar(100) = N'jscott@fcsa.ca'
-- Testing: only @fcsa.ca addresses receive operator mail. Set to 0 in production.
DECLARE @FcsaOnlyTesting bit = 1

SELECT @p_FileNameLoaded = OriginalFilename, @Username = Username,
       @ValidatedYN = ValidatedYN, @UpdatedYN = UpdatedYN
FROM t_ProcessingFilesListES
WHERE ActiveWorkingFileYN = 'Y'

IF @p_FileNameLoaded IS NULL
BEGIN
    SELECT TOP 1
        @p_FileNameLoaded = OriginalFilename,
        @Username = Username,
        @ValidatedYN = ValidatedYN,
        @UpdatedYN = UpdatedYN
    FROM t_ProcessingFilesListES
    ORDER BY ID DESC
END

UPDATE t_ProcessingFilesListES
SET ErrorYN = 'Y', ActiveWorkingFileYN = 'N'
WHERE ActiveWorkingFileYN = 'Y'
   OR (OriginalFileName = @p_FileNameLoaded
       AND ID = (SELECT MAX(ID) FROM t_ProcessingFilesListES WHERE OriginalFileName = @p_FileNameLoaded))

SELECT TOP 1 @UserEmail = NULLIF(RTRIM(email), '')
FROM adm.account_details
WHERE RTRIM(micsid) = RTRIM(@Username)

IF @UserEmail IS NULL
BEGIN
    SELECT TOP 1 @UserEmail = NULLIF(RTRIM(email), '')
    FROM dbo.t_UserDetails
    WHERE RTRIM(micsId) = RTRIM(@Username)
END

SET @OriginalEmail = @UserEmail
SET @MailCC = @AlwaysCc

IF @FcsaOnlyTesting = 1 AND (@UserEmail IS NULL OR LOWER(@UserEmail) NOT LIKE '%@fcsa.ca')
    SET @MailTo = @AlwaysCc
ELSE IF @UserEmail IS NULL
    SET @MailTo = @AlwaysCc
ELSE
    SET @MailTo = @UserEmail

IF LOWER(@MailTo) = LOWER(@AlwaysCc)
    SET @MailCC = NULL

SET @ErrDetails = NULL
SELECT @ErrDetails = STUFF((
    SELECT TOP 8 CHAR(13) + CHAR(10) + CAST(LineNumber AS varchar(12)) + ': ' + LEFT(REPLACE(REPLACE(ISNULL(ErrorList, ''), CHAR(13), ' '), CHAR(10), ' '), 180)
    FROM t_ESLoadRaw
    WHERE OriginalFileName = @p_FileNameLoaded
      AND Username = @Username
      AND ErrorYN = 'Y'
    ORDER BY LineNumber
    FOR XML PATH(''), TYPE
).value('.', 'nvarchar(max)'), 1, 2, '')

IF ISNULL(@ValidatedYN, 'N') = 'N'
    SET @MailSubject = LEFT(N'ES file validation failed - ' + ISNULL(@p_FileNameLoaded, N'unknown'), 100)
ELSE
    SET @MailSubject = LEFT(N'ES file processing failed - ' + ISNULL(@p_FileNameLoaded, N'unknown'), 100)

SET @MailBody =
    N'Your ES file failed during the remicsdev ProcessESFileSQL job.' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
    N'File: ' + ISNULL(@p_FileNameLoaded, N'(unknown)') + CHAR(13) + CHAR(10) +
    N'Submitter: ' + ISNULL(@Username, N'(unknown)') + CHAR(13) + CHAR(10) +
    N'ValidatedYN: ' + ISNULL(@ValidatedYN, N'?') + CHAR(13) + CHAR(10) +
    N'UpdatedYN: ' + ISNULL(@UpdatedYN, N'?') + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) +
    N'Validation / processing errors:' + CHAR(13) + CHAR(10) +
    ISNULL(@ErrDetails, N'(no row-level errors recorded)') + CHAR(13) + CHAR(10)

IF @FcsaOnlyTesting = 1
    SET @MailBody = @MailBody + CHAR(13) + CHAR(10) +
        N'[Testing] FCSA-only recipients. Original operator email: ' + ISNULL(@OriginalEmail, N'(none)') + CHAR(13) + CHAR(10)

BEGIN TRY
    INSERT INTO adm.t_EmailQueue_local (mailFrom, mailTo, mailCC, mailSubject, mailBody, mailBodyFormat, mailAttachments, sentYN)
    VALUES (
        N'mics@fcsa.ca',
        @MailTo,
        @MailCC,
        @MailSubject,
        @MailBody,
        N'TEXT',
        NULL,
        N'N'
    )
END TRY
BEGIN CATCH
    -- Do not fail the error step if queue insert fails.
    PRINT 'ProcessESFileSQL notify failed: ' + ERROR_MESSAGE()
END CATCH
