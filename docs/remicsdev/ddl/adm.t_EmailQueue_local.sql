-- remicsdev local email queue (EC2AMAZ-9DKDM82 IIS only)
-- Processed by SQL Agent job "Email Queue Local" — not the legacy "Email Queue" job.

IF OBJECT_ID(N'adm.t_EmailQueue_local', N'U') IS NULL
BEGIN
    CREATE TABLE adm.t_EmailQueue_local (
        mail_sequence     INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        mailFrom          NVARCHAR(50)   NOT NULL,
        mailTo            NVARCHAR(500)  NOT NULL,
        mailCC            NVARCHAR(500)  NULL,
        mailSubject       NVARCHAR(100)  NOT NULL,
        mailBody          NVARCHAR(MAX)  NOT NULL,
        mailBodyFormat    NVARCHAR(50)   NOT NULL CONSTRAINT DF_EmailQueue_local_BodyFormat DEFAULT ('TEXT'),
        mailAttachments   NVARCHAR(4000) NULL,
        sentYN            CHAR(1)        NOT NULL CONSTRAINT DF_EmailQueue_local_sentYN DEFAULT ('N'),
        SentDate          DATETIME       NULL,
        ErrorMsg          NVARCHAR(MAX)  NULL,
        AttemptCount      INT            NULL,
        LastAttempt       DATETIME       NULL
    );

    CREATE INDEX IX_EmailQueue_local_pending
        ON adm.t_EmailQueue_local (sentYN, mail_sequence);
END
GO
