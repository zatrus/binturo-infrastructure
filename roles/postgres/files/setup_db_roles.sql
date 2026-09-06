-- Project-adapted version of D:/projects/reservations/sql/setup_db_roles.sql.
-- The target database, login roles, group role, schemas and passwords are
-- supplied by Ansible from the selected inventory. Do not hard-code them here.
\set ON_ERROR_STOP on

SELECT format(
  'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT PASSWORD %L',
  :'platform_user',
  :'platform_password'
)
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'platform_user') \gexec
SELECT format(
  'ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT PASSWORD %L',
  :'platform_user',
  :'platform_password'
) \gexec

SELECT format(
  'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT PASSWORD %L',
  :'organizers_user',
  :'organizers_password'
)
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'organizers_user') \gexec
SELECT format(
  'ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT PASSWORD %L',
  :'organizers_user',
  :'organizers_password'
) \gexec

-- Application migrations grant schema privileges to the stable organizers
-- group role. The backend logs in through the environment-specific app role.
SELECT format(
  'CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT',
  :'organizers_group_role'
)
WHERE :'organizers_group_role' <> :'organizers_user'
  AND NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = :'organizers_group_role'
  ) \gexec
SELECT format('ALTER ROLE %I NOLOGIN', :'organizers_group_role')
WHERE :'organizers_group_role' <> :'organizers_user' \gexec
SELECT format(
  'GRANT %I TO %I',
  :'organizers_group_role',
  :'organizers_user'
)
WHERE :'organizers_group_role' <> :'organizers_user' \gexec

SELECT format(
  'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT PASSWORD %L',
  :'backup_user',
  :'backup_password'
)
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'backup_user') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'backup_user', :'backup_password') \gexec
SELECT format('REVOKE %I FROM %I', :'platform_user', :'organizers_user') \gexec

SELECT format(
  'CREATE DATABASE %I OWNER %I ENCODING ''UTF8'' TEMPLATE template0',
  :'database_name',
  :'platform_user'
)
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'database_name') \gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'database_name', :'platform_user') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'database_name') \gexec
SELECT format(
  'GRANT CONNECT, CREATE ON DATABASE %I TO %I',
  :'database_name',
  :'platform_user'
) \gexec
SELECT format(
  'REVOKE CREATE, TEMPORARY ON DATABASE %I FROM %I',
  :'database_name',
  :'organizers_user'
) \gexec
SELECT format(
  'GRANT CONNECT ON DATABASE %I TO %I',
  :'database_name',
  :'organizers_user'
) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'database_name', :'backup_user') \gexec
SELECT format('GRANT pg_read_all_data TO %I', :'backup_user') \gexec
SELECT format('GRANT pg_monitor TO %I', :'backup_user') \gexec

\connect :database_name

SELECT set_config('binturo.target_database', :'database_name', false);
SELECT set_config('binturo.platform_user', :'platform_user', false);
SELECT set_config('binturo.organizers_user', :'organizers_user', false);
SELECT set_config('binturo.legacy_owner_role', :'legacy_owner_role', false);
SELECT set_config('binturo.legacy_platform_user', :'legacy_platform_user', false);
SELECT set_config('binturo.organizers_group_role', :'organizers_group_role', false);
SELECT set_config('binturo.initial_schema', :'initial_schema', false);
SELECT set_config('binturo.organizers_schema', :'organizers_schema', false);
SELECT set_config('binturo.users_schema', :'users_schema', false);

DO $bootstrap$
BEGIN
  IF current_database() <> current_setting('binturo.target_database') THEN
    RAISE EXCEPTION 'setup_db_roles.sql connected to %, expected %',
      current_database(),
      current_setting('binturo.target_database');
  END IF;
END
$bootstrap$;

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('REVOKE CREATE ON SCHEMA public FROM %I', :'organizers_user') \gexec

