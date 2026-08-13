# Dynamiczna konfiguracja Caddy

Pliki witryn znajdują się w `/etc/caddy/sites-enabled`. Główny `Caddyfile` importuje
wszystkie pliki z tego katalogu. Ansible zarządza plikami `10-platform.caddy` i
`20-organizers.caddy`; inne procesy mogą dodawać osobne pliki o innych nazwach.

Każda publiczna witryna musi importować snippet `binturo_common`. Zapewnia on
wspólne limity, nagłówki bezpieczeństwa oraz blokadę typowych plików wrażliwych.
Logowanie dostępu jest konfigurowane osobno dla każdej witryny:

- platforma: `/var/log/caddy/platform.log`;
- organizator (staff, trainer i client): `/var/log/caddy/organizers.log`.

Logi mają format JSON i są rotowane przez Caddy codziennie o północy czasu
lokalnego. Rotacja zachowuje maksymalnie 31 plików nie starszych niż 31 dni.
Limit `100MiB` powoduje dodatkową rotację, jeżeli plik urośnie do tego rozmiaru
przed północą. Zmienne `caddy_log_*` w `group_vars/all.yml` pozwalają zmienić te
ustawienia.

Środowisko `dev` używa `caddy_tls_internal: true`, ponieważ domeny `.warszawa` nie
kwalifikują się do publicznego ACME. Urządzenia klienckie muszą ufać lokalnemu root
CA Caddy. Produkcja używa `caddy_tls_cloudflare_origin: true` i certyfikatu
Cloudflare Origin CA przechowywanego w Vault. Cloudflare musi mieć włączony proxy
dla rekordów DNS i tryb `Full (strict)`.

Konfiguracja `binturo-platform` kieruje `/api` i `/api/*` do backendu, a pozostały
ruch obsługuje jako statyczną aplikację SPA:

```caddyfile
platform.example.com {
    import binturo_common

    @backend_api path /api /api/*
    handle @backend_api {
        reverse_proxy 127.0.0.1:18101
    }
    handle {
        root * /srv/binturo/apps/frontend-platform
        try_files {path} /index.html
        file_server
    }
}
```

Trzy frontendy `binturo-organizers` współdzielą jedną domenę i są rozdzielone
prefiksami `/staff`, `/trainer` i `/client`:

```caddyfile
app.example.com {
    import binturo_common

    @backend_api path /api /api/*
    handle @backend_api {
        reverse_proxy 127.0.0.1:18102
    }
    handle_path /staff/* {
        root * /srv/binturo/apps/frontend-organizers/staff
        try_files {path} /index.html
        file_server
    }
    handle_path /trainer/* {
        root * /srv/binturo/apps/frontend-organizers/trainer
        try_files {path} /index.html
        file_server
    }
    handle_path /client/* {
        root * /srv/binturo/apps/frontend-organizers/client
        try_files {path} /index.html
        file_server
    }
    redir / /staff/login
}
```

`handle_path` usuwa prefiks aplikacji przed wyszukaniem pliku w jej katalogu.
Prefiks `/api` nie jest usuwany. Backend musi więc obsługiwać ścieżki zaczynające się
od `/api` i nasłuchiwać wyłącznie na `127.0.0.1`. Frontendy nie uruchamiają osobnych
serwerów: proces budowania npm zapisuje gotowe pliki w katalogach wskazanych przez
`binturo_frontend_roots`, a Caddy odczytuje je bezpośrednio. Frontendy organizers
`staff`, `trainer` i `client` są ponadto dostępne lokalnie odpowiednio na portach
`18201`, `18202` i `18203`; porty są konfigurowane przez `binturo_frontend_ports`
i nasłuchują wyłącznie na `127.0.0.1`. `try_files` zapewnia
fallback do `index.html` dla routingu po stronie Reacta.

Na produkcji matcher `remote_ip` rozpoznaje oficjalne zakresy IPv4 i IPv6
Cloudflare. Tylko dla takich połączeń Caddy ustawia `X-Real-IP` i
`X-Forwarded-For` na pojedynczą wartość `CF-Connecting-IP`. Dla wejścia
bezpośredniego używany jest adres TCP. Listy `caddy_cloudflare_ipv4_ranges` i
`caddy_cloudflare_ipv6_ranges` należy aktualizować, gdy Cloudflare zmieni oficjalne
zakresy.

