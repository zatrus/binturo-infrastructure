# Binturo infrastructure

Projekt Ansible przygotowuje dwa niezależne hosty Ubuntu: `dev` i `prod`. Każdy
host otrzymuje Caddy, rootless Docker, PostgreSQL, lokalny Prometheus oraz katalogi
dla:

- `binturo-platform`;
- `binturo-organizers`;
- statycznej strony WWW oraz czterech frontendów: platform i organizers
  `staff`, `trainer`, `client`;
- plików współdzielonych przez backendy.

Osobna, przenośna konfiguracja panelu Semaphore UI dla Ubuntu i Windows znajduje
się w [semaphore/README.md](semaphore/README.md). Panel korzysta z własnego
PostgreSQL i nie jest instalowany na hostach aplikacyjnych przez playbooki tego
projektu.

Projekt konfiguruje środowisko hosta. Nie implementuje procedury wdrażania aplikacji
ani GitHub Actions. Środowiska `dev` i `prod` znajdują się na różnych hostach i
korzystają z osobnych inventory oraz sekretów.

## Założenia architektury

- Ubuntu 24.04 lub nowsze;
- publicznie dostępne są wyłącznie `custom_ssh_port/tcp` i `443/tcp`, zarówno przez
  IPv4, jak i IPv6;
- Caddy działa jako usługa systemowa, bez listenera na porcie 80 i bez HTTP/3;
- Caddy wiąże HTTPS jawnie do `0.0.0.0:443` i `[::]:443`;
- kontenery działają przez rootless Docker użytkownika `binturo`;
- systemowe usługi `docker.service`, `docker.socket` i `containerd.service` są
  wyłączone i zamaskowane;
- PostgreSQL publikuje port wyłącznie na `127.0.0.1:5432`, aby lokalne backendy
  mogły łączyć się z bazą bez udostępniania jej publicznie;
- Prometheus publikuje API wyłącznie na `127.0.0.1:19090` i przechowuje dane
  lokalnie między okresowymi odczytami przez drugi serwer.

## Playbooki

Konfiguracja jest podzielona na trzy etapy:

1. `01-bootstrap.yml` — tworzy konto administratora, instaluje jego klucz SSH,
   uruchamia UFW i tymczasowo udostępnia początkowy oraz docelowy port SSH.
2. `02-hardening.yml` — wymaga połączenia nowym kontem na docelowym porcie,
   konfiguruje SSH i Fail2Ban oraz pozostawia w UFW tylko docelowy port SSH i
   `443/tcp`.
3. `03-site.yml` — konfiguruje właściwe środowisko: użytkownika systemowego,
   rootless Docker, Caddy, PostgreSQL, Prometheus, usługi backendów i strukturę
   katalogów aplikacji.

Rola `python_venvs` tworzy środowiska `venv` w katalogach
`apps/backend-organizers`, `apps/backend-platform`, `apps/www` i
`apps/frontend-platform`.
Trzy frontendy organizers znajdują się w `apps/frontend-organizers/{staff,trainer,client}`.
Domyślnie wykonuje
`python3 -m venv venv`. Interpreter można zmienić, ustawiając np. w zmiennych
środowiska:

```yaml
binturo_venv_python_executable: /usr/bin/python3.14
```

Wskazany interpreter musi mieć dostępny moduł `venv`. Istniejące środowisko nie
jest przebudowywane ani nadpisywane. Etap `03-site.yml` instaluje także pakiety
`build-essential`, `libpq-dev` i `python3.14-dev`, wymagane do kompilowania części
sterowników i zależności Pythona/PostgreSQL. Pakiet `python3.14-dev` musi być
dostępny w repozytoriach APT skonfigurowanych na hoście.

Rozdzielenie pierwszych dwóch etapów chroni przed utratą dostępu. Początkowy port
SSH jest usuwany dopiero po sprawdzeniu połączenia przez port docelowy.

## Przygotowanie kontrolera Ansible

Instrukcja utworzenia środowiska `.venv`, instalacji Pythona i Ansible oraz
bezpiecznej obsługi kluczy i Vault znajduje się w
[ANSIBLE_INSTALL.md](ANSIBLE_INSTALL.md).

Kontroler powinien działać w Linux lub WSL. Repozytorium najlepiej przechowywać w
systemie plików WSL, np. `~/projects/reservation-stack`. Przy domyślnym montowaniu
`/mnt/c` i `/mnt/d` katalog może być world-writable, przez co Ansible ignoruje
lokalny `ansible.cfg`. W takim przypadku przenieś projekt do WSL albo ustaw jawnie:

```bash
export ANSIBLE_CONFIG=/mnt/d/projects/reservation-stack/ansible.cfg
```

