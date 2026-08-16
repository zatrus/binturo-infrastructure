# Model uprawnień PostgreSQL

## Role aplikacyjne

Rola binturo_platform_app jest bezpośrednim właścicielem bazy aplikacyjnej,
schematów oraz obiektów tworzonych przez migracje. Ma:

- CONNECT i CREATE na bazie;
- pełne DDL wynikające z własności schematów i obiektów;
- pełne DML na swoich tabelach;
- wyłączne prawo tworzenia i aktualizowania schematów platformy, użytkowników
  oraz organizatorów.

Rola binturo_organizers jest stabilną rolą grupową NOLOGIN, do której migracje
platformy nadają uprawnienia. Rola logowania binturo_organizers_app jest jej
członkiem i nie jest właścicielem żadnego schematu ani obiektu.
Ma:

- CONNECT do bazy;
- USAGE na dozwolonych schematach;
- SELECT, INSERT, UPDATE, DELETE na tabelach schematów organizatorów
  i współdzielonego schematu użytkowników;
- USAGE, SELECT na ich sekwencjach;
- tylko SELECT do tabeli binturo_platform.organizers;
- tylko INSERT i UPDATE do tabeli
  binturo_platform.organizer_billing_info, używanej przez push-sync danych
  rozliczeniowych.

Rola organizers nie otrzymuje CREATE na bazie ani schematach. Nie może
wykonywać migracji, CREATE, ALTER, DROP ani samodzielnie zakładać schematów.

## Bootstrap i istniejące instalacje

Bootstrap Ansible jest idempotentny. Dla nowych instalacji ustawia login
platformy jako właściciela bazy i schematu początkowego. Dla istniejących
instalacji wykonuje REASSIGN OWNED ze starej roli binturo_platform_owner,
odbiera członkostwo w tej roli i porządkuje granty organizatora. Migruje także
własność z przejściowego loginu binturo_platform i blokuje mu możliwość
logowania. Istniejąca rola binturo_organizers jest normalizowana do NOLOGIN i
używana dalej jako grupa uprawnień backendu organizatora.

Przy każdym uruchomieniu playbooka wykonywany jest backfill uprawnień dla:

- binturo_users, jeśli istnieje;
- skonfigurowanego schematu organizers, jeśli istnieje;
- istniejących schematów zapisanych w binturo_platform.organizers.

Backfill najpierw odbiera wcześniejsze granty, a następnie nadaje wyłącznie
wymagane DML i dostęp do sekwencji.

## Nowe schematy organizatorów

Ansible nie zna nazw schematów tworzonych w przyszłości. Backend platformy musi
więc w tej samej transakcji, w której tworzy lub migruje schemat organizatora:

    GRANT USAGE ON SCHEMA nowy_schemat
    TO binturo_organizers;

    GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA nowy_schemat
    TO binturo_organizers;

    GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA nowy_schemat
    TO binturo_organizers;

    ALTER DEFAULT PRIVILEGES
    FOR ROLE binturo_platform_app
    IN SCHEMA nowy_schemat
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO binturo_organizers;

    ALTER DEFAULT PRIVILEGES
    FOR ROLE binturo_platform_app
    IN SCHEMA nowy_schemat
    GRANT USAGE, SELECT ON SEQUENCES
    TO binturo_organizers;

Nazwy schematów są identyfikatorami SQL. Kod aplikacji musi korzystać z
bezpiecznego cytowania identyfikatorów, a utworzenie schematu i nadanie grantów
powinno być jedną atomową operacją.

Na czystej instalacji tabela `binturo_platform.organizers` nie istnieje jeszcze
podczas `03-site`. Skrypt instaluje dlatego event trigger
`binturo_grant_organizers_registry_select`. Reaguje on na `CREATE TABLE` oraz
`ALTER TABLE`, ponieważ początkowa migracja tworzy tabelę `clubs`, a kolejna
zmienia jej nazwę na `organizers`. Gdy docelowa tabela pojawi się pod właściwą
nazwą, trigger nadaje `SELECT` roli grupowej `binturo_organizers`. Trigger nie
nadaje dostępu do żadnej innej tabeli schematu platformy.

Analogiczny event trigger `binturo_grant_organizers_billing_write` nadaje
wyłącznie `INSERT, UPDATE` po utworzeniu lub zmianie tabeli
`binturo_platform.organizer_billing_info`. Nie nadaje `SELECT`, `DELETE` ani
żadnych praw DDL. Jeżeli tabela istnieje już podczas uruchomienia playbooka,
bootstrap wykonuje ten sam grant bezpośrednio.

## Uruchamianie przez 03-site

Playbook `03-site.yml` instaluje projektową wersję skryptu
`roles/postgres/files/setup_db_roles.sql` jako
`/srv/binturo/compose/setup_db_roles.sql`. Rola PostgreSQL uruchamia go w
kontenerze `postgres-bootstrap` przy każdym wykonaniu playbooka.

Nazwa bazy nie jest wpisana w skrypcie na stałe. `bootstrap.sh.j2` przekazuje
wartość `postgres_database` z wybranego inventory. Skrypt łączy się początkowo
z techniczną bazą `postgres`, tworzy brakującą bazę aplikacyjną, a następnie
wykonuje `\\connect :database_name` przed konfiguracją schematów i uprawnień.
