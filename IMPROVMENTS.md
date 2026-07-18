# Proponowane usprawnienia i poprawki

Ten dokument jest backlogiem dalszych prac nad konfiguracją środowisk Binturo.
Obejmuje konfigurację hostów, PostgreSQL, Caddy, rootless Docker, monitoring,
bezpieczeństwo i odtwarzanie danych. Nie obejmuje procedury wdrażania aplikacji,
GitHub Actions ani zarządzania wersjami aplikacji.

## Priorytety

- **P0** — wymagane przed uruchomieniem produkcji;
- **P1** — zalecane krótko po uruchomieniu lub przed większym obciążeniem;
- **P2** — dalsze usprawnienia operacyjne.

## P0 — przed uruchomieniem produkcji

### 1. Test na czystym hoście Ubuntu

Obecny projekt został przygotowany statycznie i nie został jeszcze wykonany na
docelowym Ubuntu.

Zakres:

- uruchomić playbook dwukrotnie na czystej VM;
- potwierdzić idempotencję drugiego przebiegu;
- sprawdzić działanie `systemd --user` po restarcie hosta;
- sprawdzić rootless Docker, Compose, Caddy i wszystkie eksportery;
- wykonać `ansible-lint`, `yamllint` i `caddy validate`;
- przetestować zarówno inventory `dev`, jak i `prod`.

Kryterium akceptacji: drugi przebieg Ansible nie wykonuje nieuzasadnionych zmian,
a wszystkie usługi wracają po restarcie hosta bez logowania użytkownika `binturo`.

### 2. Walidacja zgodności wersji Caddy

Rola instaluje pakiet `caddy` z repozytorium Ubuntu. Dostępność opcji użytych w
globalnym bloku `servers` zależy od wersji pakietu.

Zakres:

- ustalić minimalną obsługiwaną wersję Caddy;
- przejść na oficjalne repozytorium Caddy, jeśli wersja Ubuntu jest zbyt stara;
- przypiąć wersję lub kontrolowany zakres wersji;
- dodać asercję wersji przed instalacją konfiguracji;
- zweryfikować socket administracyjny i `systemctl reload caddy`.

Kryterium akceptacji: playbook kończy się czytelnym błędem przed zmianą aktywnej
konfiguracji, jeżeli zainstalowana wersja Caddy nie obsługuje wymaganych opcji.

### 3. Backup i test odtworzenia PostgreSQL

Projekt tworzy konto `binturo_backup`, ale nie implementuje wykonywania backupów.

Zakres:

- dodać osobną rolę `backup`;
- wykonywać regularny `pg_dump` w formacie custom;
- szyfrować backupy przed wysłaniem poza host;
- przechowywać kopie poza serwerem aplikacyjnym;
- skonfigurować retencję;
- monitorować wiek ostatniego poprawnego backupu;
- okresowo automatyzować próbne odtworzenie do tymczasowej bazy.

Kryterium akceptacji: udokumentowany test odtwarza kompletną bazę i dynamiczne
schematy na pustej instancji PostgreSQL, a alert wykrywa brak świeżego backupu.

### 4. Backup współdzielonych plików

Katalog `/srv/binturo/shared/binturo-organizers-files` jest stanem aplikacyjnym i
nie jest objęty obecnym mechanizmem kopii zapasowej.

Zakres:

- ustalić oczekiwany RPO i RTO;
- wykonywać przyrostowe, szyfrowane kopie poza host;
- zachowywać właścicieli, tryby plików i znaczniki czasu;
- skoordynować spójność plików z backupem bazy, jeśli rekordy wskazują pliki;
- przeprowadzić test odtworzenia.

Kryterium akceptacji: pliki i odpowiadające im rekordy bazy można odtworzyć do
spójnego punktu w czasie.

### 5. Utwardzenie PostgreSQL

Zakres:

- jawnie skonfigurować `pg_hba.conf` i `listen_addresses`;
- dopuścić wyłącznie sieć kontenerową i wymagane role;
- ustawić `password_encryption = scram-sha-256`;
- odebrać zbędne uprawnienia do schematu `public`;
- zweryfikować, że `binturo_organizers_app` nie ma `CREATE`, DDL ani członkostwa
  w rolach uprzywilejowanych;
- ustawić sensowne limity połączeń per rola;
- dodać `statement_timeout`, `lock_timeout` i `idle_in_transaction_session_timeout`;
- włączyć logowanie wolnych zapytań oraz blokad.

Kryterium akceptacji: testy negatywne potwierdzają, że `binturo-organizers` nie może
tworzyć ani modyfikować struktur bazy, a potrzebne operacje DML działają.

### 6. Weryfikacja dynamicznych schematów

Zakres:

- dodać test SQL sprawdzający właściciela każdego schematu dynamicznego;
- sprawdzać granty dla istniejących tabel i sekwencji;
- sprawdzać `ALTER DEFAULT PRIVILEGES` dla przyszłych obiektów;
- raportować schematy częściowo skonfigurowane;
- zweryfikować bezpieczne cytowanie identyfikatorów w `binturo-platform`.

