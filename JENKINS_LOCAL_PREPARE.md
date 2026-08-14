# Generowanie konfiguracji Jenkins z inventory

Playbook `jenkins-local.yml` generuje konfigurację dla jednego środowiska
wskazanego przez `-i`. Nie łączy się z hostem: używa połączenia lokalnego, ale
odczytuje wszystkie wartości z hosta grupy `hardened_hosts`.

Mapowanie nazw środowisk:

| Inventory | Jenkins |
| --- | --- |
| `dev` | `local` |
| `staging` | `staging` |
| `prod` | `production` |

## Źródła danych

Z inventory i `group_vars/all.yml` pobierane są:

- host, port i użytkownik SSH;
- użytkownik systemowy, na którego joby przełączają się przez `sudo`;
- domenę platformy i trzy konteksty ścieżek frontendów organizatora;
- katalogi wdrożeniowe;
- katalog markera trybu maintenance organizatora;
- porty backendów;
- nazwa bazy, użytkownicy i schematy PostgreSQL;
- hasła aplikacyjnych użytkowników PostgreSQL.

Hasła użytkowników aplikacyjnych PostgreSQL są pobierane z istniejących
zmiennych Vault inventory. Generator nie pobiera ani nie generuje sekretów JWT.
Jeżeli aktualne pipeline'y nadal wymagają credentiali
`ORGANIZERS_<ENV>_JWT_SECRET` i `PLATFORM_<ENV>_JWT_SECRET`, należy dodać
je ręcznie podczas składania finalnego `secrets.properties`.

Współdzielona konfiguracja znajduje się w:

    vars/jenkins-local.yml

Katalog wynikowy jest podany jawnie w `group_vars/all.yml`:

    jenkins_output_dir: /mnt/d/projects/reservations/jenkins

Ponieważ Ansible działa w WSL, musi to być bezwzględna ścieżka linuksowa.
W celu zmiany katalogu edytuj tę jedną wartość.

Przygotowanie:

    cp vars/jenkins-local.example.yml vars/jenkins-local.yml

Hasło administratora Jenkins jest zapisane na stałe w generowanym fragmencie:

    JENKINS_ADMIN_PASSWORD=password

## Klucz SSH Jenkins

`custom_admin_authorized_key_file` wskazuje klucz publiczny, np.:

    /home/user/.ssh/binturo_deploy.pub

Jenkins potrzebuje klucza prywatnego. Generator automatycznie usuwa końcówkę
`.pub` i odczytuje:

    /home/user/.ssh/binturo_deploy

Ten sam klucz prywatny jest kopiowany do credentiali organizers i platformy.
Jeżeli prywatny odpowiednik nie istnieje, playbook przerwie działanie.

## Uruchamianie

Dev generuje środowisko Jenkins `local`:

    ansible-playbook -i inventories/dev/hosts.yml jenkins-local.yml \
      --vault-id dev@prompt \
      --diff

Staging:

    ansible-playbook -i inventories/staging/hosts.yml jenkins-local.yml \
      --vault-id staging@prompt \
      --diff

Produkcja:

    ansible-playbook -i inventories/prod/hosts.yml jenkins-local.yml \
      --vault-id prod@prompt \
      --diff

Playbook generuje dla wskazanego środowiska:

    <jenkins_output_dir>/config/organizers/<environment>.env
    <jenkins_output_dir>/config/platform/<environment>.env
    <jenkins_output_dir>/secrets/fragments/<environment>.properties
    <jenkins_output_dir>/secrets/keys/ORGANIZERS_<ENVIRONMENT>_SSH_KEY
    <jenkins_output_dir>/secrets/keys/PLATFORM_<ENVIRONMENT>_SSH_KEY

Plik `config/organizers/<environment>.env` zawiera również
`ORGANIZERS_<ENVIRONMENT>_MAINTENANCE_DIR`. Wartość pochodzi z
`caddy_maintenance_dir` i musi wskazywać ten sam katalog, w którym Caddy sprawdza
marker `organizers.enabled`. Korzystają z niej aktualne joby
`binturo-organizers-maintenance-enable` i
`binturo-organizers-maintenance-disable`.

Generuje także współdzielony fragment:

    <jenkins_output_dir>/secrets/fragments/shared.properties

## Łączenie fragmentów sekretów

Playbook celowo nie tworzy ani nie nadpisuje finalnego
`<jenkins_output_dir>/secrets/secrets.properties`. Generuje natomiast
dwa skrypty scalające:

    <jenkins_output_dir>/secrets/merge-secrets.sh
    <jenkins_output_dir>/secrets/merge-secrets.ps1

Uruchomienie w WSL:

    /mnt/d/projects/reservations/jenkins/secrets/merge-secrets.sh

Uruchomienie w PowerShell:

    & D:\projects\reservations\jenkins\secrets\merge-secrets.ps1

Skrypty sprawdzają kolejno fragmenty `shared`, `local`,
`staging` i `production`. Brak fragmentu powoduje ostrzeżenie,
ale nie przerywa scalania. Jeżeli nie istnieje żaden fragment, skrypt kończy się
błędem. Finalny plik jest zapisywany atomowo; wersja Bash nadaje mu uprawnienia
`0600`.

Wygenerowane fragmenty, finalny plik sekretów i prywatne klucze nie mogą być
commitowane. Po ich połączeniu uruchom Jenkins:

    .\jenkins\local\run-jenkins.ps1 -InstallPlugins
