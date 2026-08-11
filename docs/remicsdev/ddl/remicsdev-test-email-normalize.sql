-- remicsdev: normalize operator email addresses for end-to-end testing.
-- All mail flows (PCN, DbUpdate, TSIP, auto-processor) should resolve to jscott@fcsa.ca.
-- Rollback: restore from backup export of email columns before running this script.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @testEmail NVARCHAR(500) = N'jscott@fcsa.ca';

UPDATE dbo.t_UserDetails
SET email = @testEmail
WHERE email IS NULL OR RTRIM(email) <> @testEmail;

UPDATE adm.account_details
SET email = @testEmail
WHERE email IS NULL OR RTRIM(email) <> @testEmail;

UPDATE adm.pcn_account_details
SET email = @testEmail
WHERE email IS NULL OR RTRIM(email) <> @testEmail;

SELECT 't_UserDetails' AS src, COUNT(*) AS rows_updated_or_matching
FROM dbo.t_UserDetails WHERE RTRIM(email) = @testEmail
UNION ALL
SELECT 'account_details', COUNT(*)
FROM adm.account_details WHERE RTRIM(email) = @testEmail
UNION ALL
SELECT 'pcn_account_details', COUNT(*)
FROM adm.pcn_account_details WHERE RTRIM(email) = @testEmail;
