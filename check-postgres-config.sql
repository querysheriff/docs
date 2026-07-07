WITH s AS (
    SELECT
        (SELECT setting FROM pg_settings WHERE name = 'server_version_num')            AS server_version_num,
        (SELECT setting FROM pg_settings WHERE name = 'shared_preload_libraries')      AS shared_preload_libraries,
        (SELECT setting FROM pg_settings WHERE name = 'compute_query_id')              AS compute_query_id,
        (SELECT setting FROM pg_settings WHERE name = 'track_io_timing')               AS track_io_timing,
        (SELECT setting FROM pg_settings WHERE name = 'pg_stat_statements.track')      AS pgss_track,
        (SELECT setting FROM pg_settings WHERE name = 'pg_stat_statements.max')        AS pgss_max,
        (SELECT setting FROM pg_settings WHERE name = 'logging_collector')             AS logging_collector,
        (SELECT setting FROM pg_settings WHERE name = 'log_destination')               AS log_destination,
        (SELECT setting FROM pg_settings WHERE name = 'log_directory')                 AS log_directory,
        (SELECT setting FROM pg_settings WHERE name = 'log_filename')                  AS log_filename,
        (SELECT setting FROM pg_settings WHERE name = 'log_rotation_age')              AS log_rotation_age,
        (SELECT setting FROM pg_settings WHERE name = 'log_rotation_size')             AS log_rotation_size,
        (SELECT setting FROM pg_settings WHERE name = 'log_timezone')                  AS log_timezone,
        (SELECT setting FROM pg_settings WHERE name = 'log_min_duration_statement')    AS log_min_duration_statement,
        (SELECT setting FROM pg_settings WHERE name = 'log_lock_waits')                AS log_lock_waits,
        (SELECT setting FROM pg_settings WHERE name = 'log_file_mode')                 AS log_file_mode,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.log_format')       AS ae_log_format,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.log_min_duration') AS ae_log_min_duration,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.log_analyze')      AS ae_log_analyze,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.log_buffers')      AS ae_log_buffers,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.log_timing')       AS ae_log_timing,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.log_triggers')     AS ae_log_triggers,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.log_verbose')      AS ae_log_verbose,
        (SELECT setting FROM pg_settings WHERE name = 'auto_explain.sample_rate')      AS ae_sample_rate,
        EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')       AS pgss_installed,
        EXISTS (
            SELECT 1
            FROM pg_auth_members m
            JOIN pg_roles grp ON grp.oid = m.roleid
            JOIN pg_roles mem ON mem.oid = m.member
            WHERE grp.rolname = 'pg_monitor' AND mem.rolname = 'pgdozor_collector'
        ) AS collector_has_pg_monitor
)
SELECT parameter, current_value AS "current", required AS expected, status
FROM (
    SELECT 'required' AS severity, 'server' AS category, 'server_version_num' AS parameter,
        COALESCE(server_version_num, '(unset)') AS current_value,
        '150000..190000' AS required,
        CASE WHEN server_version_num::int BETWEEN 150000 AND 190000 THEN 'OK' ELSE 'FAIL' END AS status
    FROM s
    UNION ALL
    SELECT 'recommended', 'role', 'pgdozor_collector -> pg_monitor',
        CASE WHEN collector_has_pg_monitor THEN 'granted' ELSE 'missing' END,
        'granted',
        CASE WHEN collector_has_pg_monitor THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'pg_stat_statements', 'shared_preload_libraries: pg_stat_statements',
        COALESCE(shared_preload_libraries, '(unset)'),
        'contains pg_stat_statements',
        CASE WHEN shared_preload_libraries LIKE '%pg_stat_statements%' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'pg_stat_statements', 'extension installed',
        CASE WHEN pgss_installed THEN 'installed' ELSE 'not installed' END,
        'installed',
        CASE WHEN pgss_installed THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'pg_stat_statements', 'pg_stat_statements.track',
        COALESCE(pgss_track, '(not loaded)'),
        'top',
        CASE WHEN pgss_track = 'top' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'pg_stat_statements', 'pg_stat_statements.max',
        COALESCE(pgss_max, '(not loaded)'),
        '>= 5000',
        CASE WHEN pgss_max::int >= 5000 THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'metrics', 'compute_query_id',
        COALESCE(compute_query_id, '(unset)'),
        'on',
        CASE WHEN compute_query_id IN ('on', 'auto') THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'metrics', 'track_io_timing',
        COALESCE(track_io_timing, '(unset)'),
        'on',
        CASE WHEN track_io_timing = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'logging', 'logging_collector',
        COALESCE(logging_collector, '(unset)'),
        'on',
        CASE WHEN logging_collector = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'logging', 'log_destination',
        COALESCE(log_destination, '(unset)'),
        'contains jsonlog',
        CASE WHEN log_destination LIKE '%jsonlog%' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'logging', 'log_file_mode',
        COALESCE(log_file_mode, '(unset)'),
        '0640',
        CASE WHEN log_file_mode = '0640' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'logging', 'log_directory',
        COALESCE(log_directory, '(unset)'),
        'set',
        CASE WHEN COALESCE(log_directory, '') <> '' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'logging', 'log_filename',
        COALESCE(log_filename, '(unset)'),
        'set',
        CASE WHEN COALESCE(log_filename, '') <> '' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'logging', 'log_rotation_age (minutes)',
        COALESCE(log_rotation_age, '(unset)'),
        '> 0',
        CASE WHEN log_rotation_age::int > 0 THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'logging', 'log_rotation_size (kB)',
        COALESCE(log_rotation_size, '(unset)'),
        '> 0',
        CASE WHEN log_rotation_size::int > 0 THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'logging', 'log_timezone',
        COALESCE(log_timezone, '(unset)'),
        'set',
        CASE WHEN COALESCE(log_timezone, '') <> '' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'logging', 'log_min_duration_statement (ms)',
        COALESCE(log_min_duration_statement, '(unset)'),
        '> 0',
        CASE WHEN log_min_duration_statement::int > 0 THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'logging', 'log_lock_waits',
        COALESCE(log_lock_waits, '(unset)'),
        'on',
        CASE WHEN log_lock_waits = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'auto_explain', 'shared_preload_libraries: auto_explain',
        COALESCE(shared_preload_libraries, '(unset)'),
        'contains auto_explain',
        CASE WHEN shared_preload_libraries LIKE '%auto_explain%' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'required', 'auto_explain', 'auto_explain.log_format',
        COALESCE(ae_log_format, '(not loaded)'),
        'json',
        CASE WHEN ae_log_format = 'json' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'auto_explain', 'auto_explain.log_min_duration (ms)',
        COALESCE(ae_log_min_duration, '(not loaded)'),
        '> 0',
        CASE WHEN ae_log_min_duration::int > 0 THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'auto_explain', 'auto_explain.log_analyze',
        COALESCE(ae_log_analyze, '(not loaded)'),
        'on',
        CASE WHEN ae_log_analyze = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'auto_explain', 'auto_explain.log_buffers',
        COALESCE(ae_log_buffers, '(not loaded)'),
        'on',
        CASE WHEN ae_log_buffers = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'auto_explain', 'auto_explain.log_timing',
        COALESCE(ae_log_timing, '(not loaded)'),
        'on',
        CASE WHEN ae_log_timing = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'auto_explain', 'auto_explain.log_triggers',
        COALESCE(ae_log_triggers, '(not loaded)'),
        'on',
        CASE WHEN ae_log_triggers = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'auto_explain', 'auto_explain.log_verbose',
        COALESCE(ae_log_verbose, '(not loaded)'),
        'on',
        CASE WHEN ae_log_verbose = 'on' THEN 'OK' ELSE 'FAIL' END
    FROM s
    UNION ALL
    SELECT 'recommended', 'auto_explain', 'auto_explain.sample_rate',
        COALESCE(ae_sample_rate, '(not loaded)'),
        '> 0',
        CASE WHEN ae_sample_rate::float > 0 THEN 'OK' ELSE 'FAIL' END
    FROM s
) checks
ORDER BY status = 'OK', severity <> 'required', category, parameter;
