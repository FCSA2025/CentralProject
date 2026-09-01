/* Delete TSIP parm files whose runs point at another company's TS/ES (proname or PDF envname).
   remicsdev cleanup — audit + delete. See gate-f-regression.md / RunGateFRegression.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('tempdb..#targets') IS NOT NULL DROP TABLE #targets;
CREATE TABLE #targets (
  parm_schema sysname NOT NULL,
  parm_name nvarchar(128) NOT NULL,
  reasons nvarchar(200) NOT NULL,
  PRIMARY KEY (parm_schema, parm_name)
);

IF OBJECT_ID('tempdb..#hits') IS NOT NULL DROP TABLE #hits;
CREATE TABLE #hits (parm_schema sysname, parm_name nvarchar(128), reason nvarchar(40));

DECLARE @schema sysname, @tname sysname, @parm nvarchar(128), @sql nvarchar(max);
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
INSERT INTO #hits(parm_schema, parm_name, reason)
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
    BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH
  END

  IF EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = @schema AND TABLE_NAME = @tname AND COLUMN_NAME = 'envname'
  )
  BEGIN
    SET @sql = N'
INSERT INTO #hits(parm_schema, parm_name, reason)
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
    BEGIN TRY EXEC sp_executesql @sql; END TRY BEGIN CATCH END CATCH
  END

  FETCH NEXT FROM c INTO @schema, @tname;
END
CLOSE c;
DEALLOCATE c;

INSERT INTO #targets (parm_schema, parm_name, reasons)
SELECT parm_schema, parm_name,
  CASE
    WHEN MAX(CASE WHEN reason = 'cross-proname' THEN 1 ELSE 0 END) = 1
     AND MAX(CASE WHEN reason = 'cross-envname' THEN 1 ELSE 0 END) = 1
      THEN 'cross-proname,cross-envname'
    WHEN MAX(CASE WHEN reason = 'cross-proname' THEN 1 ELSE 0 END) = 1
      THEN 'cross-proname'
    ELSE 'cross-envname'
  END
FROM #hits
GROUP BY parm_schema, parm_name;

SELECT 'PRE_DELETE' AS phase, parm_schema, parm_name, reasons
FROM #targets
ORDER BY parm_schema, parm_name;

IF OBJECT_ID('tempdb..#results') IS NOT NULL DROP TABLE #results;
CREATE TABLE #results (
  parm_schema sysname,
  parm_name nvarchar(128),
  dropped_table bit,
  catalog_rows_deleted int,
  err nvarchar(4000)
);

DECLARE @name nvarchar(128), @drop nvarchar(max), @cat int, @err nvarchar(4000);
DECLARE d CURSOR LOCAL FAST_FORWARD FOR
SELECT parm_schema, parm_name FROM #targets ORDER BY parm_schema, parm_name;
OPEN d;
FETCH NEXT FROM d INTO @schema, @name;
WHILE @@FETCH_STATUS = 0
BEGIN
  SET @cat = 0;
  SET @err = NULL;
  BEGIN TRY
    BEGIN TRAN;
    SET @drop = N'IF OBJECT_ID(N''' + @schema + N'.tp_' + @name + N'_parm'', ''U'') IS NOT NULL DROP TABLE [' + @schema + N'].[tp_' + @name + N'_parm];';
    EXEC sp_executesql @drop;

    DELETE FROM web.user_tables
    WHERE RTRIM(operator) = @schema
      AND RTRIM(file_name) = @name
      AND tabletype = 417;
    SET @cat = @@ROWCOUNT;

    COMMIT TRAN;
    INSERT INTO #results VALUES (@schema, @name, 1, @cat, NULL);
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    INSERT INTO #results VALUES (@schema, @name, 0, 0, ERROR_MESSAGE());
  END CATCH

  FETCH NEXT FROM d INTO @schema, @name;
END
CLOSE d;
DEALLOCATE d;

SELECT 'RESULT' AS phase, parm_schema, parm_name, dropped_table, catalog_rows_deleted, err
FROM #results
ORDER BY CASE WHEN err IS NULL THEN 0 ELSE 1 END, parm_schema, parm_name;

SELECT
  SUM(CASE WHEN err IS NULL THEN 1 ELSE 0 END) AS deleted_ok,
  SUM(CASE WHEN err IS NOT NULL THEN 1 ELSE 0 END) AS deleted_fail,
  SUM(catalog_rows_deleted) AS catalog_rows_removed
FROM #results;
