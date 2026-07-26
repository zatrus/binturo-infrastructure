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
cp vars/jenkins-local-vault.example.yml vars/jenkins-local-vault.yml
```

Uzupełnij `vars/jenkins-local.yml`. Szczególnie uzupełnij staging, ponieważ jego
obecne inventory zawiera placeholdery. Domyślna ścieżka docelowa to:

```yaml
jenkins_source_root: /mnt/d/projects/reservations/jenkins
```

Uzupełnij sekrety i prywatne klucze w `vars/jenkins-local-vault.yml`, a następnie
zaszyfruj plik:

```bash
ansible-vault encrypt vars/jenkins-local-vault.yml
```

Oba lokalne pliki są ignorowane przez Git. Nie zapisuj kluczy prywatnych ani
haseł w plikach `.example`.

## Uruchomienie

Pierwsze wygenerowanie:

```bash
ansible-playbook jenkins-local.yml --ask-vault-pass --diff
```

Sekretne zadania używają `no_log`, więc hasła i klucze nie pojawią się w diffie
ani logu Ansible.

Domyślnie playbook nie nadpisuje istniejących plików runtime. Pozwala to uniknąć
utraty ręcznie poprawionej konfiguracji. Aby świadomie odtworzyć wszystkie pliki
na podstawie aktualnych zmiennych:

```bash
ansible-playbook jenkins-local.yml \
  --ask-vault-pass \
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
- PostgreSQL, JWT i klucze SSH są pobierane wyłącznie z zaszyfrowanego pliku
  `vars/jenkins-local-vault.yml`.
- Hasła bazy w Jenkins muszą odpowiadać hasłom skonfigurowanym na właściwych
  hostach.
- JWT organizatorów i platformy muszą być różne i mieć co najmniej 32 znaki.