-- Migrate objects created by the former NOLOGIN owner role. New installations
-- use the platform login as the direct database and object owner.
DO $bootstrap$
DECLARE
  legacy_owner text := current_setting('binturo.legacy_owner_role');
  legacy_platform text := current_setting('binturo.legacy_platform_user');
  organizers_group text := current_setting('binturo.organizers_group_role');
  platform_role text := current_setting('binturo.platform_user');
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = legacy_owner) THEN
    EXECUTE format('REASSIGN OWNED BY %I TO %I', legacy_owner, platform_role);
    EXECUTE format('REVOKE %I FROM %I', legacy_owner, platform_role);
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = legacy_platform) THEN
      EXECUTE format('REVOKE %I FROM %I', legacy_owner, legacy_platform);
    END IF;
  END IF;

  IF legacy_platform <> platform_role
    AND EXISTS (SELECT FROM pg_roles WHERE rolname = legacy_platform)
  THEN
    EXECUTE format('REASSIGN OWNED BY %I TO %I', legacy_platform, platform_role);
    EXECUTE format(
      'REVOKE CONNECT, CREATE, TEMPORARY ON DATABASE %I FROM %I',
      current_database(),
      legacy_platform
    );
    EXECUTE format('ALTER ROLE %I NOLOGIN', legacy_platform);
  END IF;

  IF organizers_group <> current_setting('binturo.organizers_user')
    AND EXISTS (SELECT FROM pg_roles WHERE rolname = organizers_group)
  THEN
    EXECUTE format('REASSIGN OWNED BY %I TO %I', organizers_group, platform_role);
    EXECUTE format(
      'REVOKE CONNECT, CREATE, TEMPORARY ON DATABASE %I FROM %I',
      current_database(),
      organizers_group
    );
    EXECUTE format('ALTER ROLE %I NOLOGIN', organizers_group);
  END IF;
END
$bootstrap$;

SELECT format(
  'CREATE SCHEMA IF NOT EXISTS %I AUTHORIZATION %I',
  :'initial_schema',
  :'platform_user'
) \gexec
SELECT format('ALTER SCHEMA %I OWNER TO %I', :'initial_schema', :'platform_user') \gexec

-- Organizers can inspect only the organizer registry in the platform schema.
SELECT format('REVOKE CREATE ON SCHEMA %I FROM %I', :'initial_schema', :'organizers_user') \gexec
SELECT format('REVOKE CREATE ON SCHEMA %I FROM %I', :'initial_schema', :'organizers_group_role') \gexec
SELECT format('GRANT USAGE ON SCHEMA %I TO %I', :'initial_schema', :'organizers_group_role') \gexec
SELECT format(
  'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I FROM %I',
  :'initial_schema',
  :'organizers_user'
) \gexec
SELECT format(
  'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I FROM %I',
  :'initial_schema',
  :'organizers_group_role'
) \gexec
SELECT format(
  'REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I FROM %I',
  :'initial_schema',
  :'organizers_user'
) \gexec
SELECT format(
  'REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I FROM %I',
  :'initial_schema',
  :'organizers_group_role'
) \gexec

DO $bootstrap$
DECLARE
  platform_schema text := current_setting('binturo.initial_schema');
  organizers_role text := current_setting('binturo.organizers_user');
  organizers_group text := current_setting('binturo.organizers_group_role');
  organizers_columns text;
