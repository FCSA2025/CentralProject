-- SQL Agent job step command: User Tables Reconcile (remicsdev)
-- Nightly + callable on demand after KillTable/CopyTable failures.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

EXEC web.ReconcileUserTables
    @Operator = NULL,
    @DryRun = 0,
    @SyncValidstat = 1;
