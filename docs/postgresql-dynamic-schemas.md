# Dynamiczne schematy PostgreSQL

## Odpowiedzialność

`binturo-platform` tworzy i aktualizuje wszystkie dynamiczne schematy PostgreSQL.
`binturo-organizers` korzysta z ich danych, ale nie może tworzyć, zmieniać ani usuwać
schematów i obiektów.

Ansible przygotowuje role oraz bazę, lecz nie zna nazw schematów tworzonych później.
Dlatego po utworzeniu każdego dynamicznego schematu `binturo-platform` musi nadać
uprawnienia roli `binturo_organizers_app`.

## Uprawnienia do istniejących obiektów

Poniższy SQL należy wykonać w tej samej transakcji lub operacji inicjalizującej
schemat. `nowy_schemat` należy zastąpić bezpiecznie zacytowanym identyfikatorem.

```sql
GRANT USAGE ON SCHEMA nowy_schemat
TO binturo_organizers_app;

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA nowy_schemat
TO binturo_organizers_app;

GRANT USAGE, SELECT, UPDATE
ON ALL SEQUENCES IN SCHEMA nowy_schemat
TO binturo_organizers_app;
```

Jeżeli `binturo-organizers` ma tylko odczytywać dane, należy ograniczyć prawa tabel
do `SELECT`, a sekwencje pominąć.

## Uprawnienia do przyszłych obiektów

Granty dla istniejących tabel nie obejmują tabel utworzonych przez następne migracje.
Po utworzeniu schematu trzeba więc ustawić również domyślne uprawnienia:

```sql
ALTER DEFAULT PRIVILEGES
FOR ROLE binturo_platform_owner
IN SCHEMA nowy_schemat
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
TO binturo_organizers_app;

ALTER DEFAULT PRIVILEGES
FOR ROLE binturo_platform_owner
IN SCHEMA nowy_schemat
GRANT USAGE, SELECT, UPDATE ON SEQUENCES
TO binturo_organizers_app;
```

`ALTER DEFAULT PRIVILEGES` dotyczy obiektów tworzonych przez wskazaną rolę. Migracje
muszą więc tworzyć obiekty jako `binturo_platform_owner`. Jeśli obiekty utworzy inna
rola, powyższe prawa domyślne nie zostaną zastosowane.

## Bezpieczna implementacja

Nazwy schematów są identyfikatorami SQL i nie mogą być przekazywane jako zwykłe
parametry tekstowe. Kod aplikacji powinien korzystać z mechanizmu bezpiecznego
cytowania identyfikatorów udostępnianego przez sterownik, np. `psycopg.sql.Identifier`.

Operacja utworzenia schematu powinna zakończyć się błędem, jeżeli nie uda się nadać
pełnego zestawu wymaganych uprawnień. Dzięki temu nie powstanie częściowo
skonfigurowany schemat, którego `binturo-organizers` nie może prawidłowo używać.

Po każdej migracji dodającej obiekty warto wykonać ponownie granty `ON ALL TABLES`
i `ON ALL SEQUENCES`. Jest to idempotentne i zabezpiecza także obiekty utworzone przez
starszy kod, zanim skonfigurowano prawa domyślne.

