/*
  TSIP run archive — Phase 1 registry (shared web schema).
  CREATE-only; does not alter existing tables.
*/
SET NOCOUNT ON;

IF OBJECT_ID(N'web.tsip_run', N'U') IS NULL
BEGIN
    CREATE TABLE web.tsip_run (
        run_id            BIGINT         IDENTITY(1,1) NOT NULL,
        mics_user         VARCHAR(32)    NOT NULL,
        source_schema     VARCHAR(128)   NOT NULL,
        parm_file         VARCHAR(64)    NOT NULL,
        run_name          VARCHAR(64)    NOT NULL,
        view_name         VARCHAR(128)   NOT NULL,
        protype           CHAR(1)        NOT NULL,
        run_started_utc   DATETIME2(3)   NOT NULL CONSTRAINT DF_tsip_run_started DEFAULT (SYSUTCDATETIME()),
        run_finished_utc  DATETIME2(3)   NULL,
        num_int_cases     INT            NULL,
        queue_job_id      INT            NULL,
        archive_status    VARCHAR(16)    NOT NULL,
        archive_message   NVARCHAR(500)  NULL,
        CONSTRAINT PK_tsip_run PRIMARY KEY CLUSTERED (run_id),
        CONSTRAINT CK_tsip_run_protype CHECK (protype IN ('T', 'E')),
        CONSTRAINT CK_tsip_run_archive_status CHECK (archive_status IN ('pending', 'complete', 'partial', 'failed'))
    );

    CREATE INDEX IX_tsip_run_user_started
        ON web.tsip_run (mics_user, run_started_utc DESC);

    CREATE INDEX IX_tsip_run_parm_started
        ON web.tsip_run (source_schema, parm_file, run_name, run_started_utc DESC);
END;

IF OBJECT_ID(N'web.tsip_run_parm_ts', N'U') IS NULL
BEGIN
    CREATE TABLE web.tsip_run_parm_ts (
        run_id      BIGINT       NOT NULL,
        protype     CHAR(1)      NULL,
        envtype     CHAR(8)      NULL,
        proname     CHAR(16)     NULL,
        envname     CHAR(16)     NULL,
        tsorbout    CHAR(1)      NULL,
        spherecalc  CHAR(1)      NULL,
        fsep        FLOAT        NULL,
        coordist    FLOAT        NULL,
        analopt     CHAR(4)      NULL,
        margin      FLOAT        NULL,
        numchan     SMALLINT     NULL,
        chancodes   CHAR(19)     NULL,
        tempant     CHAR(15)     NULL,
        tempctx     CHAR(15)     NULL,
        tempplan    CHAR(15)     NULL,
        tempequip   CHAR(15)     NULL,
        country     CHAR(3)      NULL,
        selsites    CHAR(15)     NULL,
        numcodes    SMALLINT     NULL,
        codes       CHAR(164)    NULL,
        runname     CHAR(5)      NULL,
        reports     INT          NULL,
        numcases    INT          NULL,
        numtecases  INT          NULL,
        parmparm    CHAR(50)     NULL,
        mdate       CHAR(10)     NULL,
        mtime       CHAR(8)      NULL,
        CONSTRAINT PK_tsip_run_parm_ts PRIMARY KEY CLUSTERED (run_id),
        CONSTRAINT FK_tsip_run_parm_ts_run FOREIGN KEY (run_id)
            REFERENCES web.tsip_run (run_id) ON DELETE CASCADE
    );
END;

IF OBJECT_ID(N'web.tsip_run_parm_es', N'U') IS NULL
BEGIN
    CREATE TABLE web.tsip_run_parm_es (
        run_id      BIGINT       NOT NULL,
        protype     CHAR(1)      NULL,
        envtype     CHAR(8)      NULL,
        proname     CHAR(16)     NULL,
        envname     CHAR(16)     NULL,
        tsorbout    CHAR(1)      NULL,
        spherecalc  CHAR(1)      NULL,
        fsep        FLOAT        NULL,
        coordist    FLOAT        NULL,
        analopt     CHAR(4)      NULL,
        margin      FLOAT        NULL,
        numchan     SMALLINT     NULL,
        chancodes   CHAR(19)     NULL,
        tempant     CHAR(15)     NULL,
        tempctx     CHAR(15)     NULL,
        tempplan    CHAR(15)     NULL,
        tempequip   CHAR(15)     NULL,
        country     CHAR(3)      NULL,
        selsites    CHAR(15)     NULL,
        numcodes    SMALLINT     NULL,
        codes       CHAR(164)    NULL,
        runname     CHAR(5)      NULL,
        reports     INT          NULL,
        numcases    INT          NULL,
        numtecases  INT          NULL,
        parmparm    CHAR(50)     NULL,
        mdate       CHAR(10)     NULL,
        mtime       CHAR(8)      NULL,
        CONSTRAINT PK_tsip_run_parm_es PRIMARY KEY CLUSTERED (run_id),
        CONSTRAINT FK_tsip_run_parm_es_run FOREIGN KEY (run_id)
            REFERENCES web.tsip_run (run_id) ON DELETE CASCADE
    );
END;
