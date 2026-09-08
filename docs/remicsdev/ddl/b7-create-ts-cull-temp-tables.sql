-- Provision missing TS Data Search cull temp tables (companion to B7 ES culls).
-- Template matches remicsdev healthy schemas (e.g. rctl / xci).
-- Safe to re-run (IF NOT EXISTS).

SET NOCOUNT ON;

DECLARE @schemas TABLE (name sysname PRIMARY KEY);
INSERT INTO @schemas(name) VALUES
    ('aliant'),('bchy'),('bell'),('bmce'),('bragg'),
    ('dnd'),('tbay'),('tels'),('terago');

DECLARE @sch sysname;
DECLARE @sql nvarchar(max);
DECLARE @ddl nvarchar(max) = N'(
    sessionid varchar(16) NULL,
    cull_type char(4) NULL,
    call1     char(9) NULL,
    call2     char(9) NULL,
    bndcde    char(4) NULL,
    chid      char(4) NULL,
    anum      int NULL,
    source    int NULL
)';

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM @schemas
    WHERE EXISTS (SELECT 1 FROM sys.schemas s WHERE s.name = name);
OPEN c;
FETCH NEXT FROM c INTO @sch;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(QUOTENAME(@sch) + '.cull_temp1', 'U') IS NULL
    BEGIN
        SET @sql = N'CREATE TABLE ' + QUOTENAME(@sch) + N'.cull_temp1 ' + @ddl + N';';
        EXEC sp_executesql @sql;
        PRINT 'CREATED ' + @sch + '.cull_temp1';
    END
    ELSE PRINT 'EXISTS  ' + @sch + '.cull_temp1';

    IF OBJECT_ID(QUOTENAME(@sch) + '.cull_temp2', 'U') IS NULL
    BEGIN
        SET @sql = N'CREATE TABLE ' + QUOTENAME(@sch) + N'.cull_temp2 ' + @ddl + N';';
        EXEC sp_executesql @sql;
        PRINT 'CREATED ' + @sch + '.cull_temp2';
    END
    ELSE PRINT 'EXISTS  ' + @sch + '.cull_temp2';

    IF OBJECT_ID(QUOTENAME(@sch) + '.cull_temp3', 'U') IS NULL
    BEGIN
        SET @sql = N'CREATE TABLE ' + QUOTENAME(@sch) + N'.cull_temp3 ' + @ddl + N';';
        EXEC sp_executesql @sql;
        PRINT 'CREATED ' + @sch + '.cull_temp3';
    END
    ELSE PRINT 'EXISTS  ' + @sch + '.cull_temp3';

    FETCH NEXT FROM c INTO @sch;
END
CLOSE c;
DEALLOCATE c;

-- Verify: B7 schemas should all have TS + ES cull sets
SELECT sch.name AS schema_name,
       CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp1','U') IS NULL THEN 0 ELSE 1 END AS t1,
       CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp2','U') IS NULL THEN 0 ELSE 1 END AS t2,
       CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp3','U') IS NULL THEN 0 ELSE 1 END AS t3,
       CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp1_es','U') IS NULL THEN 0 ELSE 1 END AS e1,
       CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp2_es','U') IS NULL THEN 0 ELSE 1 END AS e2,
       CASE WHEN OBJECT_ID(QUOTENAME(sch.name)+'.cull_temp3_es','U') IS NULL THEN 0 ELSE 1 END AS e3
FROM (VALUES
    ('aliant'),('bchy'),('bell'),('bmce'),('bragg'),
    ('dnd'),('tbay'),('tels'),('terago')
) sch(name)
ORDER BY 1;
