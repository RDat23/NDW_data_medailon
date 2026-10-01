\set ON_ERROR_STOP on

SELECT format(
    'ALTER ROLE %I PASSWORD %L',
    :'app_db_user',
    :'app_db_password'
) \gexec
