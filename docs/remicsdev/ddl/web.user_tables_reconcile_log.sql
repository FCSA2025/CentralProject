-- remicsdev: audit log for web.user_tables reconcile
-- See docs/remicsdev/user-tables-reconcile.md

IF OBJECT_ID(N'web.user_tables_reconcile_run', N'U') IS NULL
BEGIN
    CREATE TABLE web.user_tables_reconcile_run (
        run_id            INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        started_at        DATETIME2(3)   NOT NULL CONSTRAINT DF_utr_run_started DEFAULT (SYSUTCDATETIME()),
        finished_at       DATETIME2(3)   NULL,
        mode              CHAR(4)        NOT NULL,  -- LIVE / DRY
        operator_filter   VARCHAR(8)     NULL,
        deleted_orphans   INT            NOT NULL CONSTRAINT DF_utr_run_del DEFAULT (0),
        inserted_missing  INT            NOT NULL CONSTRAINT DF_utr_run_ins DEFAULT (0),
        updated_validstat INT            NOT NULL CONSTRAINT DF_utr_run_upd DEFAULT (0),
        notes             NVARCHAR(400)  NULL
    );
END
GO

IF OBJECT_ID(N'web.user_tables_reconcile_log', N'U') IS NULL
BEGIN
    CREATE TABLE web.user_tables_reconcile_log (
        log_id      INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
        run_id      INT            NOT NULL,
        logged_at   DATETIME2(3)   NOT NULL CONSTRAINT DF_utr_log_at DEFAULT (SYSUTCDATETIME()),
        action      VARCHAR(20)    NOT NULL,  -- DELETE_ORPHAN / INSERT_MISSING / UPDATE_VALIDSTAT
        operator    VARCHAR(8)     NOT NULL,
        tabletype   INT            NOT NULL,
        file_name   VARCHAR(128)   NOT NULL,
        detail      NVARCHAR(200)  NULL,
        CONSTRAINT FK_utr_log_run FOREIGN KEY (run_id)
            REFERENCES web.user_tables_reconcile_run (run_id)
    );

    CREATE INDEX IX_utr_log_run ON web.user_tables_reconcile_log (run_id);
END
GO
