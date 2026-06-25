/*
  TSIP run archive — Phase 1 Layer 3 (report file line cache).
*/
SET NOCOUNT ON;

IF OBJECT_ID(N'web.tsip_run_report_line', N'U') IS NULL
BEGIN
    CREATE TABLE web.tsip_run_report_line (
        line_id      BIGINT        IDENTITY(1,1) NOT NULL,
        run_id       BIGINT        NOT NULL,
        report_type  VARCHAR(32)   NOT NULL,
        line_no      INT           NOT NULL,
        line_text    VARCHAR(MAX)  NOT NULL,
        CONSTRAINT PK_tsip_run_report_line PRIMARY KEY CLUSTERED (line_id),
        CONSTRAINT FK_tsip_run_report_line_run FOREIGN KEY (run_id)
            REFERENCES web.tsip_run (run_id) ON DELETE CASCADE
    );

    CREATE UNIQUE INDEX UX_tsip_run_report_line_run_type_line
        ON web.tsip_run_report_line (run_id, report_type, line_no);
END;
