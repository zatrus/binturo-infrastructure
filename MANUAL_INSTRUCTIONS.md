# Ręczna obsługa środowiska Binturo

Dokument opisuje bezpieczne zatrzymywanie, uruchamianie i diagnostykę zasobów
utworzonych przez Ansible. Do trwałych zmian konfiguracji nadal używaj playbooków;
polecenia ręczne służą głównie do obsługi awarii i diagnostyki.

Przykłady dotyczą środowiska `dev`. Dla produkcji zamień `dev` na `prod`, nazwę
bazy na wartość `postgres_database` z inventory oraz — jeśli został zmieniony — UID
użytkownika `binturo`.

## Przygotowanie sesji rootless Docker

Docker działa jako nieuprzywilejowany użytkownik `binturo`, a nie jako systemowa
usługa `root`. Rozpocznij sesję:

```bash
sudo -iu binturo
export XDG_RUNTIME_DIR=/run/user/1500
export DOCKER_HOST=unix:///run/user/1500/docker.sock
export BINTURO_ENVIRONMENT=dev
cd /srv/binturo/compose
```

Podstawowa kontrola:

```bash
docker info
docker ps -a
docker compose version
```

Nie używaj tutaj `sudo docker`. Wskazałoby ono rootful Docker, który w tym
projekcie jest wyłączony i zamaskowany.

## Rootless Docker

Status i logi wykonuj z konta administratora hosta:

```bash
sudo -u binturo XDG_RUNTIME_DIR=/run/user/1500 systemctl --user status docker.service
sudo -u binturo XDG_RUNTIME_DIR=/run/user/1500 journalctl --user -u docker.service -n 200 --no-pager
sudo -u binturo XDG_RUNTIME_DIR=/run/user/1500 journalctl --user -u docker.service -f
```

Restart, zatrzymanie i uruchomienie demona:

```bash
sudo -u binturo XDG_RUNTIME_DIR=/run/user/1500 systemctl --user restart docker.service
sudo -u binturo XDG_RUNTIME_DIR=/run/user/1500 systemctl --user stop docker.service
sudo -u binturo XDG_RUNTIME_DIR=/run/user/1500 systemctl --user start docker.service
```

Restart demona powoduje krótką przerwę wszystkich kontenerów. Kontenery projektu
mają `restart: always`, dlatego Docker podniesie je automatycznie także po restarcie
hosta.

## Backendy

Backendy są obsługiwane przez systemowe jednostki działające jako użytkownik
`binturo`:

- `binturo-platform.service` wywołuje
  `/srv/binturo/apps/backend-platform/binturo_platform.sh`;
- `binturo-organizers.service` wywołuje
  `/srv/binturo/apps/backend-organizers/binturo_organizers.sh`.

Jednostki są włączone podczas startu hosta, czekają na rootless Docker i zdrowy
PostgreSQL, a następnie wykonują skrypt z argumentem `start`. Podczas zatrzymania
wykonują go z argumentem `stop`.

Status, start, stop i restart:

```bash
sudo systemctl status binturo-platform.service binturo-organizers.service
sudo systemctl start binturo-platform.service binturo-organizers.service
sudo systemctl stop binturo-platform.service binturo-organizers.service
sudo systemctl restart binturo-platform.service binturo-organizers.service
```

Logi jednostek i procesów zapisujących do stdout/stderr:

```bash
sudo journalctl -u binturo-platform.service -n 200 --no-pager
sudo journalctl -u binturo-organizers.service -n 200 --no-pager
sudo journalctl -u binturo-platform.service -u binturo-organizers.service -f
```

Ręczne sprawdzenie interfejsu skryptów:

```bash
sudo -u binturo /srv/binturo/apps/backend-platform/binturo_platform.sh status
sudo -u binturo /srv/binturo/apps/backend-organizers/binturo_organizers.sh status
```