Zainstaluj wymagane kolekcje i sprawdź środowisko:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook --version
ansible-inventory -i inventories/dev/hosts.yml --graph
```

## Konfiguracja środowiska

Inventory definiuje dwa aliasy tego samego hosta:

- alias w `bootstrap_hosts` używa początkowego konta i portu operatora VPS;
- alias w `hardened_hosts` używa docelowego administratora i
  `custom_ssh_port`.

Dla produkcji użyj osobnego `inventories/prod`. Oba aliasy w obrębie jednego
inventory muszą wskazywać ten sam host, ale inventory `dev` i `prod` wskazują różne
serwery.

Najważniejsze zmienne w `inventories/<środowisko>/group_vars/all/vars.yml`:

```yaml
environment_name: dev
custom_admin_user: server_admin
custom_ssh_port: 2918
bootstrap_ssh_port: 22
custom_admin_authorized_key_file: /home/operator/.ssh/server_admin.pub
```

Port docelowy musi być w zakresie 1–65535 i różnić się od portu początkowego.
Portów aplikacji, PostgreSQL ani Prometheusa nie dodawaj do UFW — PostgreSQL i
Prometheus nasłuchują wyłącznie na loopback, a publiczny ruch aplikacyjny przechodzi
przez Caddy na `443/tcp`.

Sieć Docker PostgreSQL jest osobną siecią bridge, ale nie ma ustawienia
`internal: true`, ponieważ rootless Docker nie aktywował wtedy publikacji portu na
loopback. Dostęp zewnętrzny pozostaje zablokowany przez bind do `127.0.0.1` i UFW.

### Klucz SSH

`custom_admin_authorized_key_file` wskazuje plik klucza publicznego na kontrolerze.
Plik musi zawierać pojedynczy klucz OpenSSH, np.:

```text
ssh-ed25519 AAAA... opis
```

Klucza prywatnego nie zapisuj w inventory, Vault ani repozytorium. Przechowuj go
poza projektem, dodaj do `ssh-agent` albo przekaż przez
`--private-key /bezpieczna/sciezka/do/klucza`.

### Hasło sudo i Vault

Każde środowisko powinno mieć własny zaszyfrowany plik
`inventories/<środowisko>/group_vars/all/vault.yml` zawierający co najmniej:

```yaml
vault_ansible_become_password: bardzo_tajne_haslo
```

Utwórz go na podstawie przykładu i zaszyfruj:

```bash
cp inventories/dev/vault.example.yml inventories/dev/group_vars/all/vault.yml
ansible-vault encrypt inventories/dev/group_vars/all/vault.yml
```

Pliki `vault.yml` i `.vault-password` są ignorowane przez Git. Do poleceń używających
Vault dodawaj `--ask-vault-pass`. Hasło początkowego użytkownika można alternatywnie
podać interaktywnie przez `-K`.

## Procedura wykonania

Poniższe kroki są kanoniczną kolejnością uruchamiania projektu. W przykładach użyto
środowiska `dev`; dla produkcji zastąp ścieżkę przez `inventories/prod/hosts.yml` i
wykonaj procedurę na hoście produkcyjnym.

### 1. Czynności wykonywane tylko raz dla nowego hosta

1. Zainstaluj Ansible w `.venv`, aktywuj środowisko i zainstaluj kolekcje z
   `requirements.yml`.
2. Uzupełnij inventory, zmienne środowiska, publiczny klucz administratora i
   zaszyfrowany Vault.
3. Porównaj fingerprint hosta z konsolą operatora VPS i sprawdź połączenie
   początkowe:

   ```bash
   ansible bootstrap_hosts -i inventories/dev/hosts.yml -m ansible.builtin.ping
   ```

4. Sprawdź, a następnie wykonaj bootstrap:

   ```bash
   ansible-playbook -i inventories/dev/hosts.yml 01-bootstrap.yml --syntax-check
   ansible-playbook -i inventories/dev/hosts.yml 01-bootstrap.yml --ask-vault-pass --check --diff
   ansible-playbook -i inventories/dev/hosts.yml 01-bootstrap.yml --ask-vault-pass --diff
   ```

   Tryb `--check` nie przełącza listenerów SSH i nie potwierdza dostępności nowego
   portu.

5. Nie zamykając starej sesji ani konsoli awaryjnej, sprawdź w nowym terminalu
   logowanie na docelowym porcie oraz dostęp przez Ansible:

   ```bash
   ssh -p 2918 server_admin@ADRES_HOSTA
   ansible hardened_hosts -i inventories/dev/hosts.yml -m ansible.builtin.ping
   ansible hardened_hosts -i inventories/dev/hosts.yml -b -m ansible.builtin.command -a whoami --ask-vault-pass
   ```

6. Dopiero po udanym teście wykonaj finalny hardening:

   ```bash
   ansible-playbook -i inventories/dev/hosts.yml 02-hardening.yml --syntax-check
   ansible-playbook -i inventories/dev/hosts.yml 02-hardening.yml --ask-vault-pass --check --diff
   ansible-playbook -i inventories/dev/hosts.yml 02-hardening.yml --ask-vault-pass --diff
   ```

7. Skonfiguruj wszystkie usługi środowiska:

   ```bash
   ansible-playbook -i inventories/dev/hosts.yml 03-site.yml --syntax-check
   ansible-playbook -i inventories/dev/hosts.yml 03-site.yml --ask-vault-pass --check --diff
   ansible-playbook -i inventories/dev/hosts.yml 03-site.yml --ask-vault-pass --diff
   ```

8. Wykonaj weryfikację końcową:

   ```bash
   sudo ufw status verbose
   sudo systemctl status ssh.socket ssh.service fail2ban.service caddy.service
   sudo fail2ban-client status sshd
   sudo ss -lntup
   ```

   UFW powinien dopuszczać wyłącznie `custom_ssh_port/tcp` i `443/tcp` dla IPv4
   oraz IPv6. Port 22 nie powinien nasłuchiwać, chyba że jest równocześnie
   skonfigurowanym portem docelowym.

   UFW ma jawnie włączone `IPV6=yes`. Publiczny dostęp IPv6 wymaga również globalnego
   adresu IPv6 na hoście, trasy od operatora oraz — dla Cloudflare — poprawnego
   proxowanego rekordu AAAA.

### 2. Czynności wykonywane po zmianach konfiguracji

1. Zaktualizuj pliki Ansible i odpowiednie zmienne lub sekrety środowiska.
2. Sprawdź składnię wszystkich playbooków:

   ```bash
   ansible-playbook -i inventories/dev/hosts.yml 01-bootstrap.yml --syntax-check
   ansible-playbook -i inventories/dev/hosts.yml 02-hardening.yml --syntax-check
   ansible-playbook -i inventories/dev/hosts.yml 03-site.yml --syntax-check
   ```

3. Sprawdź plan zmian dla etapów wielokrotnego użytku:

   ```bash
   ansible-playbook -i inventories/dev/hosts.yml 02-hardening.yml --ask-vault-pass --check --diff
   ansible-playbook -i inventories/dev/hosts.yml 03-site.yml --ask-vault-pass --check --diff
   ```

4. Oceń diff, a następnie zastosuj konfigurację w tej kolejności:

   ```bash
   ansible-playbook -i inventories/dev/hosts.yml 02-hardening.yml --ask-vault-pass --diff
   ansible-playbook -i inventories/dev/hosts.yml 03-site.yml --ask-vault-pass --diff
   ```

5. Powtórz weryfikację UFW, SSH, Fail2Ban, Caddy i portów z punktu 8 procedury
   jednorazowej. `01-bootstrap.yml` nie jest ponownie wykonywany na skonfigurowanym
   hoście.

## Wysyłka e-maili przez backendy

Konfiguracja klientów `mock` i MailerSend, osobnych kluczy API backendów oraz
plików generowanych dla Jenkins jest opisana w
[docs/backend-email.md](docs/backend-email.md).

## PostgreSQL

Ansible tworzy:

- bazę `binturo_dev` albo `binturo_prod`;
- konto `binturo_platform_app` będące bezpośrednim właścicielem bazy,
  schematów i obiektów, z prawem tworzenia schematów oraz wykonywania DDL/DML;
- konto `binturo_organizers_app` bez praw DDL, z dostępem DML wyłącznie
  do dozwolonych schematów;
- konto `binturo_backup` z rolą `pg_read_all_data`;
- początkowy schemat `binturo_platform`.

Nazwa `binturo_platform_owner` jest zachowana jedynie jako zmienna
migracyjna. Bootstrap przenosi własność starych obiektów na
`binturo_platform_app` i odbiera członkostwo w dawnej roli.

`binturo-platform` pozostaje właścicielem migracji oraz dynamicznych schematów.
`binturo-organizers` korzysta z wielu schematów, ale ich tworzenie i aktualizacja
należą do `binturo-platform`. Zasady nadawania praw bezpośrednio po utworzeniu
schematu opisuje
[docs/postgresql-dynamic-schemas.md](docs/postgresql-dynamic-schemas.md).

Limit równoczesnych połączeń serwera PostgreSQL określa zmienna Ansible
`postgres_max_connections` (domyślnie `100`). Można ją nadpisać osobno w inventory
danego środowiska; zmiana powoduje odtworzenie kontenera PostgreSQL bez usuwania
danych z `postgres_data_path`.

## Caddy

Konfiguracja bazowa `/etc/caddy/Caddyfile` importuje:

```caddyfile
import snippets/*.caddy
import sites-enabled/*.caddy
```

Ansible przygotowuje `/etc/caddy/sites-enabled` oraz generuje konfiguracje platformy
i organizatora. Frontendy organizatora współdzielą domenę i są dostępne pod
`/staff`, `/trainer` i `/client`; wspólne `/api` i `/api/*` trafia do backendu
organizatora. Platforma pozostaje na osobnej domenie. Ruch frontendowy jest
obsługiwany jako statyczny build Reacta z fallbackiem SPA do `index.html`. Ścieżki
określa `binturo_frontend_roots`. Każda publiczna witryna importuje snippet
`binturo_common`, zawierający limity, nagłówki bezpieczeństwa, ochronę plików
wrażliwych i ustawienia ACME.

Port 80 jest zamknięty, dlatego Caddy nie wystawia przekierowań HTTP→HTTPS. ACME
korzysta z TLS-ALPN-01 na porcie 443. HTTP/3 jest wyłączone, aby nie otwierać
`443/udp`. Szczegóły i przykłady znajdują się w
[docs/caddy-dynamic-config.md](docs/caddy-dynamic-config.md).

Instrukcja bezpiecznego połączenia z PostgreSQL przez tunel SSH oraz uruchamiania
lokalnych testów wydajnościowych na dev, staging i prod znajduje się w
[docs/remote-access-and-load-testing.md](docs/remote-access-and-load-testing.md).

Logi dostępu Caddy mają format JSON i trafiają do
`/var/log/caddy/platform.log` oraz `/var/log/caddy/organizers.log`. Caddy obraca je
codziennie o północy czasu lokalnego i zachowuje do 31 plików nie starszych niż
31 dni. Logi operacyjne usługi pozostają w `journald`.

Deweloperskie domeny `.warszawa` używają wewnętrznego CA Caddy. Produkcja używa
certyfikatu Cloudflare Origin CA pobranego z zaszyfrowanego Vault. Rekordy DNS muszą
być proxowane przez Cloudflare, a tryb SSL/TLS strefy ustawiony na `Full (strict)`.

Dla żądań API pochodzących z oficjalnych zakresów Cloudflare Caddy przekazuje
backendom prawdziwy adres klienta w `X-Real-IP` i `X-Forwarded-For`, pobierając go z
`CF-Connecting-IP`. Połączenia bezpośrednie otrzymują rzeczywisty adres TCP i nie
mogą podszyć się przez własny nagłówek. Backend powinien ufać nagłówkom proxy
wyłącznie od lokalnego Caddy (`127.0.0.1`).

Polecenia do ręcznego zatrzymywania, uruchamiania i diagnozowania PostgreSQL,
monitoringu, Caddy oraz usług systemowych znajdują się w
[MANUAL_INSTRUCTIONS.md](MANUAL_INSTRUCTIONS.md).

Po zmianie pliku dynamicznego wykonaj:

```bash
caddy fmt --overwrite /etc/caddy/sites-enabled/nazwa.caddy
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl reload caddy
```

## Dane trwałe i współdzielone

PostgreSQL przechowuje dane bezpośrednio w
`/srv/binturo/persistent/postgres` (`postgres_data_path`), a Prometheus korzysta z
wolumenu rootless Docker. Katalog
`/srv/binturo/shared/binturo-organizers-files` jest przeznaczony na dane zapisywane
przez `binturo-organizers`; `binturo-platform` może montować go tylko do odczytu.

Przy pierwszym uruchomieniu po tej zmianie rola PostgreSQL zatrzymuje kontener i
kopiuje dane z wcześniejszego wolumenu
`binturo_<środowisko>_postgres_data`, o ile katalog docelowy nie zawiera jeszcze
`PG_VERSION`. Stary wolumen nie jest automatycznie usuwany i pozostaje kopią
awaryjną do czasu ręcznego potwierdzenia poprawności migracji oraz backupu.

## Odzyskiwanie dostępu

Jeżeli bootstrap nie zakończy się prawidłowo:

1. nie uruchamiaj `02-hardening.yml`;
2. nie zamykaj istniejącej sesji i spróbuj połączenia przez port początkowy;
3. użyj konsoli awaryjnej operatora VPS, jeśli SSH nie odpowiada;
4. sprawdź `sudo sshd -t`, status `ssh.socket`, `ssh.service` i UFW;
5. popraw konfigurację i ponów `01-bootstrap.yml`.
