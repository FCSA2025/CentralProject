-- remicsdev: nightly Gate F regression checks + optional FCSA team alert
-- See docs/remicsdev/gate-f-regression.md

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE web.SendGateFAlert
    @Subject NVARCHAR(200),
    @Body    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @profile_name  NVARCHAR(128) = N'AlertMailProfile';
    DECLARE @from_address  NVARCHAR(50)  = N'mics@fcsa.ca';
    DECLARE @recipients    NVARCHAR(500) = N'jscott@fcsa.ca;sbekhsat@fcsa.ca;plin@fcsa.ca;alejandro.moreno@sympatico.ca;ablesonb@venn.ca';

    BEGIN TRY
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = @profile_name,
            @from_address = @from_address,
            @recipients   = @recipients,
            @subject      = @Subject,
            @body         = @Body,
            @body_format  = 'TEXT';
    END TRY
    BEGIN CATCH
        PRINT 'SendGateFAlert failed: ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE web.RunGateFRegression
    @SendEmail       BIT = 1,
    @MaxStaleHours   INT = 36,
    @FailJobOnIssues BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET QUOTED_IDENTIFIER ON;
    SET ANSI_NULLS ON;

    DECLARE @run_id INT;
    DECLARE @cross_company INT = 0;
    DECLARE @catalog_orphans INT = 0;
    DECLARE @catalog_missing INT = 0;
    DECLARE @reconcile_stale BIT = 0;
    DECLARE @last_reconcile DATETIME2(3);
    DECLARE @issue_count INT = 0;
    DECLARE @body NVARCHAR(MAX) = N'';
    DECLARE @subject NVARCHAR(200) = N'RemIcs Gate F regression — issues detected (remicsdev)';

    INSERT INTO web.gate_f_regression_run (ok) VALUES (1);
    SET @run_id = SCOPE_IDENTITY();

    /* --- 1. Cross-company TSIP parm runs (proname / PDF envname) --- */
    IF OBJECT_ID('tempdb..#cc_hits') IS NOT NULL DROP TABLE #cc_hits;
    CREATE TABLE #cc_hits (
        parm_schema SYSNAME NOT NULL,
        parm_name   NVARCHAR(128) NOT NULL,
        reason      NVARCHAR(40) NOT NULL
    );

    DECLARE @schema SYSNAME, @tname SYSNAME, @parm NVARCHAR(128), @sql NVARCHAR(MAX);
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT TABLE_SCHEMA, TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_TYPE = 'BASE TABLE'
          AND TABLE_NAME LIKE 'tp\_%\_parm' ESCAPE '\'
          AND TABLE_SCHEMA NOT IN ('web', 'sys', 'INFORMATION_SCHEMA', 'dbo', 'guest');

    OPEN c;
    FETCH NEXT FROM c INTO @schema, @tname;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @parm = REPLACE(REPLACE(@tname, 'tp_', ''), '_parm', '');

        IF EXISTS (
            SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @tname AND COLUMN_NAME = 'proname'
        )
        BEGIN
            SET @sql = N'
