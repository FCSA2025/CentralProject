-- SQL Agent job step: "Mail Files Local" (Email Queue Local)
-- remicsdev / EC2AMAZ-9DKDM82 only — reads adm.t_EmailQueue_local
-- Attachment paths: \\IIS-REMICS-PROD\MicsEmailStaging\... (UNC from IIS staging share)
-- Schedule: every 1 minute. Profile: AlertMailProfile.

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @MaxPerRun INT;
SET @MaxPerRun = 10;

DECLARE
    @mail_sequence     INT               = NULL,
    @mailFrom          NVARCHAR(50)      = NULL,
    @mailTo            NVARCHAR(500)     = NULL,
    @mailCC            NVARCHAR(500)     = NULL,
    @mailSubject       NVARCHAR(100)     = NULL,
    @mailBody          NVARCHAR(MAX)     = NULL,
    @mailBodyFormat    NVARCHAR(50)      = NULL,
    @mailAttachments   NVARCHAR(4000)    = NULL,
    @SendBodyFormat    VARCHAR(20)       = 'TEXT',

    @profile_name      NVARCHAR(128)     = 'AlertMailProfile',
    @RowsAffected      INT               = 0,
    @ErrorMessage      NVARCHAR(2048)    = NULL,
    @OriginalMailTo    NVARCHAR(500)     = NULL,
    @OriginalSubject   NVARCHAR(100)     = NULL,
    @ProblemFiles      NVARCHAR(MAX)     = NULL,

    @CurrentMailSequence INT             = NULL,
    @ErrorOccurred     BIT               = 0,
    @CompositeErrorMsg NVARCHAR(MAX)     = NULL,
    @ProcessedCount    INT               = 0,

    @ErrorSubject      NVARCHAR(200)     = NULL,
    @ErrorBody         NVARCHAR(MAX)     = NULL,
    @TeamRecipients    NVARCHAR(500)     = NULL,

    @FileList          VARCHAR(4000)     = NULL,
    @Pos               INT               = NULL,
    @NextPos           INT               = NULL,
    @Item              NVARCHAR(4000)    = NULL,
    @FileName          VARCHAR(4000)     = NULL,
    @Cmd               VARCHAR(8000)     = NULL,
    @Result            VARCHAR(4000)     = NULL,
    @FileSize          BIGINT            = NULL,
    @ShortName         VARCHAR(4000)     = NULL,
    @FileExistsFlag    INT               = NULL,
    @CleanupDir        VARCHAR(4000)     = NULL,
    @FirstAttach       VARCHAR(4000)     = NULL;

DECLARE @Files TABLE (FileName VARCHAR(4000));

