# Model uprawnień PostgreSQL

## Role aplikacyjne

Rola binturo_platform jest bezpośrednim właścicielem bazy aplikacyjnej,
schematów oraz obiektów tworzonych przez migracje. Ma:

- CONNECT i CREATE na bazie;
- pełne DDL wynikające z własności schematów i obiektów;
- pełne DML na swoich tabelach;
- wyłączne prawo tworzenia i aktualizowania schematów platformy, użytkowników
  oraz organizatorów.

Rola binturo_organizers nie jest właścicielem żadnego schematu ani obiektu.
Ma:

- CONNECT do bazy;
- USAGE na dozwolonych schematach;
- SELECT, INSERT, UPDATE, DELETE na tabelach schematów organizatorów
  i współdzielonego schematu użytkowników;
- USAGE, SELECT na ich sekwencjach;
- tylko SELECT do tabeli binturo_platform.organizers.

Rola organizers nie otrzymuje CREATE na bazie ani schematach. Nie może
wykonywać migracji, CREATE, ALTER, DROP ani samodzielnie zakładać schematów.

## Bootstrap i istniejące instalacje

Bootstrap Ansible jest idempotentny. Dla nowych instalacji ustawia login
platformy jako właściciela bazy i schematu początkowego. Dla istniejących
instalacji wykonuje REASSIGN OWNED ze starej roli binturo_platform_owner,
odbiera członkostwo w tej roli i porządkuje granty organizatora. Migruje także
własność ze starszych loginów binturo_platform_app i binturo_organizers_app,
a następnie blokuje im możliwość logowania.

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
    FOR ROLE binturo_platform
    IN SCHEMA nowy_schemat
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO binturo_organizers;

    ALTER DEFAULT PRIVILEGES
    FOR ROLE binturo_platform
    IN SCHEMA nowy_schemat
    GRANT USAGE, SELECT ON SEQUENCES
    TO binturo_organizers;

Nazwy schematów są identyfikatorami SQL. Kod aplikacji musi korzystać z
bezpiecznego cytowania identyfikatorów, a utworzenie schematu i nadanie grantów
powinno być jedną atomową operacją.
