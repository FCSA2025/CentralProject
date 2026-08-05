-- remicsdev: register TS PDFs in web.user_tables when ft_{name}_* tables exist
-- but no tabletype=0 catalog row (tsipValidateAll reports "has been deleted").
-- After insert, validstat='N' — run Validate on each TS file in MICS before batch TSIP.
--
-- Verified 2026-07-30: ecomm2601, ecomm2602, ecomm2602a had ft_* tables but no catalog row.

USE RemicsDev;
GO

DECLARE @schema   char(4)  = 'rctl';
DECLARE @micsid   char(10) = 'rctl1';
DECLARE @proj     char(10) = 'rctl1_0';
DECLARE @base     varchar(16);
DECLARE @inserted int = 0;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8)
    FROM INFORMATION_SCHEMA.TABLES t
    WHERE t.TABLE_SCHEMA = @schema
      AND t.TABLE_NAME LIKE 'ft[_]%[_]ante'
      AND NOT EXISTS (
          SELECT 1
          FROM web.user_tables ut
          WHERE ut.operator = @schema
            AND ut.tabletype = 0
            AND ut.file_name = SUBSTRING(t.TABLE_NAME, 4, LEN(t.TABLE_NAME) - 8)
      );

OPEN c;
FETCH NEXT FROM c INTO @base;

WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT INTO web.user_tables (operator, tabletype, file_name, micsid, project_code, validstat, create_date)
    VALUES (@schema, 0, @base, @micsid, @proj, 'N', CURRENT_TIMESTAMP);

    SET @inserted += 1;
    PRINT 'Registered: ' + @base;

    FETCH NEXT FROM c INTO @base;
END

CLOSE c;
DEALLOCATE c;

PRINT 'Inserted ' + CAST(@inserted AS varchar(10)) + ' catalog row(s). Validate each TS file in MICS before batch TSIP.';