BEGIN
  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'organizers'
  ) THEN
    SELECT string_agg(format('%I', column_name), ', ' ORDER BY ordinal_position)
    INTO organizers_columns
    FROM information_schema.columns
    WHERE table_schema = platform_schema
      AND table_name = 'organizers';

    IF organizers_columns IS NOT NULL THEN
      EXECUTE format(
        'REVOKE UPDATE (%s) ON %I.organizers FROM %I',
        organizers_columns,
        platform_schema,
        organizers_role
      );
      EXECUTE format(
        'REVOKE UPDATE (%s) ON %I.organizers FROM %I',
        organizers_columns,
        platform_schema,
        organizers_group
      );
    END IF;

    EXECUTE format(
      'GRANT SELECT ON %I.organizers TO %I',
      platform_schema,
      organizers_group
    );

    IF NOT EXISTS (
      SELECT required.column_name
      FROM (VALUES
        ('contact_phone'), ('contact_email'), ('street'),
        ('city'), ('postal_code'), ('country')
      ) AS required(column_name)
      WHERE NOT EXISTS (
        SELECT
        FROM information_schema.columns AS existing
        WHERE existing.table_schema = platform_schema
          AND existing.table_name = 'organizers'
          AND existing.column_name = required.column_name
      )
    ) THEN
      EXECUTE format(
        'GRANT UPDATE (contact_phone, contact_email, street, city, postal_code, country) ON %I.organizers TO %I',
        platform_schema,
        organizers_group
      );
    END IF;
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'organizer_billing_info'
  ) THEN
    EXECUTE format(
      'GRANT SELECT (organizer_id), INSERT, UPDATE ON %I.organizer_billing_info TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'payment_provider_account_index'
  ) THEN
    EXECUTE format(
      'GRANT SELECT, INSERT ON %I.payment_provider_account_index TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'subscriptions'
  ) THEN
    EXECUTE format(
      'GRANT SELECT ON %I.subscriptions TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'subscription_plans'
  ) THEN
    EXECUTE format(
      'GRANT SELECT ON %I.subscription_plans TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'subscription_payments'
  ) THEN
    EXECUTE format(
      'GRANT SELECT ON %I.subscription_payments TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'platform_settings'
  ) THEN
    EXECUTE format(
      'GRANT SELECT ON %I.platform_settings TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'internal_messages'
  ) THEN
    EXECUTE format(
      'GRANT SELECT, INSERT ON %I.internal_messages TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'internal_message_reads'
  ) THEN
    EXECUTE format(
      'GRANT SELECT, INSERT ON %I.internal_message_reads TO %I',
      platform_schema,
      organizers_group
    );
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'client_incident_messages'
  ) THEN
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE ON %I.client_incident_messages TO %I',
      platform_schema,
      organizers_group
    );
  END IF;
END
$bootstrap$;

-- On a clean infrastructure run the application registry table does not exist
-- yet. Grant SELECT exactly when the platform migration creates that table;
-- granting default SELECT on every future platform table would expose data the
-- organizers backend must not read.
SELECT format(
  $function_sql$
CREATE OR REPLACE FUNCTION %I.binturo_grant_organizers_registry_select()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $event_function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_event_trigger_ddl_commands() AS ddl_command
    WHERE ddl_command.objid = pg_catalog.to_regclass(%L)::oid
  ) THEN
    EXECUTE %L;
    IF (
      SELECT count(*)
      FROM pg_catalog.pg_attribute AS attribute
      WHERE attribute.attrelid = pg_catalog.to_regclass(%L)
        AND attribute.attname = ANY (ARRAY[
          'contact_phone', 'contact_email', 'street',
          'city', 'postal_code', 'country'
        ])
        AND attribute.attnum > 0
        AND NOT attribute.attisdropped
    ) = 6 THEN
      EXECUTE %L;
    END IF;
  END IF;
END
$event_function$
  $function_sql$,
  :'initial_schema',
  format('%I.organizers', :'initial_schema'),
  format(
    'GRANT SELECT ON %I.organizers TO %I',
    :'initial_schema',
    :'organizers_group_role'
  ),
  format('%I.organizers', :'initial_schema'),
  format(
    'GRANT UPDATE (contact_phone, contact_email, street, city, postal_code, country) ON %I.organizers TO %I',
    :'initial_schema',
    :'organizers_group_role'
  )
) \gexec

DROP EVENT TRIGGER IF EXISTS binturo_grant_organizers_registry_select;
SELECT format(
  'CREATE EVENT TRIGGER binturo_grant_organizers_registry_select ON ddl_command_end WHEN TAG IN (''CREATE TABLE'', ''ALTER TABLE'') EXECUTE FUNCTION %I.binturo_grant_organizers_registry_select()',
  :'initial_schema'
) \gexec

-- The billing sync table is also created by a platform migration. Organizers
-- may push billing data into it, but must not read or delete platform data.
SELECT format(
  $function_sql$
CREATE OR REPLACE FUNCTION %I.binturo_grant_organizers_billing_write()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $event_function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_event_trigger_ddl_commands() AS ddl_command
    WHERE ddl_command.objid = pg_catalog.to_regclass(%L)::oid
  ) THEN
    EXECUTE %L;
  END IF;
END
$event_function$
  $function_sql$,
  :'initial_schema',
  format('%I.organizer_billing_info', :'initial_schema'),
  format(
    'GRANT SELECT (organizer_id), INSERT, UPDATE ON %I.organizer_billing_info TO %I',
    :'initial_schema',
    :'organizers_group_role'
  )
) \gexec

