# Generowanie GitHub Environments z inventory Ansible

Playbook `github-local.yml` działa lokalnie, odczytuje wskazane inventory oraz
Ansible Vault i generuje dwa skrypty konfigurujące jedno GitHub Environment:

- Bash: `configure-github-<environment>.sh`;
- PowerShell: `configure-github-<environment>.ps1`.

Skrypty używają GitHub CLI (`gh`) i ustawiają dokładnie variables oraz secrets
odczytywane przez `.github/workflows/deploy-organizator.yml` i
`.github/workflows/deploy-platform.yml`. Workflowy `pr-tests.yml` i `release.yml`
nie wymagają tej konfiguracji: korzystają z automatycznego `GITHUB_TOKEN`.

## Szybki przebieg end-to-end

Generator jest lokalnym playbookiem Ansible, a nie workflowem wykonywanym przez
GitHub Actions. Typowy przebieg wygląda następująco:

1. skonfiguruj `vars/github-local.yml`;
2. uruchom `github-local.yml` dla wybranego inventory i Vault;
3. uruchom jeden z dwóch wygenerowanych skryptów;
4. sprawdź Environment przez `gh` lub interfejs GitHuba;
5. uruchom najpierw deploy organizatora, a następnie platformy.

Przykład dla produkcji, gdy Ansible działa w WSL, a skrypt wykonujesz w
PowerShellu:

```bash
cd /mnt/d/projects/reservation-stack
cp vars/github-local.example.yml vars/github-local.yml
ansible-playbook -i inventories/prod/hosts.yml github-local.yml \
  --vault-id prod@prompt
```

```powershell
gh auth login
& D:\projects\reservations\github-environments\configure-github-production.ps1
gh workflow run deploy-organizator.yml --repo OWNER/reservations -f environment=production
gh workflow run deploy-platform.yml --repo OWNER/reservations -f environment=production
```

Zastąp `OWNER/reservations` wartością `github_repository`.

## Mapowanie środowisk

| Inventory | GitHub Environment |
|---|---|
| `dev` | `dev` |
| `staging` | `staging` |
| `prod` | `production` |

Mapowanie można zmienić w `roles/github_local_config/defaults/main.yml`.

## Przygotowanie

Skopiuj publiczną konfigurację i ustaw repozytorium oraz bezwzględny katalog
wynikowy widziany przez środowisko, w którym działa Ansible (typowo WSL):

```bash
cp vars/github-local.example.yml vars/github-local.yml
```

Przykład:

```yaml
github_repository: twoja-organizacja/reservations
github_local_output_dir: /mnt/d/projects/reservations/github-environments
```

`vars/github-local.yml` jest ignorowany przez Git. Klucz prywatny jest pobierany
z pliku odpowiadającego `custom_admin_authorized_key_file` po usunięciu `.pub`,
tak samo jak w generatorze Jenkins. Pozostałe sekrety pochodzą z Vault wybranego
inventory.

## Generowanie

```bash
# dev
ansible-playbook -i inventories/dev/hosts.yml github-local.yml \
  --vault-id dev@prompt --diff

# staging
ansible-playbook -i inventories/staging/hosts.yml github-local.yml \
  --vault-id staging@prompt --diff

# production
ansible-playbook -i inventories/prod/hosts.yml github-local.yml \
  --vault-id prod@prompt --diff
```

Katalog można jednorazowo wskazać również z CLI:

```bash
ansible-playbook -i inventories/prod/hosts.yml github-local.yml \
  --vault-id prod@prompt \
  -e github_local_output_dir=/mnt/d/inny/katalog
```

## Uruchomienie wygenerowanego skryptu

Najpierw zainstaluj `gh`, zaloguj się kontem mającym uprawnienia administracyjne
do Environments, Actions variables i Actions secrets danego repozytorium:

```bash
gh auth login
gh auth status
```

Aktywne konto powinno wskazywać właściwy host (`github.com`) i mieć dostęp do
repozytorium podanego w `github_repository`. Dla repozytorium prywatnego token
musi mieć dostęp do repozytorium oraz możliwość zarządzania Actions secrets,
variables i Environments. W przypadku logowania tokenem klasycznym zwykle
potrzebny jest zakres `repo`; przy tokenie fine-grained nadaj uprawnienia tylko
temu repozytorium, zgodnie z zasadą najmniejszych uprawnień.

Bash/WSL:

```bash
/mnt/d/projects/reservations/github-environments/configure-github-production.sh
```

PowerShell:

```powershell
& D:\projects\reservations\github-environments\configure-github-production.ps1
```

Skrypt jest idempotentny: tworzy Environment, jeśli nie istnieje, a następnie
ustawia lub aktualizuje wszystkie jego variables i secrets. Nie usuwa dodatkowych
wartości istniejących w GitHubie i nie konfiguruje reguł ochrony, takich jak
required reviewers — te wymagają osobnej, świadomej polityki.