WHILE @ProcessedCount < @MaxPerRun
BEGIN
    SET @mail_sequence       = NULL;
    SET @mailFrom            = NULL;
    SET @mailTo              = NULL;
    SET @mailCC              = NULL;
    SET @mailSubject         = NULL;
    SET @mailBody            = NULL;
    SET @mailBodyFormat      = NULL;
    SET @mailAttachments     = NULL;
    SET @SendBodyFormat      = 'TEXT';
    SET @OriginalMailTo      = NULL;
    SET @OriginalSubject     = NULL;
    SET @ProblemFiles        = NULL;
    SET @CurrentMailSequence = NULL;
    SET @ErrorOccurred       = 0;
    SET @CompositeErrorMsg   = '';
    SET @RowsAffected        = 0;
    SET @ErrorMessage        = NULL;
    SET @ErrorSubject        = NULL;
    SET @ErrorBody           = NULL;
    SET @CleanupDir         = NULL;
    SET @FirstAttach         = NULL;
    DELETE FROM @Files;

    BEGIN TRY
        SELECT TOP (1)
            @mail_sequence     = mail_sequence,
            @mailFrom          = mailFrom,
            @mailTo            = mailTo,
            @mailCC            = mailCC,
            @mailSubject       = mailSubject,
            @mailBody          = mailBody,
            @mailBodyFormat    = mailBodyFormat,
            @mailAttachments   = mailAttachments,
            @OriginalMailTo    = mailTo,
            @OriginalSubject   = mailSubject
        FROM [adm].[t_EmailQueue_local]
        WHERE sentYN = 'N'
        ORDER BY mail_sequence ASC;

        SET @RowsAffected = @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = 'Error selecting email from local queue: ' + ERROR_MESSAGE();
        PRINT @ErrorMessage;
        RAISERROR(@ErrorMessage, 16, 1);
        BREAK;
    END CATCH;

    IF @RowsAffected = 0
        BREAK;

    SET @CurrentMailSequence = @mail_sequence;
    SET @SendBodyFormat = @mailBodyFormat;
    IF @SendBodyFormat IS NULL OR @SendBodyFormat = ''
        SET @SendBodyFormat = 'TEXT';

    IF @mailFrom = 'mics.fcsa.ca'
        SET @mailFrom = 'mics@fcsa.ca';

    PRINT 'Processing local mail_sequence ' + CAST(@CurrentMailSequence AS VARCHAR(20));

    BEGIN TRY
        UPDATE [adm].[t_EmailQueue_local]
        SET mailAttachments = REPLACE(mailAttachments, '\\EC2AMAZ-9DKDM82\REMICS-D:', 'D:')
        WHERE mailAttachments LIKE '%EC2AMAZ-9DKDM82%'
          AND mail_sequence = @CurrentMailSequence;

        SELECT @mailAttachments = mailAttachments
        FROM [adm].[t_EmailQueue_local]
        WHERE mail_sequence = @CurrentMailSequence;

        IF @mailAttachments IS NOT NULL AND @mailAttachments <> ''
        BEGIN
            IF (@mailAttachments LIKE '%EC2AMAZ-2013EDB%' OR @mailAttachments LIKE '%10.0.0.67%')
               AND @mailAttachments NOT LIKE '%\MicsEmailStaging\%'
            BEGIN
                SET @ErrorOccurred = 1;
                SET @CompositeErrorMsg = @CompositeErrorMsg + 'Foreign prod path in local queue — use adm.t_EmailQueue for legacy prod IIS; ';
            END
        END
    END TRY
    BEGIN CATCH
        SET @ErrorOccurred = 1;
        SET @CompositeErrorMsg = @CompositeErrorMsg + 'Error fixing file paths: ' + ERROR_MESSAGE() + '; ';
    END CATCH;

    IF @ErrorOccurred = 0 AND @mailAttachments IS NOT NULL AND @mailAttachments <> ''
    BEGIN
        SET @FileList = REPLACE(REPLACE(@mailAttachments, CHAR(13), ''), CHAR(10), '');

        IF @FileList <> ''
        BEGIN
            SET @Pos = 1;
            SET @FileList = @FileList + ';';

            WHILE @Pos <= LEN(@FileList)
            BEGIN
                SET @NextPos = CHARINDEX(';', @FileList, @Pos);
                IF @NextPos = 0
                    SET @NextPos = LEN(@FileList) + 1;

                SET @Item = LTRIM(RTRIM(SUBSTRING(@FileList, @Pos, @NextPos - @Pos)));

                IF @Item <> ''
                    INSERT INTO @Files (FileName) VALUES (@Item);

                SET @Pos = @NextPos + 1;
            END;

            IF OBJECT_ID('tempdb..#Results') IS NOT NULL
                DROP TABLE #Results;

            CREATE TABLE #Results (
                FileName      VARCHAR(4000),
                ExistsFlag    BIT,
                FileSizeBytes BIGINT NULL,
                Status        VARCHAR(100)
            );

            WHILE EXISTS (SELECT 1 FROM @Files)
            BEGIN
                SELECT TOP 1 @FileName = FileName FROM @Files ORDER BY FileName;
                DELETE FROM @Files WHERE FileName = @FileName;

                IF @ErrorOccurred = 1
                    BREAK;

                BEGIN TRY
                    IF OBJECT_ID('tempdb..#Fx') IS NOT NULL
                        DROP TABLE #Fx;

                    CREATE TABLE #Fx (
                        FileExists INT,
                        FileIsDirectory INT,
                        ParentDirectoryExists INT
                    );

                    INSERT INTO #Fx EXEC master.dbo.xp_fileexist @FileName;
                    SET @FileExistsFlag = NULL;
                    SELECT @FileExistsFlag = FileExists FROM #Fx;
                    DROP TABLE #Fx;

                    IF ISNULL(@FileExistsFlag, 0) <> 1
                    BEGIN
                        INSERT INTO #Results VALUES (@FileName, 0, NULL, 'FILE NOT FOUND');
                        SET @ErrorOccurred = 1;
                        SET @CompositeErrorMsg = @CompositeErrorMsg + 'File not found: ' + @FileName + '; ';
                    END
                    ELSE
                    BEGIN
                        INSERT INTO #Results VALUES (@FileName, 1, NULL, 'OK');
                    END;
                END TRY
                BEGIN CATCH
                    SET @ErrorOccurred = 1;
                    SET @CompositeErrorMsg = @CompositeErrorMsg + 'Error checking file ' + ISNULL(@FileName, '(null)') + ': ' + ERROR_MESSAGE() + '; ';
                END CATCH;
            END;

            SET @ProblemFiles = NULL;

            WHILE EXISTS (SELECT 1 FROM #Results WHERE Status IN ('ZERO BYTE FILE', 'FILE NOT FOUND'))
            BEGIN
                SELECT TOP 1
                    @ShortName = CASE
                        WHEN CHARINDEX('\', FileName) > 0
                        THEN RIGHT(FileName, CHARINDEX('\', REVERSE(FileName)) - 1)
                        ELSE FileName
                    END,
                    @FileName = FileName
                FROM #Results
                WHERE Status IN ('ZERO BYTE FILE', 'FILE NOT FOUND')
                ORDER BY FileName;

                DELETE FROM #Results WHERE FileName = @FileName;

                IF @ProblemFiles IS NULL
                    SET @ProblemFiles = @ShortName;
                ELSE
                    SET @ProblemFiles = @ProblemFiles + ';' + @ShortName;
            END;

            DROP TABLE #Results;
        END
    END;

    IF @ErrorOccurred = 1
    BEGIN
        -- Testing: error notifications to jscott only (restore team list before prod cutover)
        SET @TeamRecipients = 'jscott@fcsa.ca';

        IF @OriginalSubject LIKE '%TSIP%'
        BEGIN
            SET @ErrorSubject = 'TSIP Error - ' + @OriginalSubject;
            SET @ErrorBody =
                'TSIP processing error occurred. Original subject: ' + @OriginalSubject +
                '. Errors: ' + @CompositeErrorMsg +
                '. Problem files: ' + ISNULL(@ProblemFiles, '') +
                '. Please check the TSIP integration.';
        END
        ELSE
        BEGIN
            SET @ErrorSubject = 'Email Processing Error - ' + @OriginalSubject;
            SET @ErrorBody =
                'Error processing local queue email (Sequence ' + CAST(@CurrentMailSequence AS VARCHAR(20)) + '):' + CHAR(13) + CHAR(10) +
                'Errors: ' + @CompositeErrorMsg + CHAR(13) + CHAR(10) +
                'Original recipients: ' + ISNULL(@OriginalMailTo, '') + CHAR(13) + CHAR(10) +
                'Original subject: ' + ISNULL(@OriginalSubject, '');
        END;

        BEGIN TRY
            EXEC msdb.dbo.sp_send_dbmail
                @profile_name    = @profile_name,
                @from_address    = @mailFrom,
                @recipients      = @TeamRecipients,
                @copy_recipients = NULL,
                @subject         = @ErrorSubject,
                @body            = @ErrorBody,
                @body_format     = @SendBodyFormat;
        END TRY
        BEGIN CATCH
            PRINT 'Failed to send error notification: ' + ERROR_MESSAGE();
        END CATCH;

        UPDATE [adm].[t_EmailQueue_local]
        SET
            sentYN       = 'E',
            ErrorMsg     = @CompositeErrorMsg,
            mailTo       = @TeamRecipients,
            mailCC       = NULL,
            mailSubject  = @ErrorSubject,
            mailBody     = @ErrorBody,
            AttemptCount = ISNULL(AttemptCount, 0) + 1,
            LastAttempt  = GETDATE()
        WHERE mail_sequence = @CurrentMailSequence;

        PRINT 'Skipped (E). Local sequence: ' + CAST(@CurrentMailSequence AS VARCHAR(20));
    END
    ELSE
    BEGIN
        BEGIN TRY
            IF @mailAttachments IS NULL OR LTRIM(RTRIM(@mailAttachments)) = ''
            BEGIN
                EXEC msdb.dbo.sp_send_dbmail
                    @profile_name     = @profile_name,
                    @from_address     = @mailFrom,
                    @recipients       = @mailTo,
                    @copy_recipients  = @mailCC,
                    @subject          = @mailSubject,
                    @body             = @mailBody,
                    @body_format      = @SendBodyFormat;
            END
            ELSE
            BEGIN
                EXEC msdb.dbo.sp_send_dbmail
                    @profile_name     = @profile_name,
                    @from_address     = @mailFrom,
                    @recipients       = @mailTo,
                    @copy_recipients  = @mailCC,
                    @subject          = @mailSubject,
                    @body             = @mailBody,
                    @body_format      = @SendBodyFormat,
                    @file_attachments = @mailAttachments;
            END

            UPDATE [adm].[t_EmailQueue_local]
            SET
                sentYN   = 'Y',
                SentDate = GETDATE(),
                ErrorMsg = NULL
            WHERE mail_sequence = @mail_sequence;

            -- Staging cleanup (\\IIS-REMICS-PROD\MicsEmailStaging\{batch}\...)
            IF @mailAttachments IS NOT NULL AND @mailAttachments LIKE '%\MicsEmailStaging\%'
            BEGIN
                SET @FirstAttach = LTRIM(RTRIM(
                    CASE WHEN CHARINDEX(';', @mailAttachments) > 0
                         THEN LEFT(@mailAttachments, CHARINDEX(';', @mailAttachments) - 1)
                         ELSE @mailAttachments END));
                IF CHARINDEX('\', @FirstAttach) > 0
                    SET @CleanupDir = LEFT(@FirstAttach, LEN(@FirstAttach) - CHARINDEX('\', REVERSE(@FirstAttach)));
                IF @CleanupDir IS NOT NULL AND @CleanupDir LIKE '%\MicsEmailStaging\%'
                BEGIN
                    SET @Cmd = 'powershell -NoProfile -command "Remove-Item -LiteralPath ''' + REPLACE(@CleanupDir, '''', '''''') + ''' -Recurse -Force -ErrorAction SilentlyContinue"';
                    EXEC xp_cmdshell @Cmd, NO_OUTPUT;
                END
            END

            PRINT 'Sent (Y). Local sequence: ' + CAST(@mail_sequence AS VARCHAR(20));
        END TRY
        BEGIN CATCH
            SET @ErrorMessage =
                'Email send FAILED (Local sequence ' + CAST(@mail_sequence AS VARCHAR(20)) + '): Msg ' +
                CAST(ERROR_NUMBER() AS VARCHAR(20)) + ', Line ' + CAST(ERROR_LINE() AS VARCHAR(20)) + ': ' + ERROR_MESSAGE();

            UPDATE [adm].[t_EmailQueue_local]
            SET
                sentYN       = 'E',
                ErrorMsg     = ISNULL(ErrorMsg + '; ', '') + @ErrorMessage,
                AttemptCount = ISNULL(AttemptCount, 0) + 1,
                LastAttempt  = GETDATE()
            WHERE mail_sequence = @mail_sequence;

            PRINT @ErrorMessage;
        END CATCH;
    END;

    SET @ProcessedCount = @ProcessedCount + 1;
END;

PRINT 'Email Queue Local job finished. Processed ' + CAST(@ProcessedCount AS VARCHAR(20)) + ' row(s).';

SELECT TOP 5 mail_sequence, sentYN, mailSubject, mailTo, ErrorMsg
FROM [adm].[t_EmailQueue_local]
WHERE sentYN = 'N'
ORDER BY mail_sequence ASC;