DROP EVENT TRIGGER IF EXISTS binturo_grant_organizers_billing_write;
SELECT format(
  'CREATE EVENT TRIGGER binturo_grant_organizers_billing_write ON ddl_command_end WHEN TAG IN (''CREATE TABLE'', ''ALTER TABLE'') EXECUTE FUNCTION %I.binturo_grant_organizers_billing_write()',
  :'initial_schema'
) \gexec

-- Stripe Connect uses a narrow, immutable provider-account-to-organizer index
-- owned by the platform. Organizers may insert and read mappings, but may not
-- update or delete them. The table is created by a platform migration.
SELECT format(
  $function_sql$
CREATE OR REPLACE FUNCTION %I.binturo_grant_organizers_payment_index_access()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $event_function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_event_trigger_ddl_commands() AS ddl_command
    WHERE ddl_command.objid = pg_catalog.to_regclass(%L)::oid
  ) THEN
    EXECUTE %L;
  END IF;
END
$event_function$
  $function_sql$,
  :'initial_schema',
  format('%I.payment_provider_account_index', :'initial_schema'),
  format(
    'GRANT SELECT, INSERT ON %I.payment_provider_account_index TO %I',
    :'initial_schema',
    :'organizers_group_role'
  )
) \gexec

DROP EVENT TRIGGER IF EXISTS binturo_grant_organizers_payment_index_access;
SELECT format(
  'CREATE EVENT TRIGGER binturo_grant_organizers_payment_index_access ON ddl_command_end WHEN TAG IN (''CREATE TABLE'', ''ALTER TABLE'') EXECUTE FUNCTION %I.binturo_grant_organizers_payment_index_access()',
  :'initial_schema'
) \gexec

-- The organizers staff app reads the current subscription, plan catalogue,
-- payment history, and platform settings. Writes remain exclusive to the
-- platform backend.
SELECT format(
  $function_sql$
CREATE OR REPLACE FUNCTION %I.binturo_grant_organizers_subscription_read()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $event_function$
DECLARE
  relation_name text;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[%L, %L, %L, %L]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_event_trigger_ddl_commands() AS ddl_command
      WHERE ddl_command.objid = pg_catalog.to_regclass(relation_name)::oid
    ) THEN
      EXECUTE format('GRANT SELECT ON %%s TO %%I', relation_name, %L);
    END IF;
  END LOOP;
END
$event_function$
  $function_sql$,
  :'initial_schema',
  format('%I.subscriptions', :'initial_schema'),
  format('%I.subscription_plans', :'initial_schema'),
  format('%I.subscription_payments', :'initial_schema'),
  format('%I.platform_settings', :'initial_schema'),
  :'organizers_group_role'
) \gexec

DROP EVENT TRIGGER IF EXISTS binturo_grant_organizers_subscription_read;
SELECT format(
  'CREATE EVENT TRIGGER binturo_grant_organizers_subscription_read ON ddl_command_end WHEN TAG IN (''CREATE TABLE'', ''ALTER TABLE'') EXECUTE FUNCTION %I.binturo_grant_organizers_subscription_read()',
  :'initial_schema'
) \gexec

-- Internal messages and per-organizer read receipts are append-only from the
-- organizers backend perspective. Platform migrations create both tables.
SELECT format(
  $function_sql$
CREATE OR REPLACE FUNCTION %I.binturo_grant_organizers_internal_message_access()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $event_function$
DECLARE
  relation_name text;
BEGIN
  FOREACH relation_name IN ARRAY ARRAY[%L, %L]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_catalog.pg_event_trigger_ddl_commands() AS ddl_command
      WHERE ddl_command.objid = pg_catalog.to_regclass(relation_name)::oid
    ) THEN
      EXECUTE format('GRANT SELECT, INSERT ON %%s TO %%I', relation_name, %L);
    END IF;
  END LOOP;
END
$event_function$
  $function_sql$,
  :'initial_schema',
  format('%I.internal_messages', :'initial_schema'),
  format('%I.internal_message_reads', :'initial_schema'),
  :'organizers_group_role'
) \gexec

DROP EVENT TRIGGER IF EXISTS binturo_grant_organizers_internal_message_access;
SELECT format(
  'CREATE EVENT TRIGGER binturo_grant_organizers_internal_message_access ON ddl_command_end WHEN TAG IN (''CREATE TABLE'', ''ALTER TABLE'') EXECUTE FUNCTION %I.binturo_grant_organizers_internal_message_access()',
  :'initial_schema'
) \gexec