Ansible tworzy początkowe skrypty tylko wtedy, gdy pliki nie istnieją. Kolejne
uruchomienia playbooka nie nadpisują treści zmienionej przez inny proces. Skrypt
docelowy musi zakończyć `start`, `stop` i `status` kodem `0` po udanej operacji.
Interfejs zakłada, że `start` uruchamia backend w tle i następnie kończy działanie;
proces pozostający na pierwszym planie przekroczy timeout jednostki `oneshot`.

## Środowiska Python venv

Ansible tworzy środowiska w następujących lokalizacjach:

```text
/srv/binturo/apps/backend-organizers/venv
/srv/binturo/apps/frontend-platform/venv
```

Kontrola interpretera i zainstalowanych pakietów:

```bash
sudo -u binturo /srv/binturo/apps/backend-organizers/venv/bin/python --version
sudo -u binturo /srv/binturo/apps/backend-organizers/venv/bin/pip list
sudo -u binturo /srv/binturo/apps/frontend-platform/venv/bin/python --version
```

Rola nie przebudowuje istniejącego `venv`. Zmiana
`binturo_venv_python_executable` nie zmieni interpretera już utworzonego środowiska;
wymaga to świadomego usunięcia lub przeniesienia starego katalogu `venv` i ponownego
uruchomienia playbooka.

Host ma zainstalowane `build-essential`, `python3.14-dev` i `libpq-dev`, dzięki
czemu pip może kompilować rozszerzenia, takie jak `psycopg2-binary`, gdy PyPI nie
udostępnia gotowego koła dla używanej wersji Pythona. Diagnostyka:

```bash
gcc --version
pg_config --version
/srv/binturo/apps/backend-platform/venv/bin/python --version
```

## PostgreSQL

Plik Compose znajduje się w `/srv/binturo/compose/compose.postgres.yml`, kontener
nazywa się `binturo-postgres`, a dane znajdują się w `postgres_data_path`, domyślnie
`/srv/binturo/persistent/postgres`.

PostgreSQL jest opublikowany wyłącznie na loopback hosta jako
`127.0.0.1:5432`. Lokalny backend może użyć `PGHOST=127.0.0.1` i `PGPORT=5432`.
Port nie jest dostępny z sieci zewnętrznej i nie należy dodawać go do UFW.
Sieć `binturo_<środowisko>_database` nie może mieć `Internal=true`, ponieważ w
rootless Docker uniemożliwia to aktywowanie publikowanego portu loopback.

### Status i kondycja

W sesji użytkownika `binturo`:

```bash
docker compose --project-name binturo-dev --file compose.postgres.yml ps
docker inspect --format '{{.State.Status}} {{.State.Health.Status}}' binturo-postgres
docker exec binturo-postgres pg_isready -U postgres
pg_isready -h 127.0.0.1 -p 5432
```

### Zatrzymanie, uruchomienie i restart

```bash
docker compose --project-name binturo-dev --file compose.postgres.yml stop postgres
docker compose --project-name binturo-dev --file compose.postgres.yml start postgres
docker compose --project-name binturo-dev --file compose.postgres.yml restart postgres
```

Jeżeli kontener nie istnieje albo zmienił się plik Compose:

```bash
docker compose --project-name binturo-dev --file compose.postgres.yml up -d postgres
```

Usunięcie samego kontenera nie usuwa danych z bind mounta:

```bash
docker compose --project-name binturo-dev --file compose.postgres.yml down
docker compose --project-name binturo-dev --file compose.postgres.yml up -d postgres
```

Nie usuwaj ręcznie `/srv/binturo/persistent/postgres`. Nie usuwaj też dawnego
wolumenu PostgreSQL, dopóki migracja i niezależny backup nie zostaną potwierdzone.

### Logi

```bash
docker logs --tail 200 binturo-postgres
docker logs --since 30m binturo-postgres
docker logs --timestamps --follow binturo-postgres
```

### Połączenie i kontrola bazy

```bash
docker exec -it binturo-postgres psql -U postgres -d postgres
docker exec -it binturo-postgres psql -U postgres -d binturo_dev_warszawa
```

Przydatne polecenia `psql`:

```text
\l
\du
\dn
\dt *.*
\q
```

