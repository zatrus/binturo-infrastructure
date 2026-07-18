# Binturo infrastructure

Projekt Ansible przygotowuje dwa niezależne hosty Ubuntu: `dev` i `prod`. Każdy host
otrzymuje Caddy, rootless Docker, PostgreSQL, lokalny Prometheus oraz katalogi dla:

- `binturo-platform`,
- `binturo-organizers`,
- dwóch frontendów,
- plików współdzielonych przez backendy.

Projekt nie implementuje procedury wdrażania aplikacji ani GitHub Actions.

## Założenia

- Ubuntu 24.04 lub nowsze;
- osobny host dla `dev` i `prod`;
- dostęp SSH kontem posiadającym `sudo`;
- publicznie dostępne są tylko porty 22, 80 i 443;
- kontenery działają przez rootless Docker użytkownika `binturo`;
- Caddy działa jako usługa systemowa;
- PostgreSQL nie publikuje portu na hoście;
- Prometheus publikuje API wyłącznie na `127.0.0.1:19090`.

## Przygotowanie

```bash
ansible-galaxy collection install -r requirements.yml
```

Uzupełnij:

- `ansible_host` i `ansible_user` w odpowiednim `hosts.yml`;
- domeny oraz adres e-mail Caddy;
- parametry retencji Prometheusa;
- opcjonalny endpoint `remote_write`.

Skopiuj przykładowy vault:

```bash
cp inventories/dev/group_vars/vault.example.yml inventories/dev/group_vars/vault.yml
ansible-vault encrypt inventories/dev/group_vars/vault.yml
```

Analogicznie przygotuj vault produkcyjny. Pliki `vault.yml` oraz `.vault-password` są
ignorowane przez Git.

## Sprawdzenie i uruchomienie

```bash
ansible-playbook -i inventories/dev/hosts.yml site.yml --syntax-check
ansible-playbook -i inventories/dev/hosts.yml site.yml --check --diff
ansible-playbook -i inventories/dev/hosts.yml site.yml --ask-vault-pass
```

Dla produkcji użyj `inventories/prod/hosts.yml` i jawnego `--limit binturo-prod`.

## PostgreSQL

Ansible tworzy:

- bazę `binturo_dev` albo `binturo_prod`;
- rolę właścicielską `binturo_platform_owner` bez możliwości logowania;
- konto `binturo_platform_app`, należące do roli właścicielskiej;
- konto `binturo_organizers_app` bez praw DDL;
- konto `binturo_backup` z rolą `pg_read_all_data`;
- początkowy schemat `binturo_platform`.

`binturo-platform` pozostaje jedynym właścicielem migracji oraz dynamicznych
schematów. Zasady nadawania praw do takich schematów opisuje
[docs/postgresql-dynamic-schemas.md](docs/postgresql-dynamic-schemas.md).

## Caddy

Konfiguracja bazowa znajduje się w `/etc/caddy/Caddyfile` i importuje:

```caddyfile
import snippets/*.caddy
import sites-enabled/*.caddy
```

Ansible przygotowuje katalog `/etc/caddy/sites-enabled`, ale nie generuje w nim
konfiguracji aplikacyjnych. Pozwala to oddzielić stałą konfigurację hosta od plików
tworzonych później przez właściwy mechanizm aplikacyjny.

Przed instalacją pliku dynamicznego należy zawsze wykonać:

```bash
caddy fmt --overwrite /etc/caddy/sites-enabled/nazwa.caddy
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl reload caddy
```

Przykładowa konfiguracja witryn znajduje się w
[docs/caddy-dynamic-config.md](docs/caddy-dynamic-config.md).

## Dane trwałe

PostgreSQL i Prometheus korzystają z nazwanych wolumenów rootless Docker. Katalog
`/srv/binturo/shared/binturo-organizers-files` jest przeznaczony na dane, które
`binturo-organizers` zapisuje, a `binturo-platform` może montować tylko do odczytu.
