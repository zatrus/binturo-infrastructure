# Prompt do wdrożenia workflowów maintenance w `reservations`

```text
Pracujesz w repozytorium D:\projects\reservations.

Repozytorium D:\projects\reservation-stack ma już przygotowany tryb maintenance
aplikacji organizatora. Przeczytaj docs/organizers-maintenance.md i szablon
roles/caddy/templates/organizers-site.caddy.j2 w tamtym repo, a w bieżącym repo
istniejące workflowy deploy/start/stop, GITHUB_WORKFLOWS.md oraz właściwe pliki
AGENTS.md/CLAUDE.md/JENKINS.md.

Nie zmieniaj reservation-stack. Zaimplementuj część workflowową poniżej.

KONTRAKT INFRASTRUKTURY

- marker: $DEPLOY_MAINTENANCE_DIR/organizers.enabled;
- DEPLOY_MAINTENANCE_DIR jest GitHub Environment variable;
- SSH jako DEPLOY_SSH_USER, operacje jako DEPLOY_SSH_SUDO_USER przez sudo -n;
- marker daje klientom HTTP 503 dla /staff, /trainer, /client i /api;
- operator z cookie z /__maintenance-access widzi prawdziwą aplikację;
- nie wykonuj caddy reload.

1. Dodaj `.github/workflows/enable-maintenance.yml`: workflow_dispatch z inputem
`environment` typu environment; minimalne permissions, timeout i concurrency;
walidacja wszystkich DEPLOY_SSH_* oraz DEPLOY_MAINTENANCE_DIR; konfiguracja SSH
jak w deployach; atomowe utworzenie markera w trybie 0640 przez sudo -n jako
DEPLOY_SSH_SUDO_USER; publiczna weryfikacja HTTP 503 na BINTURO_STAFF_APP_URL;
GITHUB_STEP_SUMMARY. Operacja ma być idempotentna.

2. Dodaj `.github/workflows/disable-maintenance.yml` z tym samym kontraktem.
Przed usunięciem wykonaj po SSH healthcheck backendu na
127.0.0.1:${BINTURO_BACKEND_LISTEN_PORT}/api/health. Jeśli backend nie jest
zdrowy, nie usuwaj markera. Usuń wyłącznie dokładny plik organizers.enabled przez
rm -f jako DEPLOY_SSH_SUDO_USER. Po usunięciu publiczny URL staff nie może zwracać
503. Brak markera nie jest błędem, ale oba testy nadal są wymagane.

3. Zmień deploy-organizator.yml: przed zatrzymaniem backendu utwórz marker i
potwierdź publiczne 503. Dodaj/zwaliduj DEPLOY_MAINTENANCE_DIR. Po deployu, starcie
i loopback healthchecku NIE usuwaj markera. Nie usuwaj go w always(), cleanupie
ani przy błędzie. W podsumowaniu podaj URL /__maintenance-access i polecenie
uruchomienia disable-maintenance.yml po smoke teście operatora. Nie zmieniaj
deploy-platform.yml; maintenance dotyczy organizatora.

4. Zaktualizuj GITHUB_WORKFLOWS.md: variable DEPLOY_MAINTENANCE_DIR, oba nowe
workflowy, procedura enable → deploy → dostęp operatora → smoke test → disable,
zachowanie 503/Retry-After, rollback z markerem oraz przykłady:

gh workflow run enable-maintenance.yml -f environment=staging
gh workflow run disable-maintenance.yml -f environment=staging

WYMAGANIA BEZPIECZEŃSTWA

- ścieżka maintenance musi być absolutna i walidowana;
- nie przyjmuj nazwy markera jako inputu;
- wszystkie kroki bash: set -euo pipefail;
- wszystkie operacje markera: sudo -n i DEPLOY_SSH_SUDO_USER;
- workflow nie zna hasła Basic Auth ani tokenu bypass;
- nie wypisuj sekretów;
- nie uruchamiaj prawdziwych workflowów ani połączeń do serwerów.

WERYFIKACJA

- parser YAML/actionlint wszystkich zmienionych workflowów;
- git diff --check;
- wyszukiwaniem potwierdź, że marker jest usuwany wyłącznie w
  disable-maintenance.yml, nigdy w deploy-organizator.yml;
- sprawdź zgodność vars/secrets z generatorami;
- nie commituj i nie pushuj;
- na końcu wypisz zmienione pliki, wyniki testów i ryzyka.
```
