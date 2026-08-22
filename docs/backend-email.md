# Konfiguracja wysyłki e-maili

Oba backendy obsługują klienta testowego `mock` oraz rzeczywistą wysyłkę przez
MailerSend lub serwer SMTP. Każdy backend ma niezależną konfigurację.

## Zmienne inventory

W `inventories/<environment>/group_vars/all/vars.yml` znajdują się jawne
ustawienia:

```yaml
organizers_email_client: mock
organizers_mailersend_from_email: ""
organizers_mailersend_from_name: Binturo
organizers_smtp_host: ""
organizers_smtp_port: 587
organizers_smtp_from_email: ""
organizers_smtp_from_name: Binturo
organizers_smtp_use_tls: true
organizers_smtp_use_ssl: false
organizers_smtp_routed_domains: ""

platform_email_client: mock
platform_mailersend_from_email: ""
platform_mailersend_from_name: Binturo Platform
platform_smtp_host: ""
platform_smtp_port: 587
platform_smtp_from_email: ""
platform_smtp_from_name: Binturo Platform
platform_smtp_use_tls: true
platform_smtp_use_ssl: false
platform_smtp_routed_domains: ""
```

Dozwolone wartości `*_email_client` to:

- `mock` — wiadomości nie są wysyłane do zewnętrznego dostawcy;
- `mailersend` — rzeczywista wysyłka przez MailerSend;
- `smtp` — wysyłka przez wskazany serwer SMTP;
- `domain_routed` — SMTP tylko dla odbiorców z domen wymienionych w
  `*_smtp_routed_domains`, a klient `mock` dla pozostałych odbiorców.

Przy `mailersend` adres `*_mailersend_from_email` musi należeć do domeny
zweryfikowanej w MailerSend.

Przy `smtp` należy podać host, port i dane nadawcy. Dokładnie jeden z
parametrów `*_smtp_use_tls` (STARTTLS, zwykle port 587) oraz
`*_smtp_use_ssl` (niejawny TLS, zwykle port 465) musi mieć wartość `true`.
Klient `domain_routed` wymaga tego samego kompletu ustawień SMTP oraz niepustej,
rozdzielonej przecinkami listy domen, np. `bemerken.uk,inna-domena.pl`.

## Sekrety

W `inventories/<environment>/group_vars/all/vault.yml` należy umieścić osobne
klucze obu backendów:

```yaml
vault_organizers_mailersend_api_key: "KLUCZ_ORGANIZATORA"
vault_platform_mailersend_api_key: "INNY_KLUCZ_PLATFORMY"
vault_organizers_smtp_username: "LOGIN_SMTP_ORGANIZATORA"
vault_organizers_smtp_password: "HASLO_SMTP_ORGANIZATORA"
vault_platform_smtp_username: "LOGIN_SMTP_PLATFORMY"
vault_platform_smtp_password: "HASLO_SMTP_PLATFORMY"
```

Przy kliencie `mock` wartości mogą pozostać puste. Playbook przerwie
generowanie, jeśli konfiguracja wybranego klienta `mailersend` albo `smtp`
jest niekompletna.

## Pliki generowane dla Jenkins

Jawne właściwości trafiają do plików `config/organizers/<environment>.env` i
`config/platform/<environment>.env`:

```properties
ORGANIZERS_DEV_EMAIL_CLIENT=mailersend
ORGANIZERS_DEV_MAILERSEND_FROM_EMAIL=no-reply@example.com
ORGANIZERS_DEV_MAILERSEND_FROM_NAME=Binturo
```

Dla SMTP generator zapisuje również `SMTP_HOST`, `SMTP_PORT`,
`SMTP_FROM_EMAIL`, `SMTP_FROM_NAME`, `SMTP_USE_TLS`, `SMTP_USE_SSL` i
`SMTP_ROUTED_DOMAINS` z prefiksem aplikacji i środowiska, na przykład
`ORGANIZERS_DEV_SMTP_HOST`.

Klucze API trafiają do `secrets/fragments/<environment>.properties`:

```properties
ORGANIZERS_DEV_MAILERSEND_API_KEY=...
PLATFORM_DEV_MAILERSEND_API_KEY=...
ORGANIZERS_DEV_SMTP_USERNAME=...
ORGANIZERS_DEV_SMTP_PASSWORD=...
PLATFORM_DEV_SMTP_USERNAME=...
PLATFORM_DEV_SMTP_PASSWORD=...
```

Po ponownym uruchomieniu `jenkins-local.yml` należy wykonać wygenerowany skrypt
`merge-secrets.sh` albo `merge-secrets.ps1`, aby odtworzyć końcowy plik
`secrets/secrets.properties`.

## Konfiguracja GitHub Actions

Playbook `github-local.yml` generuje skrypty, które ustawiają te same wartości
w GitHub Environments. Jawne parametry SMTP są zapisywane jako zmienne, na
przykład `BINTURO_SMTP_HOST`, `BINTURO_SMTP_ROUTED_DOMAINS` i
`BINTURO_PLATFORM_SMTP_USE_TLS`. Login i hasło
są zapisywane jako sekrety:

```text
BINTURO_SMTP_USERNAME
BINTURO_SMTP_PASSWORD
BINTURO_PLATFORM_SMTP_USERNAME
BINTURO_PLATFORM_SMTP_PASSWORD
```

Skrypty korzystają z wartości inventory i Vault właściwych dla każdego
środowiska (`dev`, `staging`, `prod`).
