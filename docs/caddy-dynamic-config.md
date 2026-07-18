# Dynamiczna konfiguracja Caddy

Pliki witryn należy umieszczać w `/etc/caddy/sites-enabled`. Główny `Caddyfile`
importuje wszystkie pliki z tego katalogu.

Przykład dla `binturo-platform`:

```caddyfile
platform.example.com {
    import binturo_common
    reverse_proxy 127.0.0.1:18101
}
```

Przykład dla `binturo-organizers`:

```caddyfile
organizers.example.com {
    import binturo_common
    reverse_proxy 127.0.0.1:18102
}
```

Frontend można wystawić jako osobną domenę albo obsłużyć przez `handle`, zależnie od
docelowego routingu. Kontenery aplikacyjne powinny publikować porty wyłącznie na
`127.0.0.1`.

Plik należy najpierw zapisać pod nazwą tymczasową poza `sites-enabled`, sformatować,
zweryfikować pełną konfigurację, a dopiero potem atomowo przenieść do katalogu
importowanego i przeładować Caddy.

