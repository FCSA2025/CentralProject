/*
  TSIP run archive — grants for MICS database roles (match web.tsip_queue pattern).
  INSERT + SELECT on archive tables only; no change to existing objects.
*/
SET NOCOUNT ON;

DECLARE @roles TABLE (role_name SYSNAME);
INSERT INTO @roles (role_name) VALUES
    (N'ROLfcsaconsultants'),
    (N'ROLfcsastaff'),
    (N'ROLwebconsultants'),
    (N'ROLwebusers');

DECLARE @tables TABLE (table_name SYSNAME);
INSERT INTO @tables (table_name) VALUES
    (N'tsip_run'),
    (N'tsip_run_parm_ts'),
    (N'tsip_run_parm_es'),
    (N'tsip_arc_ts_site'),
    (N'tsip_arc_ts_ante'),
    (N'tsip_arc_ts_chan'),
    (N'tsip_arc_ts_parm'),
    (N'tsip_arc_te_site'),
    (N'tsip_arc_te_ante'),
    (N'tsip_arc_te_chan'),
    (N'tsip_arc_te_parm'),
    (N'tsip_arc_ts_statsum'),
    (N'tsip_arc_te_statsum'),
    (N'tsip_run_report_line');

DECLARE @role SYSNAME;
DECLARE @tbl SYSNAME;
DECLARE @sql NVARCHAR(4000);

DECLARE role_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT role_name FROM @roles;
OPEN role_cursor;
FETCH NEXT FROM role_cursor INTO @role;
WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE tbl_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT table_name FROM @tables;
    OPEN tbl_cursor;
    FETCH NEXT FROM tbl_cursor INTO @tbl;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF OBJECT_ID(N'web.' + @tbl, N'U') IS NOT NULL
        BEGIN
            SET @sql = N'GRANT INSERT, SELECT ON web.' + QUOTENAME(@tbl) + N' TO ' + QUOTENAME(@role) + N';';
            EXEC sp_executesql @sql;
        END
        FETCH NEXT FROM tbl_cursor INTO @tbl;
    END
    CLOSE tbl_cursor;
    DEALLOCATE tbl_cursor;

    FETCH NEXT FROM role_cursor INTO @role;
END
CLOSE role_cursor;
DEALLOCATE role_cursor;
