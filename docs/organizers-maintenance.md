# Tryb maintenance aplikacji organizatora

Tryb maintenance chroni klientów przed częściowo wdrożoną wersją aplikacji.
Obejmuje wyłącznie domenę organizatora i ścieżki `/staff`, `/trainer`, `/client`
oraz `/api`. Platforma i strona `www` działają bez zmian.

## Jak działa

Caddy przy każdym żądaniu sprawdza istnienie markera:

```text
<caddy_maintenance_dir>/organizers.enabled
```

Domyślnie jest to `/srv/binturo/maintenance/organizers.enabled`. Ansible tworzy
katalog i stronę `index.html`, ale celowo nie tworzy ani nie usuwa markera. Dzięki
temu workflow przełącza maintenance bez zmiany Caddyfile i bez `caddy reload`.

Przy aktywnym markerze zwykły użytkownik otrzymuje:

- dla frontendu: statyczną stronę maintenance i HTTP 503;
- dla `/api`: JSON z komunikatem, HTTP 503, `Retry-After` i `Cache-Control: no-store`.

## Dostęp operatora

Operator otwiera:

```text
https://<domena-organizatora>/__maintenance-access
```

Caddy żąda Basic Auth. Po poprawnym logowaniu ustawia bezpieczne, krótkotrwałe
cookie bypass i przekierowuje na `/staff/login`. Przeglądarka operatora korzysta
potem z prawdziwego frontendu i API na tej samej domenie co klienci. Pozwala to
sprawdzić TLS, routing, CORS, logowanie i procesy biznesowe przed zakończeniem
przerwy technicznej.

Cookie jest `Secure`, `HttpOnly`, `SameSite=Strict`, działa dla całej domeny i
domyślnie wygasa po czterech godzinach. Token nie występuje w URL ani access logu.
Po wyłączeniu maintenance cookie nie zmienia zachowania aplikacji.

## Sekrety w Vault

Każde inventory wymaga dwóch wartości:

```yaml
vault_caddy_maintenance_basic_auth_password_hash: '$2a$14$...'
vault_caddy_maintenance_bypass_token: '<losowy-token-base64url>'
```

Hash hasła wygeneruj na zaufanej maszynie z Caddy:

```bash
caddy hash-password
```

Wprowadź mocne, unikalne hasło operatorskie i zapisz tylko wynikowy hash w Vault.
Samo hasło przekaż operatorom bezpiecznym kanałem. Token można wygenerować:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
```

Token powinien mieć co najmniej 43 znaki i być inny w dev, staging i prod. Po
uzupełnieniu Vault uruchom playbook `site` dla środowiska. Zadanie instalujące
sekretny szablon Caddy ma `no_log`, aby hash i token nie trafiły do logów Ansible
ani Semaphore.

## Ręczne przełączanie na serwerze

Jako użytkownik aplikacyjny `binturo`:

```bash
# Włączenie
touch /srv/binturo/maintenance/organizers.enabled
chmod 0640 /srv/binturo/maintenance/organizers.enabled

# Wyłączenie
rm -f /srv/binturo/maintenance/organizers.enabled
```

Nie wykonuj `caddy reload`. Caddy zauważa marker przy kolejnym żądaniu.

Weryfikacja bez cookie operatora:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://app.binturo.com/staff/login
curl -sS -o /dev/null -w '%{http_code}\n' https://app.binturo.com/api/health
```

Przy maintenance oba wywołania powinny zwrócić `503`; po wyłączeniu odpowiednio
kod aplikacji i API.

## Zalecany przebieg wdrożenia

1. Workflow tworzy marker i potwierdza publiczne HTTP 503.
2. Zatrzymuje backend organizatora.
3. Wdraża backend i trzy frontendowe buildy.
4. Uruchamia backend i sprawdza healthcheck bezpośrednio po loopbacku serwera.
5. Marker pozostaje aktywny także po technicznie poprawnym deployu.
6. Operator loguje się przez `__maintenance-access` i wykonuje smoke test.
7. Osobny workflow `disable-maintenance.yml`, po świadomej decyzji operatora,
   usuwa marker i sprawdza publiczną dostępność.

Nie usuwaj markera w kroku `always()` ani automatycznie po samym healthchecku.
W przypadku nieudanego lub częściowego wdrożenia klienci powinni nadal widzieć
kontrolowany komunikat 503.

## GitHub Environment

Lokalny generator `github-local.yml` ustawia dodatkową variable:

```text
DEPLOY_MAINTENANCE_DIR=/srv/binturo/maintenance
```

Workflowy przełączające maintenance powinny logować się jako `DEPLOY_SSH_USER`,
ale tworzyć i usuwać marker jako `DEPLOY_SSH_SUDO_USER`, zgodnie z tym samym
modelem `sudo -n` co workflowy wdrożeniowe.

## Cofnięcie dostępu operatorskiego

W razie podejrzenia ujawnienia hasła lub cookie:

1. wygeneruj nowe hasło i token;
2. zmień obie wartości w Vault;
3. uruchom playbook `site`, aby przeładować Caddy;
4. stare cookie przestaną pasować natychmiast.