-- Client incident conversations are stored in the platform schema but are
-- read and answered by clients through the organizers backend. UPDATE is
-- limited by application logic to read/visibility state; DELETE and DDL stay
-- unavailable to the organizers role.
SELECT format(
  $function_sql$
CREATE OR REPLACE FUNCTION %I.binturo_grant_organizers_client_incident_access()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $event_function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_event_trigger_ddl_commands() AS ddl_command
    WHERE ddl_command.objid = pg_catalog.to_regclass(%L)::oid
  ) THEN
    EXECUTE %L;
  END IF;
END
$event_function$
  $function_sql$,
  :'initial_schema',
  format('%I.client_incident_messages', :'initial_schema'),
  format(
    'GRANT SELECT, INSERT, UPDATE ON %I.client_incident_messages TO %I',
    :'initial_schema',
    :'organizers_group_role'
  )
) \gexec

DROP EVENT TRIGGER IF EXISTS binturo_grant_organizers_client_incident_access;
SELECT format(
  'CREATE EVENT TRIGGER binturo_grant_organizers_client_incident_access ON ddl_command_end WHEN TAG IN (''CREATE TABLE'', ''ALTER TABLE'') EXECUTE FUNCTION %I.binturo_grant_organizers_client_incident_access()',
  :'initial_schema'
) \gexec

-- Ensure the known shared schemas exist before application migrations start,
-- then apply DML-only permissions for the organizers backend. Without this,
-- a schema created later by the platform migrations would miss these grants.
DO $bootstrap$
DECLARE
  platform_role text := current_setting('binturo.platform_user');
  organizers_role text := current_setting('binturo.organizers_user');
  platform_schema text := current_setting('binturo.initial_schema');
  target_schema text;
BEGIN
  FOR target_schema IN
    SELECT DISTINCT schema_name
    FROM (
      SELECT current_setting('binturo.users_schema') AS schema_name
      UNION ALL
      SELECT current_setting('binturo.organizers_schema')
    ) configured_schemas
  LOOP
    EXECUTE format(
      'CREATE SCHEMA IF NOT EXISTS %I AUTHORIZATION %I',
      target_schema,
      platform_role
    );
    EXECUTE format('ALTER SCHEMA %I OWNER TO %I', target_schema, platform_role);
    EXECUTE format('REVOKE ALL ON SCHEMA %I FROM %I', target_schema, organizers_role);
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', target_schema, organizers_role);
    EXECUTE format(
      'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I FROM %I',
      target_schema,
      organizers_role
    );
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO %I',
      target_schema,
      organizers_role
    );
    EXECUTE format(
      'REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I FROM %I',
      target_schema,
      organizers_role
    );
    EXECUTE format(
      'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA %I TO %I',
      target_schema,
      organizers_role
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I',
      platform_role,
      target_schema,
      organizers_role
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT USAGE, SELECT ON SEQUENCES TO %I',
      platform_role,
      target_schema,
      organizers_role
    );
  END LOOP;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'organizers'
  ) THEN
    FOR target_schema IN EXECUTE format(
      'SELECT schema_name FROM %I.organizers',
      platform_schema
    )
    LOOP
      IF EXISTS (
        SELECT
        FROM information_schema.schemata s
        WHERE s.schema_name = target_schema
      ) THEN
        EXECUTE format('ALTER SCHEMA %I OWNER TO %I', target_schema, platform_role);
        EXECUTE format('REVOKE ALL ON SCHEMA %I FROM %I', target_schema, organizers_role);
        EXECUTE format('GRANT USAGE ON SCHEMA %I TO %I', target_schema, organizers_role);
        EXECUTE format(
          'REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA %I FROM %I',
          target_schema,
          organizers_role
        );
        EXECUTE format(
          'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO %I',
          target_schema,
          organizers_role
        );
        EXECUTE format(
          'REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA %I FROM %I',
          target_schema,
          organizers_role
        );
        EXECUTE format(
          'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA %I TO %I',
          target_schema,
          organizers_role
        );
        EXECUTE format(
          'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I',
          platform_role,
          target_schema,
          organizers_role
        );
        EXECUTE format(
          'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I GRANT USAGE, SELECT ON SEQUENCES TO %I',
          platform_role,
          target_schema,
          organizers_role
        );
      END IF;
    END LOOP;
  END IF;