INSERT INTO #cc_hits(parm_schema, parm_name, reason)
SELECT DISTINCT N''' + @schema + N''', N''' + REPLACE(@parm, '''', '''''') + N''', N''cross-proname''
FROM [' + @schema + N'].[' + @tname + N'] p
WHERE NULLIF(RTRIM(ISNULL(p.proname, '''')), '''') IS NOT NULL
  AND LEFT(RTRIM(ISNULL(p.protype, '''')), 1) IN (''T'', ''E'')
  AND EXISTS (
    SELECT 1 FROM web.user_tables_view v
    WHERE RTRIM(v.file_name) = RTRIM(p.proname)
      AND (
        (LEFT(RTRIM(ISNULL(p.protype, '''')), 1) = ''T'' AND v.tabletype = 0)
        OR (LEFT(RTRIM(ISNULL(p.protype, '''')), 1) = ''E'' AND v.tabletype = 5)
      )
  )
  AND NOT EXISTS (
    SELECT 1 FROM web.user_tables_view v
    WHERE RTRIM(v.file_name) = RTRIM(p.proname)
      AND RTRIM(v.operator) = N''' + @schema + N'''
      AND (
        (LEFT(RTRIM(ISNULL(p.protype, '''')), 1) = ''T'' AND v.tabletype = 0)
        OR (LEFT(RTRIM(ISNULL(p.protype, '''')), 1) = ''E'' AND v.tabletype = 5)
      )
  );';
            BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH;
        END

        IF EXISTS (
            SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @tname AND COLUMN_NAME = 'envname'
        )
        BEGIN
            SET @sql = N'
INSERT INTO #cc_hits(parm_schema, parm_name, reason)
SELECT DISTINCT N''' + @schema + N''', N''' + REPLACE(@parm, '''', '''''') + N''', N''cross-envname''
FROM [' + @schema + N'].[' + @tname + N'] p
WHERE NULLIF(RTRIM(ISNULL(p.envname, '''')), '''') IS NOT NULL
  AND UPPER(RTRIM(ISNULL(p.envtype, ''''))) LIKE ''PDF_%''
  AND EXISTS (
    SELECT 1 FROM web.user_tables_view v
    WHERE RTRIM(v.file_name) = RTRIM(p.envname)
      AND (
        (UPPER(RTRIM(ISNULL(p.envtype, ''''))) LIKE ''%TS%'' AND v.tabletype = 0)
        OR (UPPER(RTRIM(ISNULL(p.envtype, ''''))) LIKE ''%ES%'' AND v.tabletype = 5)
      )
  )
  AND NOT EXISTS (
    SELECT 1 FROM web.user_tables_view v
    WHERE RTRIM(v.file_name) = RTRIM(p.envname)
      AND RTRIM(v.operator) = N''' + @schema + N'''
      AND (
        (UPPER(RTRIM(ISNULL(p.envtype, ''''))) LIKE ''%TS%'' AND v.tabletype = 0)
        OR (UPPER(RTRIM(ISNULL(p.envtype, ''''))) LIKE ''%ES%'' AND v.tabletype = 5)
      )
  );';
            BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH;
        END

        FETCH NEXT FROM c INTO @schema, @tname;
    END
    CLOSE c;
    DEALLOCATE c;

    SELECT @cross_company = COUNT(*) FROM (
        SELECT DISTINCT parm_schema, parm_name FROM #cc_hits
    ) d;

    INSERT INTO web.gate_f_regression_finding (run_id, check_name, detail)
    SELECT TOP (50) @run_id, 'cross_company_parm',
        RTRIM(parm_schema) + '.' + RTRIM(parm_name) + ' (' + reason + ')'
    FROM #cc_hits
    ORDER BY parm_schema, parm_name, reason;

    /* --- 2. Catalog drift (types 0/5/417) --- */
    IF OBJECT_ID('tempdb..#phys') IS NOT NULL DROP TABLE #phys;
    CREATE TABLE #phys (
        operator   VARCHAR(8)  COLLATE DATABASE_DEFAULT NOT NULL,
        tabletype  INT         NOT NULL,
        file_name  VARCHAR(128) COLLATE DATABASE_DEFAULT NOT NULL,
        PRIMARY KEY (operator, tabletype, file_name)
    );

    INSERT INTO #phys (operator, tabletype, file_name)
    SELECT CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)), 0,
           CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128))
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE t.TABLE_TYPE = 'BASE TABLE' AND t.TABLE_NAME LIKE 'ft\_%\_titl' ESCAPE '\'
      AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web','sys','dbo','guest','INFORMATION_SCHEMA','adm');

    INSERT INTO #phys (operator, tabletype, file_name)
    SELECT CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)), 5,
           CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128))
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE t.TABLE_TYPE = 'BASE TABLE' AND t.TABLE_NAME LIKE 'fe\_%\_titl' ESCAPE '\'
      AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web','sys','dbo','guest','INFORMATION_SCHEMA','adm');

    INSERT INTO #phys (operator, tabletype, file_name)
    SELECT CAST(RTRIM(t.TABLE_SCHEMA) AS VARCHAR(8)), 417,
           CAST(SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8) AS VARCHAR(128))
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE t.TABLE_TYPE = 'BASE TABLE' AND t.TABLE_NAME LIKE 'tp\_%\_parm' ESCAPE '\'
      AND t.TABLE_SCHEMA COLLATE DATABASE_DEFAULT NOT IN ('web','sys','dbo','guest','INFORMATION_SCHEMA','adm');

    SELECT @catalog_orphans = COUNT(*)
    FROM web.user_tables u
    WHERE u.tabletype IN (0, 5, 417)
      AND NOT EXISTS (
          SELECT 1 FROM #phys p
          WHERE p.operator = RTRIM(u.operator) COLLATE DATABASE_DEFAULT
            AND p.tabletype = u.tabletype
            AND p.file_name = RTRIM(u.file_name) COLLATE DATABASE_DEFAULT);

    SELECT @catalog_missing = COUNT(*)
    FROM #phys p
    WHERE NOT EXISTS (
        SELECT 1 FROM web.user_tables u
        WHERE RTRIM(u.operator) COLLATE DATABASE_DEFAULT = p.operator
          AND u.tabletype = p.tabletype
          AND RTRIM(u.file_name) COLLATE DATABASE_DEFAULT = p.file_name);

    IF @catalog_orphans > 0
        INSERT INTO web.gate_f_regression_finding (run_id, check_name, detail)
        VALUES (@run_id, 'catalog_drift', CAST(@catalog_orphans AS NVARCHAR(20)) + ' catalog orphan row(s) in web.user_tables');

    IF @catalog_missing > 0
        INSERT INTO web.gate_f_regression_finding (run_id, check_name, detail)
        VALUES (@run_id, 'catalog_drift', CAST(@catalog_missing AS NVARCHAR(20)) + ' physical table(s) missing from web.user_tables');

    /* --- 3. Nightly User Tables Reconcile job freshness --- */
    SELECT TOP (1) @last_reconcile = finished_at
    FROM web.user_tables_reconcile_run
    WHERE mode = 'LIVE' AND finished_at IS NOT NULL
    ORDER BY run_id DESC;

    IF @last_reconcile IS NULL OR @last_reconcile < DATEADD(HOUR, -@MaxStaleHours, SYSUTCDATETIME())
    BEGIN
        SET @reconcile_stale = 1;
        INSERT INTO web.gate_f_regression_finding (run_id, check_name, detail)
        VALUES (@run_id, 'reconcile_stale',
            'No successful LIVE reconcile in the last ' + CAST(@MaxStaleHours AS VARCHAR(10)) + ' hours' +
            ISNULL(' (last: ' + CONVERT(VARCHAR(30), @last_reconcile, 120) + ' UTC)', ' (never)'));
    END

    SELECT @issue_count = COUNT(*) FROM web.gate_f_regression_finding WHERE run_id = @run_id;

    IF @issue_count > 0
    BEGIN
        UPDATE web.gate_f_regression_run
        SET finished_at = SYSUTCDATETIME(),
            ok = 0,
            cross_company_count = @cross_company,
            catalog_orphans = @catalog_orphans,
            catalog_missing = @catalog_missing,
            reconcile_stale = @reconcile_stale,
            notes = CAST(@issue_count AS NVARCHAR(20)) + ' finding(s)'
        WHERE run_id = @run_id;

        SET @body =
            N'RemIcsReWrite Gate F nightly regression found issues on remicsdev.' + CHAR(13) + CHAR(10) +
            N'Run id: ' + CAST(@run_id AS NVARCHAR(20)) + CHAR(13) + CHAR(10) +
            N'Cross-company TSIP parm files: ' + CAST(@cross_company AS NVARCHAR(20)) + CHAR(13) + CHAR(10) +
            N'Catalog orphans: ' + CAST(@catalog_orphans AS NVARCHAR(20)) + CHAR(13) + CHAR(10) +
            N'Catalog missing: ' + CAST(@catalog_missing AS NVARCHAR(20)) + CHAR(13) + CHAR(10) +
            N'Reconcile stale: ' + CASE WHEN @reconcile_stale = 1 THEN 'YES' ELSE 'no' END + CHAR(13) + CHAR(10) +
            CHAR(13) + CHAR(10) + N'Details:' + CHAR(13) + CHAR(10);

        SELECT @body = @body + N' - ' + check_name + N': ' + detail + CHAR(13) + CHAR(10)
        FROM web.gate_f_regression_finding
        WHERE run_id = @run_id
        ORDER BY finding_id;

        SET @body = @body + CHAR(13) + CHAR(10) +
            N'Audit: SELECT * FROM web.gate_f_regression_run WHERE run_id = ' + CAST(@run_id AS NVARCHAR(20)) + ';' + CHAR(13) + CHAR(10) +
            N'       SELECT * FROM web.gate_f_regression_finding WHERE run_id = ' + CAST(@run_id AS NVARCHAR(20)) + ';' + CHAR(13) + CHAR(10) +
            N'HTTP isolation (per-schema TSIP validate) runs in job step 2 / Invoke-GateFRegressionTest.ps1';

        IF @SendEmail = 1
        BEGIN
            EXEC web.SendGateFAlert @Subject = @subject, @Body = @body;
            UPDATE web.gate_f_regression_run SET email_sent = 1 WHERE run_id = @run_id;
        END

        SELECT run_id = @run_id, ok = CAST(0 AS BIT), cross_company_count = @cross_company,
               catalog_orphans = @catalog_orphans, catalog_missing = @catalog_missing,
               reconcile_stale = @reconcile_stale, issue_count = @issue_count;

        IF @FailJobOnIssues = 1
            THROW 50001, 'Gate F regression: one or more checks failed. See web.gate_f_regression_finding.', 1;

        RETURN;
    END

    UPDATE web.gate_f_regression_run
    SET finished_at = SYSUTCDATETIME(),
        ok = 1,
        cross_company_count = @cross_company,
        catalog_orphans = @catalog_orphans,
        catalog_missing = @catalog_missing,
        reconcile_stale = 0,
        notes = 'All SQL checks passed'
    WHERE run_id = @run_id;

    SELECT run_id = @run_id, ok = CAST(1 AS BIT), cross_company_count = @cross_company,
           catalog_orphans = @catalog_orphans, catalog_missing = @catalog_missing,
           reconcile_stale = CAST(0 AS BIT), issue_count = 0;
END
GO
