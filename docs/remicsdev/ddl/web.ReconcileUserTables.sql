-- remicsdev: reconcile web.user_tables with physical TS / ES / TSIP tables
-- tabletype 0 = TS (ft_*_titl), 5 = ES (fe_*_titl), 417 = TSIP parm (tp_*_parm)
-- See docs/remicsdev/user-tables-reconcile.md

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE web.ReconcileUserTables
    @Operator       VARCHAR(8)  = NULL,  -- NULL = all company schemas
    @DryRun         BIT         = 0,     -- 1 = log only, no writes to user_tables
    @SyncValidstat  BIT         = 1      -- 1 = align catalog validstat from titl.validated
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @run_id INT;
    DECLARE @mode CHAR(4) = CASE WHEN @DryRun = 1 THEN 'DRY' ELSE 'LIVE' END;
    DECLARE @del INT = 0, @ins INT = 0, @upd INT = 0;
    DECLARE @opFilter VARCHAR(8) = NULLIF(RTRIM(@Operator), '');

    INSERT INTO web.user_tables_reconcile_run (mode, operator_filter)
    VALUES (@mode, @opFilter);
    SET @run_id = SCOPE_IDENTITY();

    /* Physical inventory for types we reconcile */
    IF OBJECT_ID('tempdb..#phys') IS NOT NULL DROP TABLE #phys;
    CREATE TABLE #phys (
        operator   VARCHAR(8)  COLLATE DATABASE_DEFAULT NOT NULL,
        tabletype  INT         NOT NULL,
        file_name  VARCHAR(128) COLLATE DATABASE_DEFAULT NOT NULL,
        titl_table SYSNAME     NULL,   -- for validstat lookup (TS/ES only)
        PRIMARY KEY (operator, tabletype, file_name)
    );

    INSERT INTO #phys (operator, tabletype, file_name, titl_table)
    SELECT
        CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)),
        0,
        CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128)),
        t.TABLE_SCHEMA + N'.' + t.TABLE_NAME
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE t.TABLE_TYPE = 'BASE TABLE'
      AND t.TABLE_NAME LIKE 'ft\_%\_titl' ESCAPE '\'
      AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web', 'sys', 'dbo', 'guest', 'INFORMATION_SCHEMA', 'adm')
      AND (@opFilter IS NULL OR RTRIM(t.TABLE_SCHEMA) COLLATE DATABASE_DEFAULT = @opFilter COLLATE DATABASE_DEFAULT);

    INSERT INTO #phys (operator, tabletype, file_name, titl_table)
    SELECT
        CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)),
        5,
        CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128)),
        t.TABLE_SCHEMA + N'.' + t.TABLE_NAME
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE t.TABLE_TYPE = 'BASE TABLE'
      AND t.TABLE_NAME LIKE 'fe\_%\_titl' ESCAPE '\'
      AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web', 'sys', 'dbo', 'guest', 'INFORMATION_SCHEMA', 'adm')
      AND (@opFilter IS NULL OR RTRIM(t.TABLE_SCHEMA) COLLATE DATABASE_DEFAULT = @opFilter COLLATE DATABASE_DEFAULT);

    INSERT INTO #phys (operator, tabletype, file_name, titl_table)
    SELECT
        CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)),
        417,
        CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128)),
        NULL
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE t.TABLE_TYPE = 'BASE TABLE'
      AND t.TABLE_NAME LIKE 'tp\_%\_parm' ESCAPE '\'
      AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web', 'sys', 'dbo', 'guest', 'INFORMATION_SCHEMA', 'adm')
      AND (@opFilter IS NULL OR RTRIM(t.TABLE_SCHEMA) COLLATE DATABASE_DEFAULT = @opFilter COLLATE DATABASE_DEFAULT);

    /* ---- 1) Catalog orphans: row with no physical table ---- */
    IF OBJECT_ID('tempdb..#orphans') IS NOT NULL DROP TABLE #orphans;
    SELECT
        RTRIM(u.operator) AS operator,
        u.tabletype,
        RTRIM(u.file_name) AS file_name
    INTO #orphans
    FROM web.user_tables u
    WHERE u.tabletype IN (0, 5, 417)
      AND (@opFilter IS NULL OR RTRIM(u.operator) COLLATE DATABASE_DEFAULT = @opFilter COLLATE DATABASE_DEFAULT)
      AND NOT EXISTS (
          SELECT 1
          FROM #phys p
          WHERE p.operator = RTRIM(u.operator) COLLATE DATABASE_DEFAULT
            AND p.tabletype = u.tabletype
            AND p.file_name = RTRIM(u.file_name) COLLATE DATABASE_DEFAULT
      );

    INSERT INTO web.user_tables_reconcile_log (run_id, action, operator, tabletype, file_name, detail)
    SELECT @run_id, 'DELETE_ORPHAN', operator, tabletype, file_name, N'no physical table'
    FROM #orphans;

    SET @del = @@ROWCOUNT;

    IF @DryRun = 0 AND @del > 0
    BEGIN
        DELETE u
        FROM web.user_tables u
        INNER JOIN #orphans o
            ON RTRIM(u.operator) COLLATE DATABASE_DEFAULT = o.operator
           AND u.tabletype = o.tabletype
           AND RTRIM(u.file_name) COLLATE DATABASE_DEFAULT = o.file_name;
    END

    /* ---- 2) Missing catalog: physical with no catalog row ---- */
    IF OBJECT_ID('tempdb..#missing') IS NOT NULL DROP TABLE #missing;
    SELECT
        p.operator,
        p.tabletype,
        p.file_name,
        p.titl_table
    INTO #missing
    FROM #phys p
    WHERE NOT EXISTS (
        SELECT 1
        FROM web.user_tables u
        WHERE RTRIM(u.operator) COLLATE DATABASE_DEFAULT = p.operator
          AND u.tabletype = p.tabletype
          AND RTRIM(u.file_name) COLLATE DATABASE_DEFAULT = p.file_name
    );

    /* Default owner from account_details when available */
    IF OBJECT_ID('tempdb..#owner') IS NOT NULL DROP TABLE #owner;
    SELECT
        RTRIM(a.ultrixid) AS operator,
        CAST(MAX(RTRIM(a.micsid)) AS VARCHAR(32)) AS micsid
    INTO #owner
    FROM adm.account_details a
    WHERE (@opFilter IS NULL OR RTRIM(a.ultrixid) COLLATE DATABASE_DEFAULT = @opFilter COLLATE DATABASE_DEFAULT)
    GROUP BY RTRIM(a.ultrixid);

    INSERT INTO web.user_tables_reconcile_log (run_id, action, operator, tabletype, file_name, detail)
    SELECT
        @run_id,
        'INSERT_MISSING',
        m.operator,
        m.tabletype,
        m.file_name,
        N'physical table without catalog row'
    FROM #missing m;

    SET @ins = @@ROWCOUNT;

    IF @DryRun = 0 AND @ins > 0
    BEGIN
        /* Insert with N; validstat sync step below will fix TS/ES from titl when possible */
        INSERT INTO web.user_tables (
            operator, tabletype, file_name, micsid, project_code, validstat, create_date
        )
        SELECT
            LEFT(m.operator, 8),
            m.tabletype,
            m.file_name,
            LEFT(COALESCE(o.micsid, m.operator), 32),
            LEFT(COALESCE(o.micsid, m.operator) + '_0', 10),
            'N',
            GETDATE()
        FROM #missing m
        LEFT JOIN #owner o ON o.operator COLLATE DATABASE_DEFAULT = m.operator;
    END

    /* ---- 3) Sync validstat from titl.validated for TS/ES that exist in both ---- */
    IF @SyncValidstat = 1
    BEGIN
        IF OBJECT_ID('tempdb..#vsync') IS NOT NULL DROP TABLE #vsync;
        CREATE TABLE #vsync (
            operator   VARCHAR(8)  COLLATE DATABASE_DEFAULT NOT NULL,
            tabletype  INT         NOT NULL,
            file_name  VARCHAR(128) COLLATE DATABASE_DEFAULT NOT NULL,
            old_stat   CHAR(1)     NULL,
            new_stat   CHAR(1)     NOT NULL
        );

        DECLARE @vop VARCHAR(8), @vtt INT, @vfn VARCHAR(128), @vtab NVARCHAR(300);
        DECLARE @vsql NVARCHAR(MAX), @vnew CHAR(1), @vold CHAR(1);

        DECLARE vc CURSOR LOCAL FAST_FORWARD FOR
            SELECT p.operator, p.tabletype, p.file_name, p.titl_table
            FROM #phys p
            WHERE p.tabletype IN (0, 5)
              AND p.titl_table IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM web.user_tables u
                  WHERE RTRIM(u.operator) COLLATE DATABASE_DEFAULT = p.operator
                    AND u.tabletype = p.tabletype
                    AND RTRIM(u.file_name) COLLATE DATABASE_DEFAULT = p.file_name
              );

        OPEN vc;
        FETCH NEXT FROM vc INTO @vop, @vtt, @vfn, @vtab;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @vnew = NULL;
            SET @vsql = N'SELECT TOP (1) @out = LEFT(RTRIM(validated), 1) FROM ' + @vtab;
            BEGIN TRY
                EXEC sp_executesql @vsql, N'@out CHAR(1) OUTPUT', @out = @vnew OUTPUT;
            END TRY
            BEGIN CATCH
                SET @vnew = NULL;
            END CATCH

            IF @vnew IS NOT NULL AND @vnew NOT IN ('', ' ')
            BEGIN
                SELECT @vold = LEFT(RTRIM(u.validstat), 1)
                FROM web.user_tables u
                WHERE RTRIM(u.operator) COLLATE DATABASE_DEFAULT = @vop COLLATE DATABASE_DEFAULT
                  AND u.tabletype = @vtt
                  AND RTRIM(u.file_name) COLLATE DATABASE_DEFAULT = @vfn COLLATE DATABASE_DEFAULT;

                IF @vold IS NULL OR @vold <> @vnew
                BEGIN
                    INSERT INTO #vsync (operator, tabletype, file_name, old_stat, new_stat)
                    VALUES (@vop, @vtt, @vfn, @vold, @vnew);
                END
            END

            FETCH NEXT FROM vc INTO @vop, @vtt, @vfn, @vtab;
        END
        CLOSE vc;
        DEALLOCATE vc;

        INSERT INTO web.user_tables_reconcile_log (run_id, action, operator, tabletype, file_name, detail)
        SELECT
            @run_id,
            'UPDATE_VALIDSTAT',
            operator,
            tabletype,
            file_name,
            N'from ' + ISNULL(old_stat, '?') + N' to ' + new_stat
        FROM #vsync;

        SET @upd = @@ROWCOUNT;

        IF @DryRun = 0 AND @upd > 0
        BEGIN
            UPDATE u
            SET validstat = v.new_stat
            FROM web.user_tables u
            INNER JOIN #vsync v
                ON RTRIM(u.operator) COLLATE DATABASE_DEFAULT = v.operator
               AND u.tabletype = v.tabletype
               AND RTRIM(u.file_name) COLLATE DATABASE_DEFAULT = v.file_name;
        END
    END

    UPDATE web.user_tables_reconcile_run
    SET finished_at = SYSUTCDATETIME(),
        deleted_orphans = @del,
        inserted_missing = @ins,
        updated_validstat = @upd,
        notes = CASE WHEN @DryRun = 1 THEN N'Dry run — no catalog changes applied' ELSE N'Applied' END
    WHERE run_id = @run_id;

    /* Summary result set for callers / Agent history */
    SELECT
        @run_id AS run_id,
        @mode AS mode,
        @opFilter AS operator_filter,
        @del AS deleted_orphans,
        @ins AS inserted_missing,
        @upd AS updated_validstat;
END
GO