Sprawdzenie mounta oraz miejsca:

```bash
docker inspect binturo-postgres --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
sudo ss -lntp | grep '127.0.0.1:5432'
sudo du -sh /srv/binturo/persistent/postgres
df -h /srv/binturo/persistent/postgres
```

Nie zmieniaj ręcznie właściciela plików PostgreSQL. Przy rootless Docker UID
widoczne na hoście wynikają z mapowania subordinate UID i mogą wyglądać nietypowo.

## Monitoring

Stack zawiera `binturo-prometheus`, `binturo-node-exporter` i
`binturo-postgres-exporter`.

Status:

```bash
docker compose --project-name binturo-monitoring-dev --file compose.monitoring.yml ps
docker ps --filter name=binturo-prometheus --filter name=binturo-node-exporter --filter name=binturo-postgres-exporter
```

Zatrzymanie, uruchomienie i restart całego stacku:

```bash
docker compose --project-name binturo-monitoring-dev --file compose.monitoring.yml stop
docker compose --project-name binturo-monitoring-dev --file compose.monitoring.yml start
docker compose --project-name binturo-monitoring-dev --file compose.monitoring.yml restart
```

Odtworzenie kontenerów po zmianie Compose:

```bash
docker compose --project-name binturo-monitoring-dev --file compose.monitoring.yml up -d
```

Logi całego stacku lub pojedynczej usługi:

```bash
docker compose --project-name binturo-monitoring-dev --file compose.monitoring.yml logs --tail 200
docker compose --project-name binturo-monitoring-dev --file compose.monitoring.yml logs -f prometheus
docker logs --tail 200 binturo-node-exporter
docker logs --tail 200 binturo-postgres-exporter
```

Kontrola lokalnego API Prometheusa:

```bash
curl --fail http://127.0.0.1:19090/-/healthy
curl --fail http://127.0.0.1:19090/-/ready
curl --fail 'http://127.0.0.1:19090/api/v1/targets'
```

Przeładowanie konfiguracji bez restartu:

```bash
curl --fail --request POST http://127.0.0.1:19090/-/reload
```

Dane Prometheusa znajdują się w nazwanym wolumenie:

```bash
docker volume inspect binturo_dev_prometheus_data
docker system df -v
```

Nie wykonuj `docker compose down --volumes`, ponieważ usunęłoby to historię metryk.

## Caddy

Caddy jest systemową usługą, niezależną od rootless Docker.

```bash
sudo systemctl status caddy.service
sudo systemctl start caddy.service
sudo systemctl stop caddy.service
sudo systemctl restart caddy.service
```

Przed przeładowaniem zawsze zweryfikuj pełną konfigurację:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl reload caddy.service
```

Formatowanie pliku dynamicznego:

```bash
sudo caddy fmt --overwrite /etc/caddy/sites-enabled/nazwa.caddy
```

Pliki `10-platform.caddy`, `20-organizers-staff.caddy`,
`21-organizers-trainer.caddy` i `22-organizers-client.caddy` są zarządzane przez
Ansible i nie
powinny być edytowane ręcznie. Dodatkowe pliki dynamiczne muszą mieć inne nazwy.

Frontendy są statycznymi buildami npm i nie mają osobnych usług systemd. Caddy
udostępnia frontend platform przez jego domenę, a frontendy organizers dodatkowo
na osobnych portach loopback: `staff` 18201, `trainer` 18202 i `client` 18203. Caddy
serwuje je domyślnie z:

```text
/srv/binturo/apps/frontend-platform
/srv/binturo/apps/frontend-organizers/staff
/srv/binturo/apps/frontend-organizers/trainer
/srv/binturo/apps/frontend-organizers/client
```

Kontrola plików i uprawnień:

```bash
sudo -u caddy test -r /srv/binturo/apps/frontend-platform/index.html
sudo -u caddy test -r /srv/binturo/apps/frontend-organizers/staff/index.html
sudo -u caddy test -r /srv/binturo/apps/frontend-organizers/trainer/index.html
sudo -u caddy test -r /srv/binturo/apps/frontend-organizers/client/index.html

