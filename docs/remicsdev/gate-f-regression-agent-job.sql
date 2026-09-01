-- SQL Agent job step: RemIcs Gate F regression (remicsdev)
-- Nightly after User Tables Reconcile (02:30). Step 1 = SQL checks + email on failure.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

EXEC web.RunGateFRegression
    @SendEmail = 1,
    @MaxStaleHours = 36,
    @FailJobOnIssues = 1;