Skrypt kończy pracę przy pierwszym błędzie `gh`. Można bezpiecznie uruchomić go
ponownie: wartości ustawione przed błędem zostaną nadpisane tymi samymi danymi,
a konfiguracja będzie kontynuowana od początku.

## Weryfikacja konfiguracji

Lista Environmentów:

```bash
gh api repos/OWNER/reservations/environments --jq '.environments[].name'
```

Zmienne wybranego Environment:

```bash
gh variable list --repo OWNER/reservations --env production
```

Sekrety można wylistować tylko po nazwie i dacie aktualizacji — GitHub nigdy nie
zwraca ich wartości:

```bash
gh secret list --repo OWNER/reservations --env production
```

W interfejsie GitHuba te same dane znajdują się pod:

```text
Repository → Settings → Environments → production
```

Sprawdź szczególnie:

- `DEPLOY_SSH_HOST`, `DEPLOY_SSH_PORT`, `DEPLOY_SSH_USER` i `DEPLOY_SSH_SUDO_USER`
  (konto logowania SSH i konto systemowe właściciela aplikacji — patrz
  "Model SSH/sudo" niżej — muszą być poprawnie rozróżnione);
- katalogi `DEPLOY_*_DIR`;
- URL-e `BINTURO_*_APP_URL`;
- obecność `DEPLOY_SSH_PRIVATE_KEY`, sekretów DB i dwóch różnych sekretów JWT.

## Uruchamianie workflowów po konfiguracji

Wygenerowane Environment zasila cztery workflowy w repozytorium
`reservations`: `deploy-organizator.yml`, `deploy-platform.yml` (opisane
niżej) oraz ręcznie wyzwalane `start-backend.yml`/`stop-backend.yml` (start/stop
już wdrożonego backendu bez pełnego deployu — przyjmują dodatkowo input
`backend: organizers|platform`, patrz `GITHUB_WORKFLOWS.md` w tamtym
repozytorium). Wszystkie cztery mają input typu `environment` — wartość musi
dokładnie odpowiadać nazwie utworzonej przez generator: `dev`, `staging` albo
`production`.

Z GitHub CLI:

```bash
# dev
gh workflow run deploy-organizator.yml --repo OWNER/reservations -f environment=dev
gh workflow run deploy-platform.yml --repo OWNER/reservations -f environment=dev

# staging
gh workflow run deploy-organizator.yml --repo OWNER/reservations -f environment=staging
gh workflow run deploy-platform.yml --repo OWNER/reservations -f environment=staging

# produkcja
gh workflow run deploy-organizator.yml --repo OWNER/reservations -f environment=production
gh workflow run deploy-platform.yml --repo OWNER/reservations -f environment=production
```

Z interfejsu GitHuba:

1. otwórz **Actions**;
2. wybierz **Deploy Organizator**;
3. wybierz **Run workflow** i właściwe Environment;
4. poczekaj na poprawne zakończenie;
5. dopiero potem uruchom **Deploy Platform** na tym samym Environment.

Platformę wdrażamy po organizatorze, ponieważ jej konfiguracja wskazuje katalogi
i interpreter już wdrożonego backendu organizatora.

Podgląd ostatnich uruchomień i logów:

```bash
gh run list --repo OWNER/reservations --limit 10
gh run watch --repo OWNER/reservations
```

Przed pierwszym deployem produkcyjnym warto dodać ręcznie w ustawieniach
Environment regułę **Required reviewers**. Generator jej celowo nie ustawia,
ponieważ wybór osób zatwierdzających jest decyzją organizacyjną, a nie wartością
pochodzącą z inventory serwera.

## Aktualizacja istniejącego Environment

Po zmianie domeny, portu, katalogu, hasła, klucza SSH albo innej wartości:

1. zaktualizuj inventory lub Vault;
2. ponownie uruchom `github-local.yml` dla tego środowiska;
3. ponownie wykonaj wygenerowany skrypt;
4. zweryfikuj listę variables i secrets;
5. usuń lokalne skrypty zawierające sekrety.

Generator aktualizuje wartości istniejące, ale nie usuwa kluczy, które przestały
być używane przez workflow. Takie osierocone wartości usuń świadomie:

```bash
gh variable delete NAZWA --repo OWNER/reservations --env production
gh secret delete NAZWA --repo OWNER/reservations --env production
```

## Typowe problemy

### `gh: command not found` lub `gh is not recognized`

Zainstaluj GitHub CLI, otwórz nową powłokę i wykonaj `gh auth login`.

### HTTP 403 albo `Resource not accessible`

Aktywne konto lub token nie ma praw administracyjnych do Environment/Actions w
tym repozytorium. Sprawdź `gh auth status`, repozytorium oraz zakres tokenu.

### Environment powstał, ale workflow nie widzi wartości

