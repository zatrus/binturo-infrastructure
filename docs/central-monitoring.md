# Centralny monitoring

Serwer `binturo-monitoring` nie wymaga publicznego adresu. Obecnie łączy się
przez SSH tylko ze stagingiem raz na dobę. Lokalny Prometheus cały czas zbiera
metryki. Każdy transfer pobiera pełną migawkę TSDB, a Grafana odczytuje
centralną kopię stagingu. Grafana jest dostępna przez prywatny adres
`http://10.0.0.2:3000`.
Produkcję można dodać później do `central_monitoring_sources`.

Prometheus na stagingu odpytuje cele co **15 sekund**: tę wartość ustawia
`global.scrape_interval` w `roles/monitoring/templates/prometheus.yml.j2`.
Dotyczy to także jobów `binturo-platform` i `binturo-organizers`, które nie
ustawiają własnego interwału. Osobny timer przenosi migawkę na `kirisek` raz
na dobę o 03:00. Odświeżanie dashboardu Grafany nie zmienia częstotliwości
zbierania metryk.

## Przygotowanie

### Kirisek: Ubuntu 22.04 z `docker.io 29.1.3`

To jest ścieżka dla obecnego serwera `kirisek`. Nie uruchamiaj poleceń z
pozostałych wariantów pakietów poniżej. Pakiet Ubuntu na tym serwerze nie
zawiera instalatora rootless. Istniejący demon `docker.io` obsługuje działający
PostgreSQL, więc pozostaje uruchomiony. Rootless Docker instalujemy osobno w
katalogu domowym `binturo`.

**Strefa czasu serwera.** Administrator `kirisek` ustawia ją jednorazowo jako
`root` (konto `binturo` nie ma wymaganego `sudo`):

```bash
timedatectl set-timezone Europe/Warsaw
timedatectl status
date
```

Po zmianie zaloguj się nową sesją jako `binturo` i sprawdź termin kolejnej
synchronizacji:

```bash
systemctl --user list-timers binturo-monitoring-sync.timer
systemd-analyze calendar '*-*-* 03:00:00'
```

`central_monitoring_schedule: "*-*-* 03:00:00"` będzie oznaczał godzinę
03:00 czasu `Europe/Warsaw`, również po zmianie między CET i CEST. Zmiana
strefy nie zmienia znaczników czasu już zapisanych metryk.

**1. Jako `root` doinstaluj wymagane narzędzia i Compose:**

```bash
apt-get update
apt-get install -y uidmap slirp4netns dbus-user-session docker-compose-v2 curl
```

**2. Jako `root` przygotuj konto i katalog:**

```bash
getent passwd binturo
grep '^binturo:' /etc/subuid
grep '^binturo:' /etc/subgid
loginctl enable-linger binturo
install -d -o binturo -g binturo -m 0700 /data/binturo/binturo-monitoring
```

