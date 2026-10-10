# Backup i odtwarzanie PostgreSQL

## Zakres

Rola Ansible `postgres_backup` instaluje automatyczne, szyfrowane backupy logiczne
PostgreSQL oraz skrypt kontrolowanego odtwarzania bazy. Produkcja przesyła każdą
udaną kopię na staging. Staging tworzy własne kopie lokalne i przechowuje kopie
odebrane z produkcji.

Backupy wykonują się co trzy godziny. Domyślna polityka zachowuje:

- wszystkie punkty odtworzenia z ostatnich 24 godzin (zwykle około 8 plików);
- najnowszy punkt z każdego tygodnia ISO między 2. a 28. dniem;
- najnowszy punkt z każdego miesiąca kalendarzowego między 29. a 90. dniem.

Nadrzędna reguła bezwarunkowo usuwa pliki, które osiągnęły wiek 90 dni,
niezależnie od granicy tygodnia, miesiąca lub roku. Retencja jest wykonywana po
każdym udanym backupie i po każdym transferze. Staging na tej samej maszynie
testuje mechanizm, ale nie chroni przed utratą dysku lub całego hosta.

## Lokalizacje i format

Lokalne kopie znajdują się w `/srv/binturo/backups/local/prod/` oraz
`/srv/binturo/backups/local/staging/`. Kopie produkcyjne odebrane przez staging
znajdują się w `/srv/binturo/backups/remote/prod/`.

Każdy punkt składa się z zaszyfrowanego archiwum `pg_dump` oraz plików sumy
kontrolnej i metadanych:

```text
binturo_prod_20261004T001500Z.dump.gpg
binturo_prod_20261004T001500Z.dump.gpg.sha256
binturo_prod_20261004T001500Z.dump.gpg.json
```

Archiwum PostgreSQL używa formatu custom z kompresją zstd, a następnie jest
szyfrowane symetrycznie przez GnuPG/AES-256. Niezaszyfrowany plik istnieje tylko
w prywatnym katalogu tymczasowym na czas tworzenia albo odtwarzania kopii.

## Sekrety i klucz transferowy

Wygeneruj długie losowe hasło szyfrujące, co najmniej 32 znaki. Jeśli staging ma
umożliwiać testowe odtworzenie produkcyjnego backupu, wpisz tę samą wartość do
obu Vaultów:

```yaml
vault_postgres_backup_encryption_passphrase: "<losowa-wartość>"
```

Hasło daje dostęp do danych produkcyjnych, dlatego musi pozostać w Ansible Vault.

Wygeneruj osobny klucz, używany wyłącznie do transferu prod do staging:

```bash
ssh-keygen -t ed25519 -f postgres-backup-transfer -C binturo-postgres-backup-prod-to-staging
```

W Vault produkcji umieść klucz prywatny i przypięty klucz hosta staging:

```yaml
vault_postgres_backup_transfer_private_key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
vault_postgres_backup_transfer_known_host: "[146.59.3.169]:4285 ssh-ed25519 ..."
```

Klucz hosta należy pobrać z zaufanego kanału i porównać jego fingerprint na
staging. Nie akceptuj wyniku `ssh-keyscan` bez weryfikacji. W Vault staging
umieść publiczną część klucza:

```yaml
vault_postgres_backup_transfer_public_key: "ssh-ed25519 ... binturo-postgres-backup-prod-to-staging"
```

Ansible ogranicza ten klucz adresem IP produkcji oraz wymusza komendę odbiorczą.
Klucz nie może uruchamiać dowolnych poleceń, tworzyć tuneli ani przydzielać TTY.

## Wdrożenie

Najpierw wdroż staging, aby utworzyć odbiornik i autoryzować klucz, następnie
produkcję:

```bash
ansible-playbook -i inventories/staging/hosts.yml 03-site.yml --ask-vault-pass
ansible-playbook -i inventories/prod/hosts.yml 03-site.yml --ask-vault-pass
```

Sprawdź timer:

```bash
sudo systemctl status binturo-postgres-backup.timer
sudo systemctl list-timers binturo-postgres-backup.timer
```

## Test backupu i transferu

```bash
sudo systemctl start binturo-postgres-backup.service
sudo journalctl -u binturo-postgres-backup.service -n 100 --no-pager
```

Na produkcji sprawdź lokalny plik, a następnie odpowiadający mu plik na staging:

```bash
ls -l /srv/binturo/backups/local/prod/
ls -l /srv/binturo/backups/remote/prod/
sha256sum --check /srv/binturo/backups/remote/prod/<plik>.sha256
```

Nie uznawaj wdrożenia za zakończone wyłącznie na podstawie istnienia pliku.
Wykonaj próbne odtworzenie na staging.

## Odtwarzanie

Odtwarzanie jest operacją destrukcyjną. Skrypt:

1. wymaga uruchomienia jako root i jawnego potwierdzenia środowiska;
2. dopuszcza tylko pliki spod `/srv/binturo/backups/`;
3. weryfikuje SHA-256, odszyfrowuje plik i sprawdza katalog archiwum;
4. zatrzymuje timer i tworzy lokalny backup bezpieczeństwa aktualnej bazy;
5. włącza maintenance mode i zatrzymuje oba backendy;
6. usuwa i tworzy bazę, wykonuje `pg_restore`, a następnie bootstrap ról;
7. uruchamia backendy i ponownie uruchamia timer backupów.

Przykład odtworzenia staging z jego lokalnej kopii:

```bash
sudo /usr/local/sbin/binturo-postgres-restore \
  --backup /srv/binturo/backups/local/staging/binturo_staging_20261004T001500Z.dump.gpg \
  --confirm staging
```

Przykład testowego odtworzenia kopii produkcyjnej na staging:

```bash
sudo /usr/local/sbin/binturo-postgres-restore \
  --backup /srv/binturo/backups/remote/prod/binturo_prod_20261004T001500Z.dump.gpg \
  --confirm staging
```

Po udanym restore marker maintenance celowo pozostaje aktywny. Sprawdź logi,
healthchecki oraz wykonaj smoke test. Dopiero potem usuń marker zgodnie z
`docs/organizers-maintenance.md`:

```bash
sudo rm /srv/binturo/maintenance/organizers.enabled
```

Jeśli restore nie powiedzie się, maintenance pozostaje aktywny, a timer backupów
zostaje ponownie uruchomiony przez procedurę cleanup. Do wycofania użyj
automatycznie utworzonej kopii bezpieczeństwa.

## Diagnostyka

```bash
sudo journalctl -u binturo-postgres-backup.service --since today
sudo systemctl status binturo-postgres-backup.timer
sudo -u binturo /usr/local/sbin/binturo-postgres-backup --no-transfer
```

Opcja `--no-transfer` tworzy i rotuje lokalną kopię, ale nie wysyła jej na
staging. Jest używana także przed restore.

## Dalsze zabezpieczenia

Kopia produkcji na staging nie spełnia pełnej zasady 3-2-1. Następnym krokiem
powinien być szyfrowany, wersjonowany storage obiektowy na osobnym koncie oraz
alert, jeśli ostatni poprawny backup lub transfer jest starszy niż cztery
godziny. Procedurę odtwarzania należy testować co najmniej raz w miesiącu.