Kryterium akceptacji: automatyczny test tworzy schemat oraz tabelę po ustawieniu
default privileges i potwierdza wymagany dostęp `binturo_organizers_app`.

### 7. Obsługa sekretów i rotacja haseł

Zakres:

- wyeliminować długotrwałe przechowywanie sekretów w zwykłych plikach, jeśli
  docelowa platforma pozwoli użyć zewnętrznego secrets managera;
- opisać i przetestować rotację każdego hasła PostgreSQL;
- ustawić `no_log` dla wszystkich zadań mogących ujawnić sekret;
- sprawdzić, czy sekrety nie pojawiają się w `docker inspect`, logach lub diffie;
- rozważyć osobne konto tylko do metryk zamiast używania konta backupowego.

Kryterium akceptacji: hasła można zmienić bez rekonstrukcji wolumenu PostgreSQL,
a skan repozytorium i logów nie znajduje ich wartości.

### 8. Ograniczenia zasobów i miejsca na dysku

Zakres:

- ustawić limity pamięci, CPU, PID i otwartych plików dla kontenerów;
- zapewnić rezerwę miejsca dla PostgreSQL i Prometheusa;
- zweryfikować rotację logów rootless Docker;
- dodać alerty dla miejsca, inode, OOM i częstych restartów;
- ustalić zachowanie usług przy zapełnieniu dysku.

Kryterium akceptacji: kontrolowany test obciążeniowy jednej usługi nie powoduje
zatrzymania PostgreSQL ani całego hosta.

## P1 — zalecane usprawnienia

### 9. Poprawa monitorowania hosta

`node_exporter` działa obecnie w rootless Docker. Taki kontener może nie mieć pełnego
wglądu w przestrzenie PID, mounty i wszystkie zasoby hosta.

Rekomendacja:

- uruchomić `node_exporter` jako natywną, nieuprzywilejowaną usługę systemd;
- nasłuchiwać tylko na adresie prywatnym albo interfejsie VPN;
- ograniczyć dostęp firewallem;
- pozostawić Prometheusa w rootless Docker.

Kryterium akceptacji: metryki CPU, pamięci, dysków, filesystemów i systemd są zgodne
z narzędziami hosta i nie opisują wyłącznie kontenera eksportera.

### 10. Trwałe przesyłanie metryk

Standardowy Prometheus `remote_write` może utracić niesłane próbki po dłuższej
niedostępności odbiorcy i kompaktowaniu WAL.

Zakres:

- ustalić maksymalny czas braku łączności;
- dla krótkich przerw monitorować kolejkę `remote_write` i WAL;
- dla długich przerw rozważyć vmagent z trwałą kolejką, VictoriaMetrics, Mimir albo
  Thanos z magazynem obiektowym;
- jeśli dane muszą być pobierane, pobierać zakres historyczny z checkpointem zamiast
  wykonywać zwykły okresowy scrape;
- zabezpieczyć transport prywatną siecią i uwierzytelnieniem.

Kryterium akceptacji: test przerwy dłuższej od zadeklarowanego maksimum nie powoduje
luki w centralnym magazynie metryk.

### 11. Reguły alertów

Dodać alerty co najmniej dla:

- niedostępności backendów i PostgreSQL;
- braku metryk z hosta;
- wysokiego użycia CPU, RAM, dysku i inode;
- restartów kontenerów;
- liczby i czasu połączeń PostgreSQL;
- blokad, deadlocków i wolnych zapytań;
- wieku backupu;
- wygasania certyfikatów;
- zalegającego `remote_write`.

Kryterium akceptacji: każdy alert ma test, opis skutku i krótką instrukcję reakcji.

### 12. Bezpieczeństwo Caddy zależne od aplikacji

Obecny snippet zapewnia bezpieczną bazę, ale część nagłówków wymaga wiedzy o
frontendzie i integracjach.

Zakres:

- opracować CSP osobno dla każdego frontendu;
- rozpocząć od `Content-Security-Policy-Report-Only`;
- dodać endpoint raportów CSP;
- ustalić, czy `X-Frame-Options: DENY` nie koliduje z osadzaniem aplikacji;
- zweryfikować limit request body dla uploadów;
- rozważyć osobne limity dla API i uploadów;
- włączyć `includeSubDomains` w HSTS dopiero po audycie wszystkich subdomen;
- dodać rate limiting na poziomie Caddy lub zewnętrznej warstwy, jeśli aplikacje nie
  realizują go samodzielnie.

Kryterium akceptacji: skaner nagłówków i testy przeglądarkowe nie wykazują regresji,
a CSP działa w trybie wymuszającym bez nieoczekiwanych naruszeń.

### 13. Dostęp administracyjny przez VPN

Zakres:

