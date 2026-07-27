# Lokalne przygotowanie plików Jenkins przez Ansible

Playbook `jenkins-local.yml` działa wyłącznie na `localhost`. Nie łączy się z
hostami aplikacyjnymi i nie modyfikuje plików źródłowych JCasC, Jenkinsfile ani
plików `.example`. Tworzy w istniejącym repozytorium `reservations/jenkins`:

- `secrets/secrets.properties`;
- sześć prywatnych kluczy w `secrets/keys/`;
- po trzy pliki `.env` dla `config/organizers` i `config/platform`.

## Przygotowanie

W WSL, w katalogu projektu `reservation-stack`:

```bash
cp vars/jenkins-local.example.yml vars/jenkins-local.yml
cp vars/jenkins-local-vault.local.example.yml vars/jenkins-local-vault.local.yml
cp vars/jenkins-local-vault.staging.example.yml vars/jenkins-local-vault.staging.yml
cp vars/jenkins-local-vault.production.example.yml vars/jenkins-local-vault.production.yml
```

Stary `vars/jenkins-local-vault.yml` nie jest już wczytywany przez playbook.
Pozostaje na liście `.gitignore` wyłącznie po to, aby podczas migracji nie doszło
do przypadkowego dodania istniejącego pliku z sekretami do repozytorium.

Uzupełnij `vars/jenkins-local.yml`. Szczególnie uzupełnij staging, ponieważ jego
obecne inventory zawiera placeholdery. Domyślna ścieżka docelowa to:

```yaml
jenkins_source_root: /mnt/d/projects/reservations/jenkins
```

Dla każdego środowiska skonfiguruj osobne domeny frontendów organizers:
`organizers_staff_domain`, `organizers_trainer_domain` i
`organizers_client_domain`. Playbook generuje zgodne z JCasC zmienne
`BINTURO_STAFF_APP_URL`, `BINTURO_TRAINER_APP_URL` oraz
`BINTURO_CLIENT_APP_URL`. Generuje również trzy docelowe katalogi
`STAFF_FRONTEND_DIR`, `TRAINER_FRONTEND_DIR` i `CLIENT_FRONTEND_DIR` oraz wspólny
schemat użytkowników `BINTURO_USERS_SCHEMA`.

Porty `binturo_frontend_ports` należą do konfiguracji Caddy na hostach i nie są
przekazywane do Jenkinsa. Pipeline wdraża statyczne buildy frontendów przez
`rsync`; nie uruchamia dla nich osobnych procesów.

Uzupełnij sekrety i prywatne klucze w trzech plikach Vault. Globalne hasło
administratora Jenkins znajduje się w pliku `local`, ponieważ jest to konfiguracja
lokalnie uruchamianej instancji Jenkins. Każdy plik zaszyfruj innym Vault ID i
hasłem:

```bash
ansible-vault encrypt --vault-id local@prompt \
  vars/jenkins-local-vault.local.yml
ansible-vault encrypt --vault-id staging@prompt \
  vars/jenkins-local-vault.staging.yml
ansible-vault encrypt --vault-id production@prompt \
  vars/jenkins-local-vault.production.yml
```

Oba lokalne pliki są ignorowane przez Git. Nie zapisuj kluczy prywatnych ani
haseł w plikach `.example`.

## Uruchomienie

Pierwsze wygenerowanie:

```bash
ansible-playbook jenkins-local.yml \
  --vault-id local@prompt \
  --vault-id staging@prompt \
  --vault-id production@prompt \
  --diff
```

Sekretne zadania używają `no_log`, więc hasła i klucze nie pojawią się w diffie
ani logu Ansible.

Domyślnie playbook nie nadpisuje istniejących plików runtime. Pozwala to uniknąć
utraty ręcznie poprawionej konfiguracji. Aby świadomie odtworzyć wszystkie pliki
na podstawie aktualnych zmiennych:

```bash
ansible-playbook jenkins-local.yml \
  --vault-id local@prompt \
  --vault-id staging@prompt \
  --vault-id production@prompt \
  --extra-vars jenkins_local_overwrite_existing=true
```

Po wykonaniu przejrzyj niesekretne pliki `jenkins/config/**/*.env`, a następnie
uruchom Jenkins zgodnie z `D:\projects\reservations\JENKINS.md`, np. w PowerShell
repozytorium `reservations`:

```powershell
.\jenkins\local\run-jenkins.ps1 -InstallPlugins
```

## Zakres i bezpieczeństwo

- Playbook jedynie przygotowuje lokalne pliki wejściowe Jenkinsa.
- Nie uruchamia Jenkinsa i nie instaluje wtyczek.
- Nie wykonuje deploymentu aplikacji.
- PostgreSQL, JWT i klucze SSH są pobierane wyłącznie z trzech zaszyfrowanych
  plików `vars/jenkins-local-vault.<środowisko>.yml`.
- Vault ID `local`, `staging` i `production` pozwalają używać innego hasła dla
  każdego środowiska. ID zapisane w nagłówku zaszyfrowanego pliku musi odpowiadać
  ID przekazanemu przy uruchomieniu playbooka.
- Hasła bazy w Jenkins muszą odpowiadać hasłom skonfigurowanym na właściwych
  hostach.
- JWT organizatorów i platformy muszą być różne i mieć co najmniej 32 znaki.
