-- remicsdev: audit log for nightly Gate F regression (RemIcsReWrite)
-- See docs/remicsdev/gate-f-regression.md

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'web.gate_f_regression_run', N'U') IS NULL
BEGIN
    CREATE TABLE web.gate_f_regression_run (
        run_id               INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        started_at           DATETIME2(3)   NOT NULL CONSTRAINT DF_gfr_run_started DEFAULT (SYSUTCDATETIME()),
        finished_at          DATETIME2(3)   NULL,
        ok                   BIT            NOT NULL CONSTRAINT DF_gfr_run_ok DEFAULT (1),
        cross_company_count  INT            NOT NULL CONSTRAINT DF_gfr_run_cc DEFAULT (0),
        catalog_orphans      INT            NOT NULL CONSTRAINT DF_gfr_run_orph DEFAULT (0),
        catalog_missing      INT            NOT NULL CONSTRAINT DF_gfr_run_miss DEFAULT (0),
        reconcile_stale      BIT            NOT NULL CONSTRAINT DF_gfr_run_stale DEFAULT (0),
        email_sent           BIT            NOT NULL CONSTRAINT DF_gfr_run_mail DEFAULT (0),
        notes                NVARCHAR(MAX)  NULL
    );
END
GO

IF OBJECT_ID(N'web.gate_f_regression_finding', N'U') IS NULL
BEGIN
    CREATE TABLE web.gate_f_regression_finding (
        finding_id   INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        run_id       INT            NOT NULL,
        check_name   VARCHAR(40)    NOT NULL,
        severity     VARCHAR(10)    NOT NULL CONSTRAINT DF_gfr_find_sev DEFAULT ('ERROR'),
        detail       NVARCHAR(500)  NOT NULL,
        CONSTRAINT FK_gfr_find_run FOREIGN KEY (run_id)
            REFERENCES web.gate_f_regression_run (run_id)
    );

    CREATE INDEX IX_gfr_find_run ON web.gate_f_regression_finding (run_id);
END
GO
