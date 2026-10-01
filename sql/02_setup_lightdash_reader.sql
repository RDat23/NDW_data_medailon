\set ON_ERROR_STOP on

SELECT format('CREATE ROLE %I LOGIN', :'reader_user')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'reader_user'
) \gexec

SELECT format('ALTER ROLE %I PASSWORD %L', :'reader_user', :'reader_password') \gexec
SELECT format('ALTER ROLE %I SET default_transaction_read_only = on', :'reader_user') \gexec
SELECT format('ALTER ROLE %I SET statement_timeout = %L', :'reader_user', '5min') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'database_name', :'reader_user') \gexec
SELECT format('GRANT USAGE ON SCHEMA gold TO %I', :'reader_user') \gexec
SELECT format('GRANT SELECT ON ALL TABLES IN SCHEMA gold TO %I', :'reader_user') \gexec
SELECT format(
    'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA gold GRANT SELECT ON TABLES TO %I',
    :'owner_user',
    :'reader_user'
) \gexec