curl --fail http://127.0.0.1:18201/
curl --fail http://127.0.0.1:18202/
curl --fail http://127.0.0.1:18203/
```

Logi dostępu są zapisywane osobno w formacie JSON i rotowane codziennie o północy
czasu lokalnego. Ansible zachowuje maksymalnie 31 plików nie starszych niż 31 dni:

```bash
sudo tail -f /var/log/caddy/platform.log
sudo tail -f /var/log/caddy/organizers-staff.log
sudo tail -f /var/log/caddy/organizers-trainer.log
sudo tail -f /var/log/caddy/organizers-client.log
sudo ls -lah /var/log/caddy
```

Logi operacyjne Caddy, w tym błędy startu, konfiguracji i TLS, pozostają w
`journald`:

```bash
sudo journalctl -u caddy.service -n 200 --no-pager
sudo journalctl -u caddy.service --since '30 minutes ago'
sudo journalctl -u caddy.service -f
```

Sprawdzenie listenerów i odpowiedzi HTTPS:

```bash
sudo ss -lntp | grep -E '(:443|:2019)'
sudo ss -lnt6p | grep ':443'
curl --head https://twoja-domena.example
```

Listener IPv6 Caddy jest zwykle widoczny jako `[::]:443` albo `*:443`. Sprawdzenie
adresu, routingu i reguł IPv6:

```bash
ip -6 address show scope global
ip -6 route
grep '^IPV6=' /etc/default/ufw
sudo ufw status verbose
curl -6 --head https://twoja-domena.example
```

Konfiguracja witryn zawiera `bind 0.0.0.0 [::]`, dlatego `ss -lnt4p` i
`ss -lnt6p` powinny pokazać port 443 niezależnie od wartości
`net.ipv6.bindv6only`.

Port administracyjny `127.0.0.1:2019` nie może być wystawiony publicznie.

Na produkcji Caddy używa plików Cloudflare Origin CA:

```text
/etc/caddy/certs/cloudflare-origin.pem
/etc/caddy/certs/cloudflare-origin.key
```

Kontrola certyfikatu i uprawnień bez wyświetlania klucza prywatnego:

```bash
sudo openssl x509 -in /etc/caddy/certs/cloudflare-origin.pem -noout -subject -issuer -dates -ext subjectAltName
sudo stat -c '%U:%G %a %n' /etc/caddy/certs/cloudflare-origin.pem /etc/caddy/certs/cloudflare-origin.key
```

Cloudflare powinien używać `Full (strict)`. Certyfikat Origin CA nie jest publicznie
zaufany, dlatego bezpośredni test origin z pominięciem Cloudflare może zgłosić błąd
zaufania certyfikatu.

### Prawdziwy adres klienta za Cloudflare

Dla ruchu API z oficjalnych zakresów Cloudflare backend otrzymuje:

```text
X-Real-IP: <adres klienta>
X-Forwarded-For: <adres klienta>
CF-Connecting-IP: <adres klienta>
```

Backend powinien akceptować proxy headers wyłącznie od `127.0.0.1`, ponieważ tylko
lokalny Caddy łączy się z aplikacją. Przykład dla Uvicorn:

```bash
uvicorn app:app --host 127.0.0.1 --port 18101 --proxy-headers --forwarded-allow-ips 127.0.0.1
```

Przykład dla Flask/Werkzeug:

```python
from werkzeug.middleware.proxy_fix import ProxyFix