Wpisy `/etc/subuid` i `/etc/subgid` muszą przydzielać po co najmniej 65536
identyfikatorów. Jeśli ich brak, administrator musi przydzielić wolne,
niepokrywające się zakresy. Nie zgaduj ich numerów na serwerze z innymi
kontami. [Wymagania rootless](https://docs.docker.com/engine/security/rootless/).

**3. Wyloguj się z roota i zaloguj nową sesją SSH jako `binturo`:**

```bash
id -un
curl -fsSL https://get.docker.com/rootless -o "$HOME/docker-rootless-install.sh"
less "$HOME/docker-rootless-install.sh"
FORCE_ROOTLESS_INSTALL=1 sh "$HOME/docker-rootless-install.sh"
export PATH="$HOME/bin:$PATH"
systemctl --user enable --now docker.service
DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock" docker info --format '{{json .SecurityOptions}}'
DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock" docker compose version
test -w /data/binturo/binturo-monitoring
```

W `SecurityOptions` powinno wystąpić `rootless`. Jeżeli któryś test się nie
powiedzie, nie uruchamiaj jeszcze playbooka. Instalator statyczny wymaga
ręcznych aktualizacji; jego użycie obok działającego demona i parametr
`FORCE_ROOTLESS_INSTALL=1` opisuje [Docker](https://docs.docker.com/engine/security/rootless/).

**4. Z kontrolera Ansible uruchom centralny playbook** po uzupełnieniu
inventory i Vault zgodnie z dalszymi krokami tej instrukcji:

```bash
ansible-playbook -i inventories/monitoring/hosts.yml playbooks/central-monitoring.yml --ask-vault-pass
```

Konto `binturo` nie potrzebuje `sudo` do kroku 4.

### Zmiana katalogu rootless Docker po instalacji

Poniższe polecenia wykonuj w sesji SSH użytkownika `binturo`. Instalator
statyczny zapisuje pliki wykonywalne domyślnie w `~/bin`, a demon przechowuje
obrazy, kontenery i wolumeny domyślnie w `~/.local/share/docker`. Są to dwie
osobne lokalizacje. Przed zmianą sprawdź dane **rootless** przez jego gniazdo:

```bash
export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
docker ps -a
docker volume ls
docker info --format '{{.DockerRootDir}}'
```

Jeżeli rootless Docker ma kontenery lub wolumeny do zachowania, nie usuwaj
dotychczasowego katalogu danych. Potrzebna będzie ich osobna migracja.
Jeśli dopiero zainstalowano demon i nie ma w nim potrzebnych danych, można
odtworzyć jego usługę z nową lokalizacją. Przykład używa dysku `/data`:

```bash
"$HOME/bin/dockerd-rootless-setuptool.sh" uninstall
install -d -m 0700 /data/binturo/binturo-monitoring/docker-bin
install -d -m 0700 /data/binturo/binturo-monitoring/docker-data
install -d -m 0700 "$HOME/.config/docker"
```

W pliku `~/.config/docker/daemon.json` ustaw `data-root`. Jeśli plik już
istnieje, dodaj tę właściwość do obecnego JSON zamiast nadpisywać pozostałe
ustawienia:

```json
{
  "data-root": "/data/binturo/binturo-monitoring/docker-data"
}
```

Następnie zainstaluj pliki wykonywalne w wybranym katalogu. `DOCKER_BIN`
steruje ich lokalizacją, a `data-root` lokalizacją danych demona:

```bash
DOCKER_BIN=/data/binturo/binturo-monitoring/docker-bin \
  FORCE_ROOTLESS_INSTALL=1 sh "$HOME/docker-rootless-install.sh"
export PATH="/data/binturo/binturo-monitoring/docker-bin:$PATH"
systemctl --user enable --now docker.service
docker info --format '{{.DockerRootDir}}'
docker info --format '{{json .SecurityOptions}}'
docker compose version
```

Pierwszy wynik powinien wskazywać `/data/binturo/binturo-monitoring/docker-data`,
a drugi zawierać `rootless`. Dotychczasowe `~/bin` i
`~/.local/share/docker` pozostają jako kopia do ręcznego przeglądu; instalator
`uninstall` usuwa usługę użytkownika, ale nie kasuje plików wykonywalnych ani
danych. [Odinstalowanie rootless Docker](https://docs.docker.com/engine/security/rootless/troubleshoot/),
[konfiguracja `data-root`](https://docs.docker.com/engine/daemon/),
[domyślne katalogi](https://docs.docker.com/engine/security/rootless/tips/).

Playbook centralny działa na `kirisek` jako konto SSH `binturo` bez `sudo`.
Nie instaluje pakietów
systemowych ani nie zarządza systemowym Dockerem. Administrator serwera musi
jednorazowo przygotować dla tego konta rootless Docker z Compose, zakresy
`/etc/subuid` i `/etc/subgid`, trwałą usługę użytkownika (`loginctl enable-linger
<konto>`) oraz katalog danych wskazany przez `central_monitoring_root` z prawem
zapisu dla tego konta. Domyślnie jest to `/data/binturo/binturo-monitoring`.
Konto `binturo` na serwerze centralnym nie powinno należeć do grupy `docker` systemowego demona;
uprawnienie do tego demona jest równoważne szerokiemu dostępowi do hosta.

Polecenia `systemctl --user` trzeba wykonywać **po zalogowaniu przez SSH na
dedykowane konto**, a nie z powłoki `root` ani przez `sudo -u`. W powłoce roota
brakuje zwykle sesji i zmiennych `XDG_RUNTIME_DIR` oraz `DBUS_SESSION_BUS_ADDRESS`
tego użytkownika. Również `test -w` uruchomiony jako root nie sprawdza uprawnień
konta `binturo`.

### Pakiety na Ubuntu 22.04 i 24.04

Poniższe polecenia wykonuje administrator jako `root`. Dla **nowego hosta**
zalecany jest jeden, spójny zestaw pakietów z oficjalnego repozytorium Docker:

```bash
apt-get update
apt-get install -y ca-certificates curl uidmap slirp4netns dbus-user-session
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
docker compose version
command -v dockerd-rootless-setuptool.sh
```

Jeśli Docker jest już zainstalowany, **nie instaluj `docker-ce` obok
`docker.io`**. Najpierw ustal, skąd pochodzi obecny pakiet. Polecenia
diagnostyczne można wykonać również jako zwykły użytkownik:

```bash
cat /etc/os-release
dpkg-query -W -f='${Package} ${Version}\n' docker.io docker-ce docker-ce-cli docker-ce-rootless-extras docker-compose-v2 docker-compose-plugin 2>/dev/null || true
apt-cache policy docker.io docker-ce docker-compose-v2 docker-compose-plugin docker-ce-rootless-extras
command -v dockerd-rootless-setuptool.sh || true
ls -l /usr/share/docker.io/contrib/dockerd-rootless-setuptool.sh 2>/dev/null || true
```

W wariancie `docker.io` doinstaluj poniższe pakiety **tylko wtedy, gdy
instalator rootless z tego pakietu rzeczywiście istnieje**:

```bash
apt-get update
apt-get install -y docker-compose-v2 uidmap slirp4netns rootlesskit dbus-user-session
docker compose version
```

Na Ubuntu 22.04 pakiet `docker.io` w wersji `29.1.3-0ubuntu3~22.04.2`
nie zawiera instalatora rootless. Samo doinstalowanie `rootlesskit`, `uidmap`
i Compose nie tworzy usługi `docker.service` użytkownika. Jeśli instalatora
nie ma ani w `PATH`, ani pod `/usr/share/docker.io/contrib/`, zatrzymaj się
na tym etapie i użyj opisanej wyżej ścieżki `kirisek`, która zachowuje
istniejący demon. Migracja systemowego Dockera do Docker CE może przerwać
działające kontenery i wymaga odrębnego planu.
[Instalacja Docker na
Ubuntu](https://docs.docker.com/engine/install/ubuntu/), [wtyczka
Compose](https://docs.docker.com/compose/install/linux/), [tryb
rootless](https://docs.docker.com/engine/security/rootless/).

Administrator sprawdza, czy konto ma co najmniej 65536 przypisanych UID i GID:

```bash
grep '^<konto>:' /etc/subuid
grep '^<konto>:' /etc/subgid
```

Jeżeli wpisów brakuje, administrator musi przydzielić wolne, niepokrywające
się zakresy. Instalator rootless zgłosi ich brak. Po przygotowaniu zakresów
administrator wykonuje:

```bash
loginctl enable-linger <konto>
install -d -o <konto> -g <konto> -m 0700 /data/binturo/binturo-monitoring
```

Następnie zaloguj się przez SSH jako `<konto>`. Uruchom **tylko jeden**
instalator, który rzeczywiście istnieje na serwerze:

```bash
if command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
  dockerd-rootless-setuptool.sh install --force
elif test -x /usr/share/docker.io/contrib/dockerd-rootless-setuptool.sh; then
  /usr/share/docker.io/contrib/dockerd-rootless-setuptool.sh install --force
else
  echo 'Brak instalatora rootless: wróć do kroku z pakietami' >&2
fi
```

Dopiero po **udanym** utworzeniu jednostki `docker.service` włącz ją:

```bash
systemctl --user enable --now docker.service
```

Jeżeli serwer nie ma systemowego demona Docker, `--force` można pominąć.
Sprawdź w tej samej sesji użytkownika przed uruchomieniem Ansible:

```bash
id -un
systemctl --user status docker.service
DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock" docker compose version
test -w /data/binturo/binturo-monitoring
```

1. Ustaw adres i konto SSH serwera centralnego w
   `inventories/monitoring/hosts.yml`. Serwer musi mieć dostęp wychodzący do
   portu SSH stagingu. Ustaw poprawny adres i port w
   `inventories/monitoring/group_vars/all/vars.yml`.
2. Utwórz `inventories/monitoring/group_vars/all/vault.yml` na podstawie
   `inventories/monitoring/vault.example.yml`, ustaw hasło administratora
   Grafany (co najmniej 12 znaków) i zaszyfruj plik Ansible Vault. W YAML
   zapisz hasło w cudzysłowie, również gdy składa się wyłącznie z cyfr;
   inaczej YAML potraktuje je jako liczbę. Nie zapisuj hasła w Git.
3. Na kontrolerze Ansible uruchom:

   ```bash
   ansible-playbook -i inventories/monitoring/hosts.yml playbooks/central-monitoring.yml --ask-vault-pass
   ```

   Playbook uruchamia Grafanę w rootless Docker, tworzy klucz SSH i włącza
   timer użytkownika.
4. Odczytaj klucz publiczny z `~/.ssh/binturo-monitoring-ed25519.pub` na
   serwerze centralnym. Wstaw go jako `central_monitoring_public_key` w
   zmiennych stagingu, po czym uruchom stagingowy `03-site.yml`.
   Klucz jest instalowany w `authorized_keys` użytkownika `binturo`, który
   uruchamia rootless Docker i lokalnego Prometheusa. Ansible loguje się na
   staging jako `binturo_s`, a na produkcję jako `binturo_p`; te konta
   służą do wdrożenia, nie do synchronizacji. Klucz dostaje ograniczenie SSH:
   może wywołać tylko eksport migawki.

   Klucz tworzy automatycznie playbook centralny podczas zadania
   `Generate central SSH key`; nie trzeba uruchamiać `ssh-keygen` ręcznie. Przy
   domyślnej konfiguracji i koncie `binturo` pliki są na serwerze centralnym:
   `/home/binturo/.ssh/binturo-monitoring-ed25519` (prywatny) oraz
   `/home/binturo/.ssh/binturo-monitoring-ed25519.pub` (publiczny). Jako
   `binturo` sprawdź i wyświetl **wyłącznie klucz publiczny**:

   ```bash
   ls -l "$HOME/.ssh/binturo-monitoring-ed25519" "$HOME/.ssh/binturo-monitoring-ed25519.pub"
   cat "$HOME/.ssh/binturo-monitoring-ed25519.pub"
   ```

   Skopiuj całą pojedynczą linię zaczynającą się od `ssh-ed25519` do
   `inventories/staging/group_vars/all/vars.yml` na kontrolerze Ansible:

   ```yaml
   central_monitoring_public_key: "ssh-ed25519 AAAA... binturo@kirisek"
   ```

   Zastąp przykład rzeczywistą linią z pliku `.pub`. Klucza prywatnego nie
   kopiuj i nie zapisuj w repozytorium. Następnie na kontrolerze uruchom
   z normalnymi parametrami dostępu Ansible dla stagingu:

   ```bash
   ansible-playbook -i inventories/staging/hosts.yml 03-site.yml --ask-vault-pass
   ```

   Klucz publiczny zostanie zainstalowany na koncie `binturo` stagingu.
5. Na serwerze centralnym dodaj zweryfikowany klucz hosta stagingu do
   `~/.ssh/known_hosts` konta `binturo` na `kirisek`. Zweryfikuj
   fingerprinty niezależnie;
   skrypt wymaga `StrictHostKeyChecking=yes`.
6. Po zalogowaniu przez SSH na `kirisek` jako `binturo` uruchom synchronizację
   i sprawdź jej dziennik:

   ```bash
   systemctl --user start binturo-monitoring-sync.service
   journalctl --user -u binturo-monitoring-sync.service -n 100 --no-pager
   ```

7. Otwórz Grafanę z urządzenia mającego dostęp do prywatnej sieci:

   ```text
   http://10.0.0.2:3000
   ```

   Mapowanie portu jest związane tylko z adresem `10.0.0.2`, określonym przez
   `central_monitoring_grafana_bind_address` w inventory. Administrator hosta
   powinien dopuścić TCP/3000 jedynie z wybranych adresów lub podsieci tej
   sieci. Playbook nie zmienia zapory systemowej, bo konto Ansible nie ma
   uprawnień `sudo`. Grafana nadal wymaga logowania. Po zmianie IP uruchom
   ponownie centralny playbook, który odtworzy kontener z nowym mapowaniem.

### Weryfikacja kluczy SSH serwerów źródłowych

Jeśli synchronizacja kończy się komunikatem `No ED25519 host key is known`,
brakuje kroku 5. Na stagingu, po zalogowaniu zaufanym sposobem (np. przez
konsolę operatora), odczytaj odcisk klucza hosta:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Na serwerze centralnym, jako `binturo`, pobierz klucz na właściwym porcie SSH
do pliku tymczasowego i porównaj odcisk z odczytanym bezpośrednio na stagingu:

```bash
hostkey_dir=$(mktemp -d)
ssh-keyscan -p 4285 -t ed25519 146.59.3.169 > "$hostkey_dir/staging"
ssh-keygen -lf "$hostkey_dir/staging"
```

`ssh-keyscan` sam nie potwierdza tożsamości serwera. Dopiero gdy odciski są
zgodne, dopisz klucz do `known_hosts` konta `binturo`:

```bash
install -d -m 0700 "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts"
chmod 0600 "$HOME/.ssh/known_hosts"
cat "$hostkey_dir/staging" >> "$HOME/.ssh/known_hosts"
rm -r -- "$hostkey_dir"
systemctl --user start binturo-monitoring-sync.service
journalctl --user -u binturo-monitoring-sync.service -n 100 --no-pager
```

Komunikat `tar: This does not look like a tar archive` po błędzie weryfikacji
klucza jest skutkiem przerwanego połączenia SSH. Jeśli po dodaniu klucza
wystąpi błąd autoryzacji, sprawdź krok 4: publiczny klucz konta centralnego
musi być zainstalowany na stagingu z ograniczeniem do eksportu
migawki.

### `Connection refused` przy tworzeniu migawki

Jeśli dziennik synchronizacji pokazuje ślad z pliku
`prometheus-snapshot` i `Connection refused`, klucz
SSH zadziałał, ale skrypt na serwerze źródłowym nie połączył się z lokalnym
Prometheusem. Domyślnie skrypt wywołuje API na `127.0.0.1:19090`, zgodnie z
portem w `group_vars/all.yml`. Obecnie synchronizowany jest tylko staging.
Jeśli dziennik wskazuje `/srv/binturo/monitoring/prometheus-snapshot`,
jest to właściwa ścieżka stagingu przy obecnym `binturo_root`. Sprawdź
wdrożoną listę źródeł na `kirisek`:

```bash
cat /data/binturo/binturo-monitoring/sources.conf
```

Powinna zawierać tylko wiersz zaczynający się od `staging`. Jeśli zawiera
`prod`, uruchom ponownie playbook centralny z aktualnym repozytorium i ponów
sprawdzenie. Jeśli zawiera tylko `staging`, sprawdź lokalnego Prometheusa.
Na stagingu zaloguj się na konto `binturo` i uruchom:

```bash
export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
docker ps -a --filter name=binturo-prometheus
docker logs --tail 100 binturo-prometheus
curl -v http://127.0.0.1:19090/-/ready
```

Jeśli kontener jest zatrzymany albo go nie ma, uruchom stagingowy playbook
`03-site.yml` i sprawdź zadanie `Start monitoring stack`. Jeśli kontener działa,
ale `curl` nadal zwraca odmowę połączenia, sprawdź mapowanie portu oraz logi
kontenera. Nie uruchamiaj ręcznie nowego Prometheusa z innym wolumenem danych.
Komunikat `open /etc/prometheus/prometheus.yml: permission denied` oznacza, że
plik konfiguracji na stagingu nie jest czytelny dla procesu Prometheusa
(UID 65534 w kontenerze). Rola `monitoring` instaluje go z uprawnieniami
`0644`. Po wdrożeniu aktualnego repozytorium sprawdź uprawnienia i stan API:

```bash
stat -c '%a %U:%G %n' /srv/binturo/monitoring/prometheus.yml
docker ps -a --filter name=binturo-prometheus
curl -fsS http://127.0.0.1:19090/-/ready
```

W obecnym wariancie `remote_write` jest wyłączone, a hasło eksportera
PostgreSQL znajduje się w osobnym katalogu `secrets`. Jeśli później włączysz
`remote_write` z hasłem, trzeba przenieść jego sekret poza czytelny dla
wszystkich plik `prometheus.yml`. Nie zmieniaj ręcznie uprawnień całego
katalogu `secrets`.

Po przywróceniu odpowiedzi API ponów synchronizację na `kirisek`:

```bash
systemctl --user start binturo-monitoring-sync.service
journalctl --user -u binturo-monitoring-sync.service -n 100 --no-pager
```

Po późniejszym dodaniu produkcji ta sama diagnostyka będzie dotyczyć również jej.

## Po zalogowaniu do Grafany

Playbook tworzy źródło danych `Prometheus staging`, ale przy pierwszym
wdrożeniu uruchamia tylko Grafanę. Kontener Prometheusa powstaje dopiero po
udanym pobraniu migawki z kroku 6. Przed pierwszą synchronizacją zapytanie
w Grafanie może zwrócić błąd DNS
`lookup prometheus-staging ... server misbehaving`.
Na serwerze centralnym, w sesji SSH konta `binturo`, sprawdź i uruchom:

```bash
export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"
docker compose -f /data/binturo/binturo-monitoring/compose.yml -p binturo-central-monitoring ps -a
systemctl --user status binturo-monitoring-sync.timer
systemctl --user start binturo-monitoring-sync.service
journalctl --user -u binturo-monitoring-sync.service -n 100 --no-pager
docker compose -f /data/binturo/binturo-monitoring/compose.yml -p binturo-central-monitoring ps -a
```

Kontener `prometheus-staging` powinien mieć stan `running`. Jeśli pierwszy
przebieg się nie udał, sprawdź w `journalctl`
przyczynę: uprawnienie klucza na serwerze źródłowym, wpis w `known_hosts`,
łączność SSH albo dostępne miejsce. Samo ponowienie zapytania w Grafanie nie
uruchomi synchronizacji. Po udanym przebiegu otwórz w Grafanie
**Connections → Data sources**, sprawdź źródło przez **Save & test**,
a następnie w **Explore** wykonaj zapytanie `up`.

`up` pokazuje stan celów Prometheusa w pobranej migawce. Nie jest to podgląd
bieżącego stanu stagingu między synchronizacjami.

### Dashboardy Grafany

Playbook kopiuje siedem dashboardów z
`roles/central_monitoring/files/dashboards/` do katalogu na `kirisek` i
udostępnia je Grafanie przez provisioning plikowy. Po ponownym uruchomieniu
centralnego playbooka są dostępne w folderze **Binturo**:

| Dashboard | Zakres |
| --- | --- |
| Stan stagingu | Wiek ostatniej próbki, ostatni znany stan celów, błędy 5xx, cron i dysk |
| Zasoby hosta i bazy | CPU, pamięć, dyski, sieć, połączenia, rozmiar baz i transakcje PostgreSQL |
| Backend i HTTP | Ruch, p50/p95/p99, błędy oraz najczęstsze trasy obu backendów |
| Wzrost platformy | Organizacje, plany, unikalni użytkownicy i członkostwa w organizacjach |
| Organizacje i zaangażowanie | Klienci, zajęcia, kadra, miejsca, aktywność i ruch według organizacji |
| Zapisy i komunikacja | Zapisy, płatności za zajęcia, wiadomości, webhooki i moderacja |
| Subskrypcje i płatności | Statusy, plany, wygaśnięcia, zdarzenia i kwoty płatności |

Na kontrolerze Ansible wdroż je poleceniem:

```bash
ansible-playbook -i inventories/monitoring/hosts.yml playbooks/central-monitoring.yml --ask-vault-pass
```

Grafana po wdrożeniu odczytuje dashboardy z plików JSON. Zmiany paneli
wprowadzaj w repozytorium i wdrażaj ponownie playbookiem; konfiguracja
`allowUiUpdates: false` blokuje zapisywanie zmian tych dashboardów w GUI.
Dashboardy wskazują źródło `prometheus-staging`. Ich panele biznesowe
wymagają, aby joby `binturo-platform` i `binturo-organizers` miały `up=1`.
Kafelek **Wiek ostatniej próbki** pokazuje opóźnienie kopii centralnej.
Kafelki „ostatni stan” szukają próbek z ostatnich 48 godzin; gdy nie było
udanej synchronizacji dłużej, pokazują brak danych. Wykresy czasowe pokazują
historię ze stagingu, nie bieżący stan serwera. Domyślny zakres 7 dni mieści
się w obecnej retencji lokalnego Prometheusa (10 dni lub 10 GB).
Kwoty `applied_mock` są wydzielone jako płatności testowe i nie oznaczają
przychodu. Dane o ruchu HTTP nie mierzą wykorzystania CPU/RAM przez
poszczególne kontenery; ten podział wymaga dodatkowych metryk kontenerów.
Źródłem dashboardów jest `scripts/build_monitoring_dashboards.py`; po zmianie
definicji paneli uruchom ten skrypt, a następnie playbook.
Oba backendy słuchają na `127.0.0.1`, dlatego lokalny Prometheus pobiera ich
metryki przez wewnętrzny listener Caddy na porcie `19091`, ze ścieżek
`/platform/metrics` i `/organizers/metrics`. Rootless Docker mapuje
`host.docker.internal` na `10.0.2.2`; plik
`docker.service.d/binturo-monitoring.conf` włącza dostęp kontenerów do
loopback hosta, a Caddy nasłuchuje na `127.0.0.1:19091`. Domyślne
`host-gateway` (`172.17.0.1`) wskazywało bramę sieci kontenera i zwracało
`connection refused`. Ta zmiana pozwala wszystkim kontenerom tego demona
rootless łączyć się z usługami hosta na loopback, dlatego nie należy
uruchamiać w nim niezaufanych kontenerów. Wdrożenie `03-site.yml` restartuje
rootless Docker, czyli także kontenery PostgreSQL i monitoringu; wykonaj je
w odpowiednim oknie serwisowym.

Po wdrożeniu stagingowego
`03-site.yml` sprawdź na stagingu:

```bash
pgrep -a rootlesskit
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:19091/platform/metrics
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:19091/organizers/metrics
DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock" docker exec binturo-prometheus wget -q -O /dev/null http://10.0.2.2:19091/metrics
curl -fsSG --data-urlencode 'query=up{job="binturo-platform"}' http://127.0.0.1:19090/api/v1/query
curl -fsSG --data-urlencode 'query=up{job="binturo-organizers"}' http://127.0.0.1:19090/api/v1/query
```

W wierszu RootlessKit nie powinno już być `--disable-host-loopback`.
Oba endpointy powinny zwrócić `200`, test z kontenera zakończyć się bez
błędu, a oba zapytania `up` pokazać wartość `1` po najbliższym scrape (15 s).
Następnie uruchom synchronizację na `kirisek`, aby centralny Prometheus dostał
nowe próbki. Okres, w którym backendy nie były scrape'owane, pozostanie
pusty; synchronizacja nie odtwarza historycznych metryk, których nie zebrał
lokalny Prometheus.

Centralna kopia jest aktualizowana tylko po synchronizacji, więc panel
**Stan stagingu** przedstawia stan w ostatniej migawce. Dane biznesowe
pozostają dostępne tylko w granicach retencji lokalnego Prometheusa
(obecnie 10 dni lub 10 GB).

### Gdzie są logi

Obecne wdrożenie centralne zbiera **metryki**, nie logi. Prometheus nie
przechowuje logów aplikacji, a w Grafanie nie ma jeszcze źródła danych typu
Loki. Samo otwarcie Grafany nie uruchamia zbierania logów.

Logi można teraz odczytać bezpośrednio na stagingu lub produkcji:

| Źródło | Polecenie na właściwym serwerze |
| --- | --- |
| Backend platformy, usługa | `sudo journalctl -u binturo-platform.service -n 100 --no-pager` |
| Backend organizatorów, usługa | `sudo journalctl -u binturo-organizers.service -n 100 --no-pager` |
| Backend platformy, plik aplikacji | `tail -n 100 /srv/binturo/apps/backend-platform/binturo_platform.log` |
| Backend organizatorów, plik aplikacji | `tail -n 100 /srv/binturo/apps/backend-organizers/binturo_organizers.log` |
| Caddy, żądania platformy | `sudo tail -n 100 /var/log/caddy/platform.log` |
| Caddy, żądania organizatorów | `sudo tail -n 100 /var/log/caddy/organizers.log` |
| Caddy, usługa | `sudo journalctl -u caddy.service -n 100 --no-pager` |

Ścieżki aplikacji wynikają z `binturo_root`, `platform_application_log_file`
i `organizers_application_log_file` w `group_vars/all.yml`. Jeśli inventory
nadpisuje te zmienne, użyj odpowiednich ścieżek. Pliki archiwalne backendów
są na stagingu w `/srv/binturo/logs/backend-platform/archive` i
`/srv/binturo/logs/backend-organizers/archive`; rotacja może przenieść wcześniejsze
wpisy poza aktywny plik.

Jeśli logi mają być przeszukiwane **w Grafanie**, trzeba wdrożyć osobny
magazyn Loki i kolektor Grafana Alloy dla wybranych plików lub journald,
a następnie dodać Loki jako źródło danych Grafany. Na serwerze centralnym bez
publicznego IP należy najpierw ustalić transport: dostęp przez prywatną sieć
(np. WireGuard) dla ciągłego przesyłania albo inicjowane z centrali pobieranie
logów przez SSH. Obecny klucz SSH służy wyłącznie do eksportu migawek
Prometheusa i nie daje dostępu do logów. Przed wdrożeniem pobierania trzeba
określić opóźnienie, retencję oraz uprawnienia do odczytu logów Caddy i
backendów. [Loki i Alloy](https://grafana.com/docs/loki/latest/send-data/alloy/),
[źródło Loki w Grafanie](https://grafana.com/docs/loki/latest/visualize/grafana/).

Harmonogram zmienia `central_monitoring_schedule` w składni `OnCalendar` systemd.
Przykłady: `*-*-* 03:00:00` oznacza raz dziennie o 03:00, a
`*-*-* 00,06,12,18:00:00` oznacza co 6 godzin. Przed wdrożeniem sprawdź
wyrażenie poleceniem `systemd-analyze calendar '<wyrażenie>'`. Po zmianie
uruchom ponownie centralny playbook. Timer systemd
ma `Persistent=true`, więc po wyłączeniu serwera wykona pominięty przebieg po
starcie. Ręczne uruchomienie usługi nie zmienia harmonogramu.

Każdy przebieg tworzy pełną migawkę lokalnego Prometheusa i przesyła ją przez
SSH. Na serwerze centralnym pobieranie odbywa się do osobnego katalogu; po
sprawdzeniu kopii odpowiedni Prometheus zostaje zatrzymany na czas zamiany
bazy. Kopia poprzedniej bazy służy do cofnięcia zamiany, jeśli nowy kontener
nie wystartuje. Grafana może mieć krótką przerwę w odczycie tego źródła.

Transfer pełnych migawek wymaga miejsca na serwerach źródłowych i centralnym.
Staging i prod powinny trzymać dane dłużej niż przewidywana przerwa w
synchronizacji; obecne ustawienie to 10 dni. Ustaw je wyżej, jeśli trzeba
przetrwać dłuższą niedostępność serwera centralnego. Centralna retencja wynosi
domyślnie 30 dni, ale codzienna zamiana całej bazy oznacza, że faktyczna
historia centralna nie przekroczy retencji źródła. Aby przechowywać dłuższą
historię centralnie, potrzebny będzie magazyn bloków lub inny proces importu.

Endpoint administracyjny lokalnego Prometheusa zostaje włączony wyłącznie na
API związanym z `127.0.0.1:19090`; przez SSH dostęp ma ograniczony klucz.
Nie publikuj tego portu ani portu 3000 na interfejsie publicznym.

## Późniejsze włączenie produkcji

Gdy będzie potrzebna synchronizacja produkcji, dopisz jej konfigurację do
`central_monitoring_sources` w
`inventories/monitoring/group_vars/all/vars.yml`:

```yaml
  prod:
    host: 51.68.151.77
    port: 2416
    user: binturo
```

Następnie dodaj centralny klucz publiczny jako `central_monitoring_public_key`
do `inventories/prod/group_vars/all/vars.yml`, uruchom produkcyjny
`03-site.yml`, zweryfikuj i dodaj klucz hosta produkcji do `known_hosts`
konta `binturo` na `kirisek`, po czym ponownie uruchom centralny playbook
i usługę synchronizacji. Kontener produkcji i jej źródło w Grafanie powstaną
po udanym pobraniu migawki. Wyłączenie produkcji z konfiguracji nie usuwa
wcześniej pobranych plików w `data/prod`.