Ręcznie dodawany plik należy najpierw zapisać pod nazwą tymczasową poza
`sites-enabled`, sformatować, zweryfikować pełną konfigurację, a dopiero potem
atomowo przenieść do katalogu importowanego i przeładować Caddy. Nie edytuj ręcznie
plików zarządzanych przez Ansible.

## Statyczna strona WWW

Rola `directory_layout` przygotowuje katalog `/srv/binturo/apps/www`, a Caddy
udostępnia go jako zwykły katalog plików statycznych. Ansible nie kopiuje ani nie
usuwa jego zawartości. Pliki strony należy umieszczać na hoście jako użytkownik
`binturo`.

Domeny są jawnie określone w inventory przez `binturo_domains.www`:

- dev: `www.binturo.warszawa`;
- staging: `www-staging.binturo.com`;
- prod: `www.binturo.com`.

Przykładowe umieszczenie strony:

```bash
sudo -iu binturo
cp -a /ścieżka/do/witryny/. /srv/binturo/apps/www/
```

Punktem wejścia powinien być `/srv/binturo/apps/www/index.html`. Konfiguracja
znajduje się w `/etc/caddy/sites-enabled/05-www.caddy`, a log dostępu w
`/var/log/caddy/www.log`. Przed użyciem domeny należy utworzyć odpowiedni rekord
DNS; na staging i prod musi on wskazywać przez Cloudflare na właściwy host.

## Zastosowany hardening

Konfiguracja bazowa:

- wiąże każdą witrynę HTTPS jawnie do `0.0.0.0` oraz `[::]`, niezależnie od
  ustawienia `net.ipv6.bindv6only` kernela;
- udostępnia API administracyjne Caddy wyłącznie na `127.0.0.1:2019`, zgodnie z
  mechanizmem reload dostarczanym przez pakiet Ubuntu;
- wymaga zgodności nagłówka `Host` z TLS SNI;
- ogranicza nagłówki HTTP do 32 KB;
- ustawia timeout nagłówków, body, odpowiedzi i bezczynnych połączeń;
- zachowuje krótki okres łagodnego zamykania podczas restartu;
- pozostawia włączone wyłącznie HTTP/1.1 i HTTP/2, bez h2c i HTTP/3;
- nie uruchamia listenera przekierowań HTTP na porcie 80.

Snippet witryny:

- wyłącza challenge ACME HTTP-01 i korzysta z TLS-ALPN-01 na porcie 443;
- ogranicza request body domyślnie do 25 MB;
- usuwa nagłówki `Server` i `X-Powered-By`;
- dodaje HSTS, `nosniff`, politykę referrera i blokadę osadzania w ramce;
- wyłącza niepotrzebne funkcje przeglądarki przez `Permissions-Policy`;
- zwraca 404 dla typowych plików repozytorium i konfiguracji.

Wartości limitów można zmienić w `group_vars/all.yml`. `includeSubDomains` dla HSTS
jest domyślnie wyłączone. Należy je włączyć dopiero wtedy, gdy wszystkie subdomeny
są stale obsługiwane wyłącznie przez HTTPS.

Ponieważ port 80 jest zamknięty, adresy wpisane jawnie z prefiksem `http://` nie są
przekierowywane. Rekord DNS domeny musi wskazywać host, a publiczny `443/tcp` musi
być dostępny dla challenge TLS-ALPN-01. Jeżeli urząd certyfikacji nie obsługuje tego
challenge, należy skonfigurować DNS-01 i odpowiedni moduł dostawcy DNS w Caddy.

Nie ustawiono globalnego `Content-Security-Policy`, ponieważ poprawna polityka zależy
od zasobów, skryptów, dostawców logowania i połączeń używanych przez konkretny
frontend. CSP należy dodać osobno w jego pliku witryny po przetestowaniu najpierw
w trybie `Content-Security-Policy-Report-Only`.
