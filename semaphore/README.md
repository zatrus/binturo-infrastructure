# Semaphore UI

Konfiguracja uruchamia Semaphore UI oraz dedykowany PostgreSQL przy użyciu Docker
Compose. Działa z Docker Engine na Ubuntu i z Docker Desktop w trybie Linux
containers na Windows.

PostgreSQL nie wystawia portu na hosta. Panel Semaphore domyślnie nasłuchuje tylko
na `127.0.0.1:3000`. Dane bazy znajdują się w nazwanym wolumenie
`binturo-semaphore_semaphore_postgres_data`.

## Proste przygotowanie do pracy

### 1. Zainstaluj wymagane oprogramowanie

Ubuntu:

```bash
docker --version
docker compose version
```

Windows: zainstaluj Docker Desktop, wybierz tryb Linux containers i sprawdź w
PowerShell:

```powershell
docker version
docker compose version
```

### 2. Przygotuj konfigurację

Przejdź do katalogu `semaphore` i skopiuj przykładowy plik:

Ubuntu:

```bash
cd semaphore
cp .env.example .env
```

Windows PowerShell:

```powershell
Set-Location semaphore
Copy-Item .env.example .env
```

W `.env` ustaw prawdziwy adres e-mail administratora. Pozostaw
`SEMAPHORE_BIND_ADDRESS=127.0.0.1`, jeżeli panel ma być dostępny tylko lokalnie
albo przez reverse proxy.

### 3. Utwórz sekrety

Każdy plik ma zawierać dokładnie jedną wartość bez dodatkowych komentarzy.
Nie kopiuj katalogu `secrets` do Git.

Ubuntu:

```bash
umask 077
head -c 32 /dev/urandom | base64 > secrets/postgres_password
head -c 32 /dev/urandom | base64 > secrets/semaphore_admin_password
head -c 32 /dev/urandom | base64 > secrets/access_key_encryption
head -c 32 /dev/urandom | base64 > secrets/cookie_hash
head -c 32 /dev/urandom | base64 > secrets/cookie_encryption
```

Windows PowerShell:

```powershell
$secretNames = @(
  'postgres_password',
  'semaphore_admin_password',
  'access_key_encryption',
  'cookie_hash',
  'cookie_encryption'
)

New-Item -ItemType Directory -Force secrets | Out-Null
foreach ($secretName in $secretNames) {
  $bytes = [byte[]]::new(32)
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  [System.IO.File]::WriteAllText(
    (Join-Path (Resolve-Path secrets) $secretName),
    [Convert]::ToBase64String($bytes)
  )
}
```

Zapisz hasło z `secrets/semaphore_admin_password` w menedżerze haseł. Będzie
potrzebne do pierwszego logowania. Szczególnie ważny jest plik
`access_key_encryption`: jego utrata może uniemożliwić odszyfrowanie kluczy SSH i
innych poświadczeń zapisanych w bazie.

### 4. Sprawdź i uruchom

```bash
docker compose config
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail 100 semaphore
```

Otwórz <http://127.0.0.1:3000> i zaloguj się nazwą z `SEMAPHORE_ADMIN` oraz hasłem
z `secrets/semaphore_admin_password`.

### 5. Przygotuj pierwszy projekt

W interfejsie Semaphore:

1. Utwórz zespół i projekt.
2. Dodaj repozytorium Git zawierające ten projekt Ansible.
3. Dodaj klucz SSH użytkownika używanego do logowania na hosty.
4. Dodaj inventory dla każdego środowiska.
5. Dodaj klucz typu login/password z hasłem `become`, jeżeli sudo go wymaga.
6. Dodaj hasło Ansible Vault jako osobny chroniony klucz.
7. Utwórz szablony wskazujące playbook, inventory, repozytorium oraz właściwe
   klucze.
8. Najpierw uruchom szablon dla środowiska testowego.

Nie umieszczaj prywatnego klucza SSH ani haseł w repozytorium.

## Codzienna obsługa

Stan:

```bash
docker compose ps
```

Logi:

```bash
docker compose logs -f semaphore
docker compose logs -f postgres
```

Zatrzymanie i ponowne uruchomienie:

```bash
docker compose stop
docker compose start
```

Aktualizacja po świadomej zmianie wersji obrazu w `compose.yml`:

```bash
docker compose pull
docker compose up -d
```

Polecenie `docker compose down` usuwa kontenery i sieci, ale zachowuje nazwany
wolumen bazy. Nie używaj `docker compose down --volumes`, jeśli nie chcesz
bezpowrotnie usunąć bazy Semaphore.

## Backup

Wolumen Dockera nie jest kopią zapasową. Wykonuj regularny logiczny backup bazy i
kopiuj poza host również katalog `secrets`.

Ubuntu:

```bash
docker compose exec -T postgres sh -c \
  'pg_dump -U semaphore -d semaphore -Fc -f /backups/semaphore-$(date +%F-%H%M%S).dump'
```

Windows PowerShell:

```powershell
$stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
docker compose exec -T postgres pg_dump `
  -U semaphore -d semaphore -Fc `
  -f "/backups/semaphore-$stamp.dump"
```

Sprawdzenie kopii:

```bash
docker compose exec -T postgres pg_restore --list /backups/NAZWA_PLIKU.dump
```

Pliki w `backups` są ignorowane przez Git.

### Odtworzenie

Przed odtworzeniem zatrzymaj Semaphore, pozostawiając PostgreSQL uruchomiony:

```bash
docker compose stop semaphore
docker compose exec -T postgres dropdb -U semaphore --if-exists semaphore
docker compose exec -T postgres createdb -U semaphore semaphore
docker compose exec -T postgres pg_restore \
  -U semaphore -d semaphore --clean --if-exists /backups/NAZWA_PLIKU.dump
docker compose start semaphore
```

Odtwarzaj jednocześnie bazę oraz odpowiadające jej pliki z katalogu `secrets`.

## Dostęp z innego komputera

Nie ustawiaj bez potrzeby `SEMAPHORE_BIND_ADDRESS=0.0.0.0`, ponieważ wystawi to
niezaszyfrowany port HTTP w sieci. Preferowane rozwiązanie to reverse proxy z HTTPS
albo tunel SSH:

```bash
ssh -L 3000:127.0.0.1:3000 user@semaphore-host
```

Po zestawieniu tunelu otwórz <http://127.0.0.1:3000>.

## Pliki trwałe

- baza, historia zadań, projekty i zapisane poświadczenia:
  `binturo-semaphore_semaphore_postgres_data`;
- klucze szyfrujące i hasła: `secrets/`;
- logiczne kopie bazy: `backups/`;
- sklonowane repozytoria i pliki robocze zadań w `/tmp/semaphore` są tymczasowe.

Do pełnego odtworzenia potrzebujesz backupu PostgreSQL oraz niezmienionych kluczy
szyfrujących z `secrets`.