Najczęściej input workflow ma inną nazwę niż Environment, np. `prod` zamiast
`production`. Nazwa jest rozróżniana dokładnie według tekstu przekazanego w
`-f environment=...`.

### Deploy zatrzymuje się na SSH lub `rsync: permission denied`

Sprawdź poprawność hosta, portu i klucza. Workflowy GitHub Actions logują się
jako `DEPLOY_SSH_USER`, ale wszystkie polecenia i transfery plików wykonują
się jako `DEPLOY_SSH_SUDO_USER` przez `sudo -n -u` (ten sam model co lokalny
Jenkins) — sprawdź więc:

- czy `DEPLOY_SSH_SUDO_USER` jest ustawione i wskazuje istniejące konto
  systemowe będące właścicielem katalogów `DEPLOY_*_DIR`;
- czy na serwerze istnieje wpis `sudoers` pozwalający `DEPLOY_SSH_USER`
  uruchomić bez hasła (`NOPASSWD`) `bash` i `rsync` jako
  `DEPLOY_SSH_SUDO_USER` — przykładowy wpis i pełny opis w
  `GITHUB_WORKFLOWS.md` w repozytorium `reservations`, sekcja "Wymagania
  sudoers".

Krok "Verify required variables, SSH connectivity and sudo access" na
początku każdego workflowu (`deploy-organizator.yml`/`deploy-platform.yml`/
`start-backend.yml`/`stop-backend.yml`) sprawdza dokładnie to połączenie
(`sudo -n`) przed rozpoczęciem właściwego wdrożenia — jeśli deploy pada tu,
komunikat błędu wskazuje, czy to sudoers, czy sama łączność SSH.

### Skrypt PowerShell jest blokowany przez execution policy

Uruchom go jednorazowo bez trwałej zmiany polityki systemowej:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  D:\projects\reservations\github-environments\configure-github-production.ps1
```

## Bezpieczeństwo i ograniczenia

Wygenerowane skrypty zawierają wszystkie sekrety zakodowane Base64. Base64 nie
jest szyfrowaniem. Katalog ma tryb `0700`, a skrypty `0700`, ale na filesystemie
Windows/WSL egzekwowanie praw POSIX zależy od sposobu montowania dysku. Nie
commituj, nie wysyłaj i nie archiwizuj tych plików; po poprawnym wykonaniu usuń je.

GitHub workflowy logują się przez SSH jako `DEPLOY_SSH_USER` (`ansible_user` z
inventory), ale wszystkie polecenia na serwerze i transfery plików wykonują
się jako `DEPLOY_SSH_SUDO_USER` (`binturo_user` z inventory — konto właściciela
katalogów aplikacji) przez `sudo -n -u` — dokładnie ten sam model, jakiego
lokalny Jenkins używa od dawna (`SSH_SUDO_USER`, patrz
`roles/jenkins_local_config`). Wymaga to na serwerze wpisu `sudoers`
pozwalającego `DEPLOY_SSH_USER` uruchomić bez hasła (`NOPASSWD`) `bash` i
`rsync` jako `DEPLOY_SSH_SUDO_USER` — przykładowy wpis, pełny opis mechanizmu i
lista kroków weryfikujących połączenie/sudo przed każdym deployem: patrz
`GITHUB_WORKFLOWS.md` w repozytorium `reservations`, sekcje "Rozdzielenie
DEPLOY_SSH_USER i DEPLOY_SSH_SUDO_USER" i "Wymagania sudoers". Bez poprawnego
wpisu `sudoers` sam generator skonfiguruje Environment poprawnie, ale deploy
GitHub zawiedzie już na kroku weryfikacji wstępnej (`sudo -n` kończy się
błędem zamiast czekać na hasło).

## Co jest konfigurowane

Wspólne dane SSH (w tym `DEPLOY_SSH_SUDO_USER` — konto systemowe właściciela
aplikacji, patrz "Model SSH/sudo" wyżej), katalogi obu aplikacji, domeny i
URL-e trzech frontendów organizatora, porty backendów, parametry bazy,
schematy oraz konfiguracja poczty są tworzone jako Environment variables.
`DEPLOY_SSH_SUDO_USER` jest zwykłą variable, NIE secret — nazwa konta
systemowego nie jest wartością poufną. Klucz SSH, użytkownicy i hasła bazy,
sekrety JWT oraz opcjonalne klucze MailerSend są tworzone jako Environment
secrets.

Generator ustawia również `DEPLOY_MAINTENANCE_DIR`. Workflowy aplikacyjne mogą
tworzyć i usuwać w nim marker `organizers.enabled`, przełączając maintenance bez
przeładowania Caddy. Szczegóły opisuje
[docs/organizers-maintenance.md](docs/organizers-maintenance.md).

Generator celowo nie ustawia `GITHUB_TOKEN`: GitHub tworzy go automatycznie dla
każdego uruchomienia workflow.
