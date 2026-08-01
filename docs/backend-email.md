# Konfiguracja wysyłki e-maili

Oba backendy obsługują klienta testowego `mock` oraz rzeczywistą wysyłkę przez
MailerSend. Każdy backend ma niezależną konfigurację i osobny klucz API.

## Zmienne inventory

W `inventories/<environment>/group_vars/all/vars.yml` znajdują się jawne
ustawienia:

```yaml
organizers_email_client: mock
organizers_mailersend_from_email: ""
organizers_mailersend_from_name: Binturo

platform_email_client: mock
platform_mailersend_from_email: ""
platform_mailersend_from_name: Binturo Platform
```

Dozwolone wartości `*_email_client` to:

- `mock` — wiadomości nie są wysyłane do zewnętrznego dostawcy;
- `mailersend` — rzeczywista wysyłka przez MailerSend.

Przy `mailersend` adres `*_mailersend_from_email` musi należeć do domeny
zweryfikowanej w MailerSend.

## Sekrety

W `inventories/<environment>/group_vars/all/vault.yml` należy umieścić osobne
klucze obu backendów:

```yaml
vault_organizers_mailersend_api_key: "KLUCZ_ORGANIZATORA"
vault_platform_mailersend_api_key: "INNY_KLUCZ_PLATFORMY"
```

Przy kliencie `mock` wartości mogą pozostać puste. Przy `mailersend` playbook
przerwie generowanie, jeśli zabraknie klucza API albo adresu nadawcy.

## Pliki generowane dla Jenkins

Jawne właściwości trafiają do plików `config/organizers/<environment>.env` i
`config/platform/<environment>.env`:

```properties
ORGANIZERS_DEV_EMAIL_CLIENT=mailersend
ORGANIZERS_DEV_MAILERSEND_FROM_EMAIL=no-reply@example.com
ORGANIZERS_DEV_MAILERSEND_FROM_NAME=Binturo
```

Klucze API trafiają do `secrets/fragments/<environment>.properties`:

```properties
ORGANIZERS_DEV_MAILERSEND_API_KEY=...
PLATFORM_DEV_MAILERSEND_API_KEY=...
```

Po ponownym uruchomieniu `jenkins-local.yml` należy wykonać wygenerowany skrypt
`merge-secrets.sh` albo `merge-secrets.ps1`, aby odtworzyć końcowy plik
`secrets/secrets.properties`.
