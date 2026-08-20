-- Restore remicsdev emails for FCSA staff only (from ReMicsProd).
-- Operator emails stay on jscott@fcsa.ca so test PCN/DbUpdate does not hit customers.

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID('tempdb..#fcsa_staff_email') IS NOT NULL DROP TABLE #fcsa_staff_email;
CREATE TABLE #fcsa_staff_email (
    micsid VARCHAR(10) NOT NULL PRIMARY KEY,
    email  NVARCHAR(500) NOT NULL
);

INSERT INTO #fcsa_staff_email (micsid, email)
SELECT RTRIM(micsId), RTRIM(email)
FROM ReMicsProd.dbo.t_UserDetails
WHERE RTRIM(micsId) COLLATE Latin1_General_CI_AI IN (
    'fcsa1', 'fcsa2', 'fwmda', 'fwoad', 'fwrse', 'frse1',
    'hulme1', 'venn1', 'venn2', 'compa1', 'compa2', 'compa4',
    'comph1', 'import1', 'import2', 'TekSav1'
)
  AND NULLIF(RTRIM(email), '') IS NOT NULL;

UPDATE u
SET email = s.email
FROM dbo.t_UserDetails u
JOIN #fcsa_staff_email s ON RTRIM(u.micsId) COLLATE Latin1_General_CI_AI = s.micsid COLLATE Latin1_General_CI_AI;

UPDATE a
SET email = s.email
FROM adm.account_details a
JOIN #fcsa_staff_email s ON RTRIM(a.micsid) COLLATE Latin1_General_CI_AI = s.micsid COLLATE Latin1_General_CI_AI;

UPDATE p
SET email = s.email
FROM adm.pcn_account_details p
JOIN #fcsa_staff_email s ON RTRIM(p.micsid) COLLATE Latin1_General_CI_AI = s.micsid COLLATE Latin1_General_CI_AI;

SELECT s.micsid, s.email,
    (SELECT RTRIM(email) FROM dbo.t_UserDetails u WHERE RTRIM(u.micsId) COLLATE Latin1_General_CI_AI = s.micsid) AS user_details,
    (SELECT RTRIM(email) FROM adm.account_details a WHERE RTRIM(a.micsid) COLLATE Latin1_General_CI_AI = s.micsid) AS account_details
FROM #fcsa_staff_email s
ORDER BY s.micsid;
