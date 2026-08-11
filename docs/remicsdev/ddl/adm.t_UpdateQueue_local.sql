-- remicsdev local DbUpdate auto-processing queue (EC2AMAZ-9DKDM82)
-- Processed by SQL Agent job "Update Queue Local" via remote PowerShell on IIS-REMICS-PROD.

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'adm.t_UpdateQueue_local', N'U') IS NULL
BEGIN
    CREATE TABLE adm.t_UpdateQueue_local (
        queue_id          INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        staging_file      NVARCHAR(260)  NOT NULL,
        staging_path      NVARCHAR(500)  NOT NULL,
        submitter         NVARCHAR(50)   NOT NULL,
        pdf_name          NVARCHAR(64)   NOT NULL,
        file_type         NVARCHAR(2)    NOT NULL,
        submitter_email   NVARCHAR(500)  NULL,
        [status]          CHAR(1)        NOT NULL CONSTRAINT DF_UpdateQueue_local_status DEFAULT ('N'),
        job_id            NVARCHAR(32)   NULL,
        [mode]            NVARCHAR(20)   NOT NULL CONSTRAINT DF_UpdateQueue_local_mode DEFAULT ('spoof-first'),
        ErrorMsg          NVARCHAR(MAX)  NULL,
        AttemptCount      INT            NOT NULL CONSTRAINT DF_UpdateQueue_local_attempts DEFAULT (0),
        Created           DATETIME       NOT NULL CONSTRAINT DF_UpdateQueue_local_created DEFAULT (GETDATE()),
        Processed         DATETIME       NULL
    );

    CREATE INDEX IX_UpdateQueue_local_pending
        ON adm.t_UpdateQueue_local ([status], queue_id);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_UpdateQueue_local_staging_active'
      AND object_id = OBJECT_ID(N'adm.t_UpdateQueue_local')
)
BEGIN
    CREATE UNIQUE INDEX UX_UpdateQueue_local_staging_active
        ON adm.t_UpdateQueue_local (staging_file)
        WHERE [status] IN ('N', 'P');
END
GO