END
$bootstrap$;

-- Fail closed if the least-privilege boundary is not effective.
DO $bootstrap$
DECLARE
  platform_role text := current_setting('binturo.platform_user');
  organizers_role text := current_setting('binturo.organizers_user');
  organizers_group text := current_setting('binturo.organizers_group_role');
  platform_schema text := current_setting('binturo.initial_schema');
  profile_column text;
  target_schema text;
BEGIN
  IF NOT has_database_privilege(platform_role, current_database(), 'CREATE') THEN
    RAISE EXCEPTION 'Platform role % lacks CREATE on database %',
      platform_role,
      current_database();
  END IF;

  IF has_database_privilege(organizers_role, current_database(), 'CREATE') THEN
    RAISE EXCEPTION 'Organizers role % unexpectedly has CREATE on database %',
      organizers_role,
      current_database();
  END IF;

  IF pg_has_role(organizers_role, platform_role, 'MEMBER') THEN
    RAISE EXCEPTION 'Organizers role % is a member of platform role %',
      organizers_role,
      platform_role;
  END IF;

  IF organizers_group <> organizers_role
    AND NOT pg_has_role(organizers_role, organizers_group, 'MEMBER')
  THEN
    RAISE EXCEPTION 'Organizers login role % is not a member of group role %',
      organizers_role,
      organizers_group;
  END IF;

  IF NOT has_schema_privilege(organizers_group, platform_schema, 'USAGE') THEN
    RAISE EXCEPTION 'Organizers group role % lacks USAGE on schema %',
      organizers_group,
      platform_schema;
  END IF;

  IF has_schema_privilege(organizers_group, platform_schema, 'CREATE') THEN
    RAISE EXCEPTION 'Organizers group role % unexpectedly has CREATE on schema %',
      organizers_group,
      platform_schema;
  END IF;

  IF NOT EXISTS (
    SELECT
    FROM pg_event_trigger
    WHERE evtname = 'binturo_grant_organizers_registry_select'
      AND evtenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Registry SELECT grant event trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT
    FROM pg_event_trigger
    WHERE evtname = 'binturo_grant_organizers_billing_write'
      AND evtenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Billing INSERT/UPDATE grant event trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT
    FROM pg_event_trigger
    WHERE evtname = 'binturo_grant_organizers_payment_index_access'
      AND evtenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Payment index SELECT/INSERT grant event trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT
    FROM pg_event_trigger
    WHERE evtname = 'binturo_grant_organizers_subscription_read'
      AND evtenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Subscription SELECT grant event trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT
    FROM pg_event_trigger
    WHERE evtname = 'binturo_grant_organizers_internal_message_access'
      AND evtenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Internal message SELECT/INSERT grant event trigger is missing or disabled';
  END IF;

  IF NOT EXISTS (
    SELECT
    FROM pg_event_trigger
    WHERE evtname = 'binturo_grant_organizers_client_incident_access'
      AND evtenabled <> 'D'
  ) THEN
    RAISE EXCEPTION 'Client incident SELECT/INSERT/UPDATE grant event trigger is missing or disabled';
  END IF;

  IF EXISTS (
    SELECT
    FROM pg_roles
    WHERE rolname = organizers_group
      AND rolcanlogin
  ) THEN
    RAISE EXCEPTION 'Organizers group role % unexpectedly permits login',
      organizers_group;
  END IF;

  IF EXISTS (
    SELECT
    FROM pg_namespace n
    JOIN pg_roles r ON r.oid = n.nspowner
    WHERE r.rolname = organizers_role
  ) THEN
    RAISE EXCEPTION 'Organizers role % owns at least one schema', organizers_role;
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'organizers'
  ) AND NOT has_table_privilege(
    organizers_group,
    format('%I.organizers', platform_schema),
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'Organizers group role % lacks SELECT on %.organizers',
      organizers_group,
      platform_schema;
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'organizers'
  ) AND NOT EXISTS (
    SELECT required.column_name
    FROM (VALUES
      ('contact_phone'), ('contact_email'), ('street'),
      ('city'), ('postal_code'), ('country')
    ) AS required(column_name)
    WHERE NOT EXISTS (
      SELECT
      FROM information_schema.columns AS existing
      WHERE existing.table_schema = platform_schema
        AND existing.table_name = 'organizers'
        AND existing.column_name = required.column_name
    )
  ) THEN
    FOREACH profile_column IN ARRAY ARRAY[
      'contact_phone', 'contact_email', 'street',
      'city', 'postal_code', 'country'
    ]
    LOOP
      IF NOT has_column_privilege(
        organizers_group,
        format('%I.organizers', platform_schema),
        profile_column,
        'UPDATE'
      ) THEN
        RAISE EXCEPTION 'Organizers group role % lacks UPDATE on %.organizers column %',
          organizers_group,
          platform_schema,
          profile_column;
      END IF;
    END LOOP;

    IF has_table_privilege(
      organizers_group,
      format('%I.organizers', platform_schema),
      'UPDATE'
    ) OR EXISTS (
      SELECT
      FROM information_schema.columns AS disallowed
      WHERE disallowed.table_schema = platform_schema
        AND disallowed.table_name = 'organizers'
        AND disallowed.column_name <> ALL (ARRAY[
          'contact_phone', 'contact_email', 'street',
          'city', 'postal_code', 'country'
        ])
        AND has_column_privilege(
          organizers_group,
          format('%I.organizers', platform_schema),
          disallowed.column_name,
          'UPDATE'
        )
    ) THEN
      RAISE EXCEPTION 'Organizers group role % has excessive UPDATE privileges on %.organizers',
        organizers_group,
        platform_schema;
    END IF;
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'organizer_billing_info'
  ) THEN
    IF NOT has_table_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'INSERT'
    ) OR NOT has_table_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'UPDATE'
    ) THEN
      RAISE EXCEPTION 'Organizers group role % lacks INSERT/UPDATE on %.organizer_billing_info',
        organizers_group,
        platform_schema;
    END IF;

    IF NOT has_column_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'organizer_id',
      'SELECT'
    ) THEN
      RAISE EXCEPTION 'Organizers group role % lacks SELECT on %.organizer_billing_info.organizer_id',
        organizers_group,
        platform_schema;
    END IF;

    IF has_table_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'SELECT'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'DELETE'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'TRUNCATE'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'REFERENCES'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.organizer_billing_info', platform_schema),
      'TRIGGER'
    ) OR EXISTS (
      SELECT
      FROM information_schema.columns AS disallowed
      WHERE disallowed.table_schema = platform_schema
        AND disallowed.table_name = 'organizer_billing_info'
        AND disallowed.column_name <> 'organizer_id'
        AND has_column_privilege(
          organizers_group,
          format('%I.organizer_billing_info', platform_schema),
          disallowed.column_name,
          'SELECT'
        )
    ) THEN
      RAISE EXCEPTION 'Organizers group role % has excessive privileges on %.organizer_billing_info',
      organizers_group,
      platform_schema;
    END IF;
  END IF;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'payment_provider_account_index'
  ) THEN
    IF NOT has_table_privilege(
      organizers_group,
      format('%I.payment_provider_account_index', platform_schema),
      'SELECT'
    ) OR NOT has_table_privilege(
      organizers_group,
      format('%I.payment_provider_account_index', platform_schema),
      'INSERT'
    ) THEN
      RAISE EXCEPTION 'Organizers group role % lacks SELECT/INSERT on %.payment_provider_account_index',
        organizers_group,
        platform_schema;
    END IF;

    IF has_table_privilege(
      organizers_group,
      format('%I.payment_provider_account_index', platform_schema),
      'UPDATE'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.payment_provider_account_index', platform_schema),
      'DELETE'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.payment_provider_account_index', platform_schema),
      'TRUNCATE'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.payment_provider_account_index', platform_schema),
      'REFERENCES'
    ) OR has_table_privilege(
      organizers_group,
      format('%I.payment_provider_account_index', platform_schema),
      'TRIGGER'
    ) THEN
      RAISE EXCEPTION 'Organizers group role % has excessive privileges on %.payment_provider_account_index',
        organizers_group,
        platform_schema;
    END IF;
  END IF;

  FOREACH target_schema IN ARRAY ARRAY[
    'subscriptions', 'subscription_plans', 'subscription_payments',
    'platform_settings'
  ]
  LOOP
    IF EXISTS (
      SELECT
      FROM information_schema.tables
      WHERE table_schema = platform_schema
        AND table_name = target_schema
    ) THEN
      IF NOT has_table_privilege(
        organizers_group,
        format('%I.%I', platform_schema, target_schema),
        'SELECT'
      ) THEN
        RAISE EXCEPTION 'Organizers group role % lacks SELECT on %.%',
          organizers_group,
          platform_schema,
          target_schema;
      END IF;

      IF EXISTS (
        SELECT
        FROM unnest(ARRAY[
          'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
          'REFERENCES', 'TRIGGER'
        ]) AS forbidden(privilege_name)
        WHERE has_table_privilege(
          organizers_group,
          format('%I.%I', platform_schema, target_schema),
          forbidden.privilege_name
        )
      ) THEN
        RAISE EXCEPTION 'Organizers group role % has excessive privileges on %.%',
          organizers_group,
          platform_schema,
          target_schema;
      END IF;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT
    FROM information_schema.tables
    WHERE table_schema = platform_schema
      AND table_name = 'client_incident_messages'
  ) THEN
    IF NOT has_table_privilege(
      organizers_group,
      format('%I.client_incident_messages', platform_schema),
      'SELECT'
    ) OR NOT has_table_privilege(
      organizers_group,
      format('%I.client_incident_messages', platform_schema),
      'INSERT'
    ) OR NOT has_table_privilege(
      organizers_group,
      format('%I.client_incident_messages', platform_schema),
      'UPDATE'
    ) THEN
      RAISE EXCEPTION 'Organizers group role % lacks SELECT/INSERT/UPDATE on %.client_incident_messages',
        organizers_group,
        platform_schema;
    END IF;

    IF EXISTS (
      SELECT
      FROM unnest(ARRAY[
        'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
      ]) AS forbidden(privilege_name)
      WHERE has_table_privilege(
        organizers_group,
        format('%I.client_incident_messages', platform_schema),
        forbidden.privilege_name
      )
    ) THEN
      RAISE EXCEPTION 'Organizers group role % has excessive privileges on %.client_incident_messages',
        organizers_group,
        platform_schema;
    END IF;
  END IF;

  FOREACH target_schema IN ARRAY ARRAY[
    'internal_messages', 'internal_message_reads'
  ]
  LOOP
    IF EXISTS (
      SELECT
      FROM information_schema.tables
      WHERE table_schema = platform_schema
        AND table_name = target_schema
    ) THEN
      IF NOT has_table_privilege(
        organizers_group,
        format('%I.%I', platform_schema, target_schema),
        'SELECT'
      ) OR NOT has_table_privilege(
        organizers_group,
        format('%I.%I', platform_schema, target_schema),
        'INSERT'
      ) THEN
        RAISE EXCEPTION 'Organizers group role % lacks SELECT/INSERT on %.%',
          organizers_group,
          platform_schema,
          target_schema;
      END IF;

      IF EXISTS (
        SELECT
        FROM unnest(ARRAY[
          'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
        ]) AS forbidden(privilege_name)
        WHERE has_table_privilege(
          organizers_group,
          format('%I.%I', platform_schema, target_schema),
          forbidden.privilege_name
        )
      ) THEN
        RAISE EXCEPTION 'Organizers group role % has excessive privileges on %.%',
          organizers_group,
          platform_schema,
          target_schema;
      END IF;
    END IF;
  END LOOP;

  FOREACH target_schema IN ARRAY ARRAY[
    current_setting('binturo.users_schema'),
    current_setting('binturo.organizers_schema')
  ]
  LOOP
    IF NOT has_schema_privilege(organizers_role, target_schema, 'USAGE') THEN
      RAISE EXCEPTION 'Organizers role % lacks USAGE on schema %',
        organizers_role,
        target_schema;
    END IF;

    IF has_schema_privilege(organizers_role, target_schema, 'CREATE') THEN
      RAISE EXCEPTION 'Organizers role % unexpectedly has CREATE on schema %',
        organizers_role,
        target_schema;
    END IF;
  END LOOP;
END
$bootstrap$;