app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
```

Aktualne zakresy porównuj z oficjalnymi listami:

```text
https://www.cloudflare.com/ips-v4/
https://www.cloudflare.com/ips-v6/
```

## SSH, Fail2Ban i UFW

```bash
sudo sshd -t
sudo systemctl status ssh.socket ssh.service fail2ban.service
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo ufw status verbose
sudo ss -lntup
```

Logi:

```bash
sudo journalctl -u ssh.service -u ssh.socket -n 200 --no-pager
sudo journalctl -u fail2ban.service -n 200 --no-pager
sudo journalctl -u fail2ban.service -f
```

Restart Fail2Ban:

```bash
sudo systemctl restart fail2ban.service
```

Nie zatrzymuj ani nie restartuj SSH podczas jedynej aktywnej sesji bez dostępu do
konsoli awaryjnej VPS. Zmiany SSH wykonuj przez Ansible i pozostaw otwartą drugą,
sprawdzoną sesję.

## Szybka diagnostyka całego hosta

```bash
sudo systemctl --failed
sudo journalctl -p err..alert --since today
sudo ufw status verbose
sudo ss -lntup
df -h
free -h
```

Następnie jako `binturo`, z ustawionym `DOCKER_HOST`:

```bash
docker ps -a
docker stats --no-stream
docker system df
docker network ls
docker volume ls
```

Po ręcznej interwencji uruchom odpowiedni playbook Ansible w `--check --diff`, aby
wykryć rozbieżność konfiguracji względem repozytorium.

## Całkowite usunięcie środowiska Binturo z hosta

Poniższa procedura jest **nieodwracalna**. Usuwa kontenery, sieci, wolumen metryk,
pliki aplikacji oraz bazę PostgreSQL znajdującą się w
`/srv/binturo/persistent/postgres`. Przed rozpoczęciem wykonaj i skopiuj na inny
host co najmniej backup PostgreSQL, potrzebne metryki, pliki współdzielone i
konfigurację aplikacji.

Nie usuwaj całego `/srv`. Jest to standardowy katalog danych usług i może zawierać
zasoby niezwiązane z Binturo. Zakresem tej instalacji jest wyłącznie dokładna
ścieżka `/srv/binturo`.

Preferowanym sposobem jest skrypt `scripts/remove-binturo.sh`. Najpierw skopiuj go
na host i uruchom bez `--execute`, aby zobaczyć zakres operacji:

```bash
chmod 0755 remove-binturo.sh
./remove-binturo.sh --environment dev
```

Po wykonaniu i zweryfikowaniu backupu poza hostem uruchom świadomie:

```bash
sudo ./remove-binturo.sh \
  --environment dev \
  --execute \
  --backup-confirmed \
  --stop-caddy
```

Skrypt wymaga dodatkowo ręcznego wpisania `DELETE /srv/binturo`. Opcję
`--stop-caddy` pomiń, jeżeli Caddy obsługuje także inne witryny. Dalsza część tego
rozdziału opisuje te same kroki ręcznie i służy również do diagnostyki.

### 1. Ustal środowisko i sprawdź zakres

W dalszych poleceniach użyj `dev`, `staging` albo `prod`. Przykład dla `dev`:

```bash
readonly BINTURO_ENVIRONMENT=dev
readonly BINTURO_ROOT=/srv/binturo
readonly BINTURO_USER=binturo
readonly BINTURO_UID=1500

test "$(realpath -m -- "$BINTURO_ROOT")" = /srv/binturo || {
  echo "Nieprawidłowa ścieżka — przerwano" >&2
  exit 1
}

sudo test -d /srv/binturo || {
  echo "/srv/binturo nie istnieje — przerwano" >&2
  exit 1
}

sudo find /srv/binturo -maxdepth 2 -mindepth 1 -xdev -print
```

Sprawdź projekty Compose przed usunięciem:

```bash
sudo -u binturo \
  XDG_RUNTIME_DIR=/run/user/1500 \
  DOCKER_HOST=unix:///run/user/1500/docker.sock \
  docker compose ls

sudo -u binturo \
  XDG_RUNTIME_DIR=/run/user/1500 \
  DOCKER_HOST=unix:///run/user/1500/docker.sock \
  docker ps -a
