# Zdalny dostęp do PostgreSQL i testy wydajnościowe

## Zasady bezpieczeństwa

PostgreSQL jest publikowany przez Docker wyłącznie na `127.0.0.1:5432` hosta.
UFW nie otwiera portu 5432. To ustawienie należy zachować: z komputera operatora
łączymy się tunelem SSH, a nie przez publicznie dostępny port bazy.

Testy na produkcji tworzą dane, wykonują zapisy i mogą obniżyć dostępność usługi.
Uruchamiaj je tylko w uzgodnionym oknie, zaczynając od małego obciążenia. Nigdy nie
używaj danych ani haseł prawdziwych użytkowników. `seed_users.py` nie jest testem
tylko do odczytu — tworzy organizatorów i konta oraz zapisuje bezpośrednio do bazy.

## Parametry środowisk

| Środowisko | Host SSH | Port SSH | Użytkownik SSH | Baza | API platformy | API organizatora |
|---|---:|---:|---|---|---|---|
| dev | `10.0.0.110` | `2918` | `binturo_dev` | `binturo_dev_warszawa` | `https://platform.binturo.warszawa/api` | `https://app.binturo.warszawa` |
| staging | ustaw prawdziwy adres zamiast `1.2.3.4` w inventory | `4285` | `binturo_s` | `binturo_staging` | `https://platform-staging.binturo.com/api` | `https://app-staging.binturo.com` |
| prod | `51.68.151.77` | `2416` | `binturo_p` | `binturo_prod` | `https://platform.binturo.com/api` | `https://app.binturo.com` |

Adres staging w repozytorium jest placeholderem, więc przed połączeniem trzeba
uzupełnić `inventories/staging/hosts.yml` lub użyć rzeczywistego adresu w poleceniu.
Domeny `.warszawa` wymagają dostępu do sieci dev, poprawnego lokalnego DNS oraz
zaufania do wewnętrznego CA Caddy.

## PostgreSQL z pgAdmina lub innego klienta SQL

### 1. Uruchom tunel SSH

W PowerShellu pozostaw poniższe polecenie uruchomione. `KEY_PATH` zastąp ścieżką
do prywatnego klucza odpowiadającego kluczowi publicznemu danego środowiska.
Każde środowisko dostaje inny lokalny port, dzięki czemu tunele mogą działać
jednocześnie:

```powershell
# dev
ssh -i "KEY_PATH" -p 2918 -N `
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 `
  -L 127.0.0.1:15432:127.0.0.1:5432 binturo_dev@10.0.0.110

# staging — zastąp STAGING_HOST rzeczywistym adresem
ssh -i "KEY_PATH" -p 4285 -N `
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 `
  -L 127.0.0.1:15433:127.0.0.1:5432 binturo_s@STAGING_HOST

# prod
ssh -i "KEY_PATH" -p 2416 -N `
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 `
  -L 127.0.0.1:15434:127.0.0.1:5432 binturo_p@51.68.151.77
```

Brak komunikatu po udanym uruchomieniu jest prawidłowy (`-N` uruchamia tylko
tunel). Przerwanie: `Ctrl+C`. Jeśli SSH zgłasza zakaz forwardingu, sprawdź na
serwerze `sshd -T | grep allowtcpforwarding`; konfiguracja powinna zwrócić `yes`.

### 2. Skonfiguruj klienta SQL

W pgAdminie wybierz **Register → Server** i ustaw:

- **Host name/address:** `127.0.0.1`;
- **Port:** `15432` dla dev, `15433` dla staging albo `15434` dla prod;
- **Maintenance database:** nazwa bazy z tabeli wyżej;
- **Username:** najlepiej `binturo_organizers_app` do danych organizatorów albo
  `binturo_platform_app` do operacji platformy;
- **Password:** odpowiednio wartość `vault_postgres_organizers_password` lub
  `vault_postgres_platform_password` z Ansible Vault danego środowiska;
- **SSL mode:** `prefer` albo `disable` — połączenie jest już szyfrowane przez SSH
  i kończy się na loopbacku serwera.

Nie używaj konta `postgres`, jeśli nie jest to konieczne. Role aplikacyjne mają
różne uprawnienia: `binturo_organizers_app` jest ograniczona do DML, a
`binturo_platform_app` jest właścicielem migracji i schematów. W DBeaverze,
DataGripie lub `psql` używa się tych samych parametrów. Przykład:

```powershell
$env:PGPASSWORD = "HASLO_Z_VAULT"
psql -h 127.0.0.1 -p 15433 -U binturo_organizers_app -d binturo_staging
Remove-Item Env:PGPASSWORD
```

## Testy wydajnościowe z `D:\projects\reservations\load-testing`

Test ma dwie niezależne fazy. Seedowanie wymaga API platformy oraz tunelu do
PostgreSQL. Locust wymaga tylko dostępu HTTP(S) do API organizatora i gotowego
pliku z kontami.

### 1. Przygotowanie interpreterów

Zgodnie z README zestawu testowego `seed_users.py` uruchamiaj interpreterem
backendu organizatora, a Locusta jego własnym środowiskiem:

```powershell
Set-Location D:\projects\reservations\load-testing
Copy-Item .env.example .env       # tylko pierwszy raz; nie commituj .env
Copy-Item spec.example.json spec.json

python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

### 2. Seedowanie wybranego środowiska

Najpierw uruchom tunel PostgreSQL opisany wyżej. Następnie ustaw w
`load-testing/.env` parametry wybranego środowiska. Zmienne z tego pliku są
ładowane przed `.env` backendu i dlatego nadpisują jego lokalne ustawienia.

Przykład dla staging:

```dotenv
PLATFORM_API_URL=https://platform-staging.binturo.com/api
PLATFORM_ADMIN_EMAIL=load-test-admin@example.com
PLATFORM_ADMIN_PASSWORD=<haslo-dedykowanego-konta-platform-admin>

ORGANIZERS_BACKEND_DIR=../binturo-organizers/backend
LOAD_TEST_PASSWORD=<unikalne-silne-haslo-tylko-dla-staging>
SEED_CONCURRENCY=8

BINTURO_DB_HOST=127.0.0.1
BINTURO_DB_PORT=15433
BINTURO_DB_DATABASE=binturo_staging
BINTURO_DB_SCHEMA=binturo
BINTURO_DB_USERNAME=binturo_organizers_app
BINTURO_DB_PASSWORD=<vault_postgres_organizers_password-dla-staging>
BINTURO_PLATFORM_SCHEMA=binturo_platform
BINTURO_USERS_SCHEMA=binturo_users

ORGANIZERS_API_URL=https://app-staging.binturo.com/api
```

Dla dev zmień port na `15432`, bazę na `binturo_dev_warszawa` i domeny na
`.warszawa`. Dla prod użyj portu `15434`, bazy `binturo_prod` oraz domen bez
`-staging`. Używaj osobnego konta platform-admin i osobnego hasła testowego dla
każdego środowiska.

Zmniejsz najpierw liczby w `spec.json`, zwłaszcza na produkcji. Seedowanie:

```powershell
..\binturo-organizers\backend\.venv\Scripts\python.exe seed_users.py spec.json
```

Skrypt zawsze zapisuje `credentials.csv`. Po seedowaniu zachowaj osobną kopię,
aby nie uruchomić kont z jednego środowiska przeciw innemu:

```powershell
Copy-Item credentials.csv credentials.staging.csv
```

Pliki `.env`, `credentials*.csv` i `spec.json` zawierają sekrety lub dane testowe
i nie powinny trafiać do repozytorium ani do logów CI.

### 3. Uruchomienie Locusta

Locust nie potrzebuje tunelu SSH ani dostępu do bazy. Kieruj go na publiczną
domenę Caddy. Endpointy w `locustfile.py` zawierają prefiks `/api`, dlatego
`--host` podaj bez końcowego `/api`:

```powershell
Set-Location D:\projects\reservations\load-testing
$env:CREDENTIALS_CSV_PATH = "$PWD\credentials.staging.csv"

# UI pod http://localhost:8089
.venv\Scripts\locust.exe -f locustfile.py --host https://app-staging.binturo.com

# Ostrożny test headless: 10 użytkowników, 1/s, przez 2 minuty
.venv\Scripts\locust.exe -f locustfile.py `
  --host https://app-staging.binturo.com `
  --headless -u 10 -r 1 -t 2m

Remove-Item Env:CREDENTIALS_CSV_PATH
```

Odpowiednie hosty to:

- dev: `https://app.binturo.warszawa`;
- staging: `https://app-staging.binturo.com`;
- prod: `https://app.binturo.com`.

Jeśli komputer nie ufa CA środowiska dev albo nie rozwiązuje domeny `.warszawa`,
można ominąć Caddy i tunelować bezpośrednio port backendu organizatora:

```powershell
ssh -i "KEY_PATH" -p 2918 -N `
  -L 127.0.0.1:18002:127.0.0.1:18102 binturo_dev@10.0.0.110

.venv\Scripts\locust.exe -f locustfile.py --host http://127.0.0.1:18002
```

Analogicznie API platformy do seedowania można tunelować z portu serwera `18101`,
np. dev: `-L 127.0.0.1:18001:127.0.0.1:18101`, a następnie ustawić
`PLATFORM_API_URL=http://127.0.0.1:18001/api`.

### 4. Kontrola przed testem produkcyjnym

Przed testem produkcji potwierdź:

1. zgodę i okno testowe;
2. limity Cloudflare/WAF oraz brak automatycznej blokady ruchu generatora;
3. monitoring CPU, RAM, opóźnień, błędów HTTP i liczby połączeń PostgreSQL;
4. relację `procesy × (BINTURO_DB_POOL_SIZE + BINTURO_DB_MAX_OVERFLOW)` do
   `postgres_max_connections`, z rezerwą dla platformy, monitoringu i administracji;
5. plan usunięcia syntetycznych organizatorów i kont po teście;
6. start od małego `-u`, `-r` i krótkiego `-t`, dopiero potem stopniowe zwiększanie.
