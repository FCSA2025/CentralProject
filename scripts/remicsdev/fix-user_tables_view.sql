-- remicsdev: repair web.user_tables_view (was corrupted: WHERE operator = d)
-- UseDbAuth: app pool cannot use USER-scoped filter; apps pass operator explicitly.
-- AD sites may use the filtered variant in the comment block below instead.

USE remicsdev;
GO

IF OBJECT_ID(N'web.user_tables_view', N'V') IS NOT NULL
    DROP VIEW web.user_tables_view;
GO

CREATE VIEW web.user_tables_view
(
    operator,
    tabletype,
    file_name,
    micsid,
    project_code,
    validstat,
    create_date
)
AS
    SELECT operator,
           tabletype,
           file_name,
           micsid,
           project_code,
           validstat,
           create_date
    FROM web.user_tables;
GO

-- AD / USER-scoped variant (production pattern — do not use on UseDbAuth-only sites):
-- CREATE VIEW web.user_tables_view AS
--     SELECT operator, tabletype, file_name, micsid, project_code, validstat, create_date
--     FROM web.user_tables
--     WHERE operator = RTRIM(dbo.user_schema2022(USER));
