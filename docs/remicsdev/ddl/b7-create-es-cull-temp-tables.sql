-- B7 fix: provision missing ES Data Search cull temp tables.
-- Template matches remicsdev healthy schemas (e.g. rctl / xci).
-- Safe to re-run (IF NOT EXISTS).

SET NOCOUNT ON;

DECLARE @schemas TABLE (name sysname PRIMARY KEY);
INSERT INTO @schemas(name) VALUES
    ('aliant'),('bchy'),('bell'),('bmce'),('bragg'),
    ('dnd'),('tbay'),('tels'),('terago');

DECLARE @sch sysname;
DECLARE @sql nvarchar(max);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM @schemas
    WHERE EXISTS (SELECT 1 FROM sys.schemas s WHERE s.name = name);
OPEN c;
FETCH NEXT FROM c INTO @sch;
WHILE @@FETCH_STATUS = 0
BEGIN
    -- cull_temp1_es
    IF OBJECT_ID(QUOTENAME(@sch) + '.cull_temp1_es', 'U') IS NULL
    BEGIN
        SET @sql = N'CREATE TABLE ' + QUOTENAME(@sch) + N'.cull_temp1_es (
    sessionid char(16) NULL,
    cull_type char(4) NULL,
    location  char(10) NULL,
    call1     char(9) NULL,
    chid      char(4) NULL,
    source    int NULL
);';
        EXEC sp_executesql @sql;
        PRINT 'CREATED ' + @sch + '.cull_temp1_es';
    END
    ELSE PRINT 'EXISTS  ' + @sch + '.cull_temp1_es';

    -- cull_temp2_es
    IF OBJECT_ID(QUOTENAME(@sch) + '.cull_temp2_es', 'U') IS NULL
    BEGIN
        SET @sql = N'CREATE TABLE ' + QUOTENAME(@sch) + N'.cull_temp2_es (
    sessionid char(16) NULL,
    cull_type char(4) NULL,
    location  char(10) NULL,
    call1     char(9) NULL,
    chid      char(4) NULL,
    source    int NULL
);';
        EXEC sp_executesql @sql;
        PRINT 'CREATED ' + @sch + '.cull_temp2_es';
    END
    ELSE PRINT 'EXISTS  ' + @sch + '.cull_temp2_es';

    -- cull_temp3_es
    IF OBJECT_ID(QUOTENAME(@sch) + '.cull_temp3_es', 'U') IS NULL
    BEGIN
        SET @sql = N'CREATE TABLE ' + QUOTENAME(@sch) + N'.cull_temp3_es (
    sessionid char(16) NULL,
    cull_type char(4) NULL,
    location  char(10) NULL,
    call1     char(9) NULL,
    chid      char(4) NULL,
    source    int NULL
);';
        EXEC sp_executesql @sql;
        PRINT 'CREATED ' + @sch + '.cull_temp3_es';
    END
    ELSE PRINT 'EXISTS  ' + @sch + '.cull_temp3_es';

    FETCH NEXT FROM c INTO @sch;
END
CLOSE c;
DEALLOCATE c;

-- Verify: no B7 account schemas should still lack cull_temp3_es
SELECT RTRIM(a.ultrixid) AS still_missing
FROM (SELECT DISTINCT ultrixid FROM adm.account_details) a
WHERE EXISTS (SELECT 1 FROM sys.schemas s WHERE s.name = RTRIM(a.ultrixid))
AND NOT EXISTS (
  SELECT 1 FROM INFORMATION_SCHEMA.TABLES t
  WHERE t.TABLE_SCHEMA = RTRIM(a.ultrixid) AND t.TABLE_NAME = 'cull_temp3_es'
)
ORDER BY 1;
