# Docs

## Setup

### Collector

```sql
CREATE USER pgdozor_collector WITH PASSWORD 'CHANGE_ME' CONNECTION LIMIT 5;
GRANT pg_monitor TO pgdozor_collector;
```

```
# postgresql.conf
shared_preload_libraries = 'pg_stat_statements,auto_explain'
pg_stat_statements.track = top
pg_stat_statements.max = 20000
track_io_timing = on
compute_query_id = on

logging_collector = on
log_destination = 'jsonlog'
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = '1d'
log_rotation_size = '128MB'
log_timezone = 'UTC'
log_min_duration_statement = 1000
log_lock_waits = on
log_file_mode = 0640

auto_explain.log_format = 'json'
auto_explain.log_min_duration = 1000
auto_explain.log_analyze = on
auto_explain.log_buffers = on
auto_explain.log_timing = on
auto_explain.log_triggers = on
auto_explain.log_verbose = on
auto_explain.sample_rate = 0.5
```

give pgdozor-collector user permission to read and delete postgres log files:

```
usermod -aG adm pgdozor-collector // read access to log files
chmod -t /var/log/postgresql // remove sticky bit so pgdozor-collector can delete files in this directory
usermod -aG postgres pgdozor-collector // remove access to log files
```

```
systemctl restart postgresql
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

### Backend

### Frontend
