-- remicsdev unified DbUpdate inbox processing registry (audit; work queue stays in adm.t_UpdateQueue_local)
-- TS/ES today; ANT/EQP reserved for future subsidiary processing.

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'adm.t_InboxProcessing_local', N'U') IS NULL
BEGIN
    CREATE TABLE adm.t_InboxProcessing_local (
        processing_id     BIGINT         IDENTITY(1,1) NOT NULL PRIMARY KEY,
        file_type         NVARCHAR(3)    NOT NULL,
        processing_kind   NVARCHAR(20)   NOT NULL CONSTRAINT DF_InboxProc_local_kind DEFAULT ('dbupdate'),
        staging_file      NVARCHAR(260)  NOT NULL,
        submitter         NVARCHAR(50)   NULL,
        pdf_name          NVARCHAR(64)   NULL,
        queue_id          INT            NULL,
        job_id            NVARCHAR(32)   NULL,
        lifecycle_status  NVARCHAR(20)   NOT NULL,
        validated_code    NVARCHAR(1)    NULL,
        error_yn          BIT            NOT NULL CONSTRAINT DF_InboxProc_local_error DEFAULT (0),
        error_message     NVARCHAR(MAX)  NULL,
        failed_step       NVARCHAR(64)   NULL,
        inbox_path        NVARCHAR(500)  NULL,
        current_path      NVARCHAR(500)  NULL,
        archive_dir       NVARCHAR(500)  NULL,
        [mode]            NVARCHAR(20)   NULL,
        execution_user    NVARCHAR(50)   NULL,
        [source]          NVARCHAR(32)   NOT NULL,
        created           DATETIME       NOT NULL CONSTRAINT DF_InboxProc_local_created DEFAULT (GETDATE()),
        started           DATETIME       NULL,
        completed         DATETIME       NULL,
        archived          DATETIME       NULL,
        CONSTRAINT CK_InboxProc_local_file_type CHECK (file_type IN ('TS', 'ES', 'ANT', 'EQP')),
        CONSTRAINT CK_InboxProc_local_lifecycle CHECK (lifecycle_status IN (
            'inbox', 'queued', 'processing', 'completed', 'failed', 'stale_archived'
        ))
    );

    CREATE INDEX IX_InboxProcessing_local_file
        ON adm.t_InboxProcessing_local (staging_file, created DESC);

    CREATE INDEX IX_InboxProcessing_local_lifecycle
        ON adm.t_InboxProcessing_local (lifecycle_status, file_type, created DESC);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_InboxProcessing_local_staging_active'
      AND object_id = OBJECT_ID(N'adm.t_InboxProcessing_local')
)
BEGIN
    CREATE UNIQUE INDEX UX_InboxProcessing_local_staging_active
        ON adm.t_InboxProcessing_local (staging_file)
        WHERE lifecycle_status IN ('inbox', 'queued', 'processing');
END
GO
