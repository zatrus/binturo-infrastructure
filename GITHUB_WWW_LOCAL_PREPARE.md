# Konfiguracja GitHub Environments dla binturo-www

Playbook `github-www-local.yml` generuje osobne skrypty Bash i PowerShell, które
konfigurują GitHub Environments repozytorium landing page `binturo-www`.

## Konfiguracja lokalna

Skopiuj plik przykładowy:

```bash
cp vars/github-www-local.example.yml vars/github-www-local.yml
```

Ustaw repozytorium oraz bezpieczny katalog wyjściowy:

```yaml
github_repository: zatrus/binturo-www
github_local_output_dir: /mnt/d/projects/binturo-www/github-environments
```

Plik `vars/github-www-local.yml` jest lokalny i nie powinien zawierać sekretów.
Klucz wdrożeniowy jest pobierany z prywatnego klucza odpowiadającego
`custom_admin_authorized_key_file` w wybranym inventory.

## Generowanie

Jeżeli projekt znajduje się na montowanym dysku Windows (`/mnt/c` lub `/mnt/d`),
Ansible może uznać katalog za `world writable` i zignorować lokalny
`ansible.cfg`. Przed uruchomieniem ustaw go jawnie:

```bash
cd /mnt/d/projects/reservation-stack
export ANSIBLE_CONFIG=/mnt/d/projects/reservation-stack/ansible.cfg
```

Uruchom playbook osobno dla każdego środowiska:

```bash
ansible-playbook -i inventories/dev/hosts.yml github-www-local.yml \
  --vault-id dev@prompt
ansible-playbook -i inventories/staging/hosts.yml github-www-local.yml \
  --vault-id staging@prompt
ansible-playbook -i inventories/prod/hosts.yml github-www-local.yml \
  --vault-id prod@prompt
```

Inventory automatycznie ładuje zaszyfrowany `group_vars/all/vault.yml`, dlatego
hasło Vault jest wymagane również dla lokalnego generatora. Zamiast
`--vault-id <środowisko>@prompt` można użyć `--ask-vault-pass`.

Powstaną pliki:

```text
configure-github-www-dev.sh
configure-github-www-dev.ps1
configure-github-www-staging.sh
configure-github-www-staging.ps1
configure-github-www-production.sh
configure-github-www-production.ps1
```

## Uruchomienie skryptu

Zaloguj GitHub CLI kontem mającym prawo zarządzania Actions variables, secrets
i Environments repozytorium:

```bash
gh auth login
gh auth status
```

Bash/WSL:

```bash
./configure-github-www-production.sh
```

PowerShell:

```powershell
.\configure-github-www-production.ps1
```

Skrypt tworzy lub aktualizuje Environment i ustawia variables:

```text
DEPLOY_SSH_HOST
DEPLOY_SSH_PORT
DEPLOY_SSH_USER
DEPLOY_SSH_SUDO_USER
DEPLOY_WWW_DIR
BINTURO_WWW_URL
BINTURO_APP_URL
```

`BINTURO_APP_URL` wskazuje domenę aplikacji organizatora
(`binturo_domains.organizers`), do której prowadzą przyciski logowania na
landing page.

oraz secret:

```text
DEPLOY_SSH_PRIVATE_KEY
```

Skrypty zawierają klucz prywatny zakodowany Base64. Katalog wyjściowy ma tryb
`0700`, ale po skonfigurowaniu GitHuba należy usunąć wygenerowane pliki.

Weryfikacja:

```bash
gh variable list --repo zatrus/binturo-www --env production
gh secret list --repo zatrus/binturo-www --env production
```