- skonfigurować WireGuard albo równoważną prywatną sieć;
- ograniczyć SSH i endpointy monitoringu do VPN, jeśli jest to operacyjnie możliwe;
- nie publikować PostgreSQL ani API administratora Caddy;
- dodać oddzielne reguły UFW dla interfejsu prywatnego.

Kryterium akceptacji: publiczny skan hosta widzi wyłącznie świadomie wystawione
porty, a Prometheus i interfejsy administracyjne są dostępne tylko prywatnie.

### 14. Aktualizacje bezpieczeństwa Ubuntu

Zakres:

- skonfigurować `unattended-upgrades` dla aktualizacji bezpieczeństwa;
- ustalić okno restartów;
- wykrywać wymagany restart hosta;
- monitorować nieudane aktualizacje;
- wykonywać kontrolowane aktualizacje Docker, Caddy i PostgreSQL.

Kryterium akceptacji: host raportuje stan aktualizacji i nie pozostaje przez długi
czas z krytycznymi podatnościami bez widocznego alertu.

### 15. Parametryzacja architektury i dystrybucji

`docker_apt_arch` ma obecnie wartość `amd64`, a role zakładają Ubuntu.

Zakres:

- wyliczać architekturę repozytorium z facts Ansible;
- dodać asercję obsługiwanej dystrybucji i wydania;
- sprawdzić `arm64`, jeśli może pojawić się w przyszłości;
- jawnie deklarować wspierane wersje Ubuntu w README.

Kryterium akceptacji: nieobsługiwany host jest odrzucany przed wykonaniem zmian.

## P2 — dalszy rozwój

### 16. Molecule i testy ról

Zakres:

- dodać Molecule dla ról niezależnych od systemd user;
- testować renderowane pliki Compose i Caddy;
- testować SQL bootstrap na tymczasowym PostgreSQL;
- dodać `ansible-lint`, `yamllint`, `markdownlint` oraz skan sekretów.

Kryterium akceptacji: każda zmiana roli przechodzi automatyczne testy składni,
idempotencji i podstawowych właściwości bezpieczeństwa.

### 17. Kontrola wersji obrazów

Zakres:

- przypinać obrazy po digest zamiast wyłącznie po tagu;
- dokumentować proces aktualizacji obrazów infrastrukturalnych;
- skanować obrazy pod kątem podatności;
- usuwać nieużywane obrazy w sposób kontrolowany i bez naruszania rollbacku danych;
- monitorować dostępność nowych wersji bezpieczeństwa.

Kryterium akceptacji: odtworzenie hosta używa dokładnie tych samych zweryfikowanych
obrazów, dopóki ich wersje nie zostaną świadomie zmienione.

### 18. Strojenie PostgreSQL

Zakres:

- dobrać `shared_buffers`, `work_mem`, `maintenance_work_mem` i parametry WAL do
  zasobów hosta;
- ustawić `max_connections` na podstawie pul połączeń backendów;
- rozważyć PgBouncer przy dużej liczbie krótkich połączeń;
- włączyć `pg_stat_statements`;
- obserwować autovacuum i rozrost tabel;
- przygotować plan aktualizacji głównej wersji PostgreSQL.

Kryterium akceptacji: parametry wynikają z pomiarów, a nie tylko z wartości
domyślnych; istnieje przetestowana procedura przejścia na kolejną główną wersję.

### 19. Audyt i retencja logów

Zakres:

- ustalić centralne miejsce przechowywania logów;
- zdefiniować retencję i ograniczenia danych osobowych;
- zapewnić korelację request ID pomiędzy Caddy i backendami;
- nie logować tokenów, cookies, haseł ani treści wrażliwych;
- rozważyć `pgaudit` tylko po określeniu wymagań audytowych i kosztu logowania.

Kryterium akceptacji: incydent można prześledzić pomiędzy proxy, backendem i bazą,
bez ujawniania sekretów w logach.

### 20. Dokumentacja operacyjna

Przygotować krótkie runbooki dla:

- braku miejsca na dysku;
- niedostępności PostgreSQL;
- zablokowanej migracji wykonywanej przez `binturo-platform`;
- błędnych uprawnień dynamicznego schematu;
- utraty połączenia z centralnym monitoringiem;
- odnowienia i diagnostyki certyfikatów Caddy;
- odtworzenia bazy i współdzielonych plików.

Kryterium akceptacji: osoba nieuczestnicząca w budowie środowiska potrafi wykonać
diagnostykę i bezpieczne odtworzenie na podstawie samej dokumentacji.

## Świadomie poza zakresem

Ten backlog nie obejmuje:

- GitHub Actions;
- sposobu kopiowania katalogów i artefaktów;
- budowania obrazów aplikacyjnych;
- przełączania wersji aplikacji;
- aplikacyjnego rollbacku;
- kolejności wdrażania backendów i frontendów.

Te zagadnienia powinny zostać opisane osobno, gdy zakres prac zostanie rozszerzony o
procedurę wdrożeniową.