```

Jeżeli UID użytkownika `binturo` jest inny niż `1500`, przerwij i popraw
`BINTURO_UID`, `XDG_RUNTIME_DIR` oraz `DOCKER_HOST` zgodnie z wynikiem:

```bash
id binturo
```

### 2. Zatrzymaj usługi systemowe

```bash
sudo systemctl stop binturo-platform.service binturo-organizers.service
sudo systemctl disable binturo-platform.service binturo-organizers.service
sudo systemctl stop caddy.service
```

Caddy jest zatrzymywany, ponieważ po usunięciu frontendów jego konfiguracja nadal
wskazywałaby na nieistniejące pliki. Nie usuwaj Caddy, jeśli obsługuje również
inne witryny.

### 3. Usuń projekty Compose Binturo

Uruchom powłokę użytkownika rootless Docker:

```bash
sudo -iu binturo
export XDG_RUNTIME_DIR=/run/user/1500
export DOCKER_HOST=unix:///run/user/1500/docker.sock
cd /srv/binturo/compose
```

Usuń monitoring razem z jego wolumenem metryk oraz PostgreSQL. Dane PostgreSQL są
bind mountem w `/srv/binturo`, więc samo `down --volumes` ich nie usuwa:

```bash
docker compose \
  --project-name "binturo-monitoring-${BINTURO_ENVIRONMENT}" \
  --file compose.monitoring.yml \
  down --volumes --remove-orphans

docker compose \
  --project-name "binturo-${BINTURO_ENVIRONMENT}" \
  --file compose.postgres.yml \
  down --volumes --remove-orphans

docker ps -a
docker network ls
docker volume ls
exit
```

Po `docker ps -a` nie powinny pozostać kontenery `binturo-*`. Jeżeli pozostały,
nie usuwaj ich w ciemno — sprawdź `docker inspect NAZWA_KONTENERA` i ustal, z
którego projektu pochodzą.

### 4. Opcjonalnie wyczyść wszystkie nieużywane zasoby rootless Docker

Ten krok może usunąć obrazy, cache i wolumeny niezwiązane z Binturo. Wykonaj go
tylko wtedy, gdy konto `binturo` jest przeznaczone wyłącznie dla tej instalacji i
wcześniejsze listy `docker ps -a`, `docker volume ls` oraz `docker network ls`
zostały sprawdzone:

```bash
sudo -u binturo \
  XDG_RUNTIME_DIR=/run/user/1500 \
  DOCKER_HOST=unix:///run/user/1500/docker.sock \
  docker system prune --all --volumes --force
```

Polecenie usuwa tylko zasoby nieużywane. Nie usuwa działających kontenerów, dlatego
znane projekty Compose są zatrzymywane i usuwane w poprzednim kroku.

### 5. Zatrzymaj rootless Docker i usuń katalog Binturo

```bash
sudo -u binturo \
  XDG_RUNTIME_DIR=/run/user/1500 \
  systemctl --user stop docker.service

test "$(realpath -m -- /srv/binturo)" = /srv/binturo || {
  echo "Nieprawidłowa ścieżka — przerwano" >&2
  exit 1
}

sudo rm -rf --one-file-system -- /srv/binturo
sudo test ! -e /srv/binturo
```

Ostatnie polecenie powinno zakończyć się sukcesem. Nie zastępuj `/srv/binturo`
zmienną, globem, `/srv` ani ścieżką obliczaną dynamicznie.

### 6. Weryfikacja

```bash
sudo systemctl status binturo-platform.service binturo-organizers.service
sudo systemctl status caddy.service
sudo test ! -e /srv/binturo && echo "Katalog Binturo usunięty"

sudo -u binturo \
  XDG_RUNTIME_DIR=/run/user/1500 \
  systemctl --user is-active docker.service
```

Ostatnie polecenie powinno zwrócić `inactive`. Status zatrzymanych usług systemd
może zwrócić kod różny od zera; w tej procedurze jest to oczekiwane.

Jednostki systemd, konfiguracja Caddy, pakiety Docker/Caddy i konto `binturo`
pozostają na hoście. Ich usuwanie jest osobną operacją systemową. Ponowne
uruchomienie `03-site.yml` odtworzy `/srv/binturo`, konfigurację Compose i włączy
usługi zgodnie z Ansible.
