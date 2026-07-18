# Instalacja Ansible w środowisku Python

Ansible jest instalowany na komputerze sterującym jako pakiet Pythona w lokalnym
środowisku wirtualnym `.venv`. Na zarządzanych hostach Ubuntu nie instaluje się
serwera ani agenta Ansible — wymagane są jedynie SSH i Python.

## Wymagania

Komputer sterujący powinien posiadać:

- system Linux albo Windows z WSL2;
- Python 3.14;
- moduł `venv`;
- `pip`;
- klienta OpenSSH;
- dostęp sieciowy SSH do hostów `dev` i `prod`.

Ansible nie obsługuje natywnego Windows jako control node. Na Windows należy użyć
WSL2, np. Ubuntu, i wykonywać poniższe polecenia w terminalu WSL.

### Lokalizacja repozytorium w WSL

Zaleca się przechowywanie repozytorium w systemie plików WSL, np. w
`~/projects/reservation-stack`, a nie bezpośrednio pod `/mnt/c` lub `/mnt/d`.
Domyślne opcje montowania dysków Windows mogą przedstawiać taki katalog jako
zapisywalny dla wszystkich użytkowników. Ansible traktuje to jako ryzyko i celowo
ignoruje znajdujący się tam `ansible.cfg`.

Najbezpieczniejszy wariant to sklonowanie repozytorium wewnątrz WSL:

```bash
mkdir -p ~/projects
cd ~/projects
git clone ADRES_REPOZYTORIUM reservation-stack
cd reservation-stack
```

Następnie utwórz `.venv` ponownie w nowej lokalizacji. Nie kopiuj istniejącego
środowiska wirtualnego, ponieważ jego skrypty zawierają ścieżki do starego katalogu.

Jeżeli repozytorium tymczasowo musi pozostać pod `/mnt/d`, można jawnie wskazać plik
konfiguracyjny dla bieżącej sesji:

```bash
export ANSIBLE_CONFIG="$PWD/ansible.cfg"
ansible-config view
```

Jest to obejście, a nie docelowe rozwiązanie. Należy go używać tylko wtedy, gdy
katalog nie jest zapisywalny przez niezaufanych użytkowników i procesy. Ansible
ignoruje automatycznie konfigurację z world-writable directory właśnie po to, aby
uniemożliwić podstawienie złośliwego `ansible.cfg` przed wykonaniem zadań jako root.

Alternatywnie można włączyć obsługę metadanych uprawnień WSL dla montowanych dysków
Windows. W pliku `/etc/wsl.conf`:

```ini
[automount]
options = "metadata,umask=022,fmask=011"
```

Po zapisaniu konfiguracji zamknij WSL, wykonaj w PowerShellu `wsl --shutdown`, uruchom
WSL ponownie i ustaw katalogowi repozytorium restrykcyjne prawa:

```bash
chmod 755 /mnt/d/projects/reservation-stack
```

Sprawdź, czy Ansible korzysta z właściwego pliku:

```bash
ansible-config view
ansible-config dump --only-changed
```

## Pakiety systemowe na Ubuntu/WSL

Najpierw sprawdź wydanie Ubuntu:

```bash
. /etc/os-release
echo "$PRETTY_NAME"
```

### Ubuntu 26.04 LTS

Ubuntu 26.04 udostępnia Python 3.14 w oficjalnym repozytorium. Zainstaluj interpreter,
obsługę środowisk wirtualnych i pozostałe narzędzia poleceniem:

```bash
sudo apt update
sudo apt install --yes python3.14 python3.14-venv python3-pip openssh-client git
```

Sprawdzenie wersji:

```bash
python3.14 --version
```

### Ubuntu 22.04 lub 24.04

Te wydania nie dostarczają Python 3.14 w swoich podstawowych oficjalnych
repozytoriach. Preferowanym rozwiązaniem dla control node jest aktualizacja WSL do
Ubuntu 26.04 LTS. Jeżeli aktualizacja nie jest możliwa, Python 3.14 można zainstalować
z zewnętrznego PPA `deadsnakes`:

```bash
sudo apt update
sudo apt install --yes software-properties-common openssh-client git
sudo add-apt-repository --yes ppa:deadsnakes/ppa
sudo apt update
sudo apt install --yes python3.14 python3.14-venv
```

Następnie sprawdź interpreter:

```bash
python3.14 --version
python3.14 -m venv --help >/dev/null
```

PPA jest repozytorium zewnętrznym i samo zastrzega brak gwarancji terminowych
aktualizacji bezpieczeństwa. Na kontrolerze produkcyjnym należy użyć go tylko po
zaakceptowaniu tego ryzyka. Bezpieczniejszym wariantem pozostaje Ubuntu 26.04 z
pakietami utrzymywanymi przez Ubuntu.

Nie zmieniaj ręcznie dowiązania `/usr/bin/python3` i nie używaj `update-alternatives`
do zastępowania systemowej wersji Pythona. Narzędzia Ubuntu mogą zależeć od
dystrybucyjnego interpretera. Projekt jawnie używa polecenia `python3.14`, więc zmiana
systemowego `python3` nie jest potrzebna.

Wymagany jest Python 3.14. Projekt przypina `ansible-core` 2.21.2, który oficjalnie
obsługuje Python 3.12, 3.13 i 3.14. Pozostałe narzędzia są przypięte do wersji
`ansible-lint` 26.6.0 oraz `yamllint` 1.38.0.

Python 3.14 musi być zainstalowany wewnątrz używanej dystrybucji WSL. Nie należy
zastępować go Windowsowym interpreterem Pythona.

## Ważne: nie używaj natywnego środowiska Windows

Nie uruchamiaj plików `.venv\Scripts\ansible*.exe` z `cmd.exe` ani PowerShella.
Ansible używa funkcji systemu POSIX, których natywny Python dla Windows nie
udostępnia. Typowym objawem jest błąd:

```text
AttributeError: module 'os' has no attribute 'get_blocking'
```

Zmiana wersji `ansible-core` ani odtworzenie środowiska przez Windowsowe
`py -3.14 -m venv .venv` nie rozwiąże tego problemu. Control node musi działać
w Linux, np. w WSL2.

### Sprawdzenie istniejącego środowiska

Plik `.venv/pyvenv.cfg` wskazuje interpreter, którym utworzono środowisko. Jeżeli
zawiera ścieżkę podobną do:

```text
home = C:\Users\...\Python310
```

środowisko zostało utworzone przez natywny Python 3.10 dla Windows. Nie można go
użyć ani naprawić z poziomu WSL. Trzeba je zastąpić środowiskiem utworzonym w WSL.

## Przygotowanie WSL2

W PowerShellu uruchomionym jako administrator można zainstalować Ubuntu:

```powershell
wsl --install -d Ubuntu
```

Po instalacji uruchom terminal Ubuntu/WSL i przejdź do repozytorium:

```bash
cd /mnt/d/projects/reservation-stack
```

Jeżeli `.venv` zostało wcześniej utworzone w Windows, najpierw zmień jego nazwę
albo usuń je ręcznie. Środowiska Windows nie należy mieszać ze środowiskiem WSL.

## Utworzenie środowiska `.venv`

W katalogu głównym repozytorium wykonaj:

```bash
python3.14 -m venv .venv
```

Aktywuj środowisko:

```bash
source .venv/bin/activate
```

Po aktywacji początek znaku zachęty powinien zawierać `(.venv)`. Można również
sprawdzić używany interpreter:

```bash
which python
python --version
```

Polecenie `which python` powinno wskazywać plik `.venv/bin/python` w tym repozytorium.
Nie powinno wskazywać `.venv/Scripts/python.exe` ani ścieżki z katalogu Windows.

## Instalacja pakietów Python

Najpierw zaktualizuj narzędzia instalacyjne wewnątrz środowiska:

```bash
python -m pip install --upgrade pip setuptools wheel
```

Następnie zainstaluj zależności projektu:

```bash
python -m pip install --requirement requirements.txt
```

Plik `requirements.txt` instaluje:

- `ansible-core` — polecenia Ansible i podstawowe moduły;
- `ansible-lint` — kontrolę jakości playbooków i ról;
- `yamllint` — kontrolę składni i formatowania YAML.

Nie należy instalować tych pakietów globalnie ani uruchamiać `pip` przez `sudo`.

## Instalacja kolekcji Ansible

Pakiety Python i kolekcje Ansible są rozdzielnymi zależnościami. Po instalacji
`requirements.txt` zainstaluj kolekcje zadeklarowane w `requirements.yml`:

```bash
ansible-galaxy collection install --requirements-file requirements.yml
```

Domyślnie kolekcje zostaną zapisane w katalogu użytkownika. Aby utrzymywać je
lokalnie razem ze środowiskiem projektu, można użyć:

```bash
ansible-galaxy collection install \
  --requirements-file requirements.yml \
  --collections-path .venv/collections
```

W takim przypadku przed użyciem ustaw ścieżkę kolekcji:

```bash
export ANSIBLE_COLLECTIONS_PATH="$PWD/.venv/collections"
```

Najprostszy wariant to pozostawienie domyślnej lokalizacji użytkownika.

## Weryfikacja instalacji

```bash
ansible --version
ansible-playbook --version
ansible-lint --version
yamllint --version
ansible-galaxy collection list
```

W informacji `ansible --version` pole `python version` powinno wskazywać interpreter
z katalogu `.venv`.

Sprawdź projekt bez łączenia z hostem:

```bash
ansible-playbook \
  --inventory inventories/dev/hosts.yml \
  site.yml \
  --syntax-check

yamllint .
ansible-lint site.yml playbooks/ roles/
```

## Przygotowanie sekretów

Skopiuj plik przykładowy i uzupełnij wartości:

```bash
cp inventories/dev/vault.example.yml \
   inventories/dev/group_vars/all/vault.yml

ansible-vault encrypt inventories/dev/group_vars/all/vault.yml
```

Analogicznie przygotuj `inventories/prod/group_vars/all/vault.yml`. Pliki `vault.yml`
są ignorowane przez Git. Pliki muszą znajdować się wewnątrz katalogu
`group_vars/all/`, aby Ansible przypisał zmienne do grupy `all`.

### Hasło `sudo` dla `become`

Playbook wykonuje zadania administracyjne z `become: true`. Jeżeli konto używane do
SSH wymaga hasła dla `sudo`, zapisz je w odpowiednim zaszyfrowanym pliku Vault jako:

```yaml
vault_ansible_become_password: "SILNE_HASLO_SUDO"
```

Jawny plik `inventories/<środowisko>/group_vars/all/vars.yml` mapuje tę wartość na
standardową zmienną Ansible:

```yaml
ansible_become_password: "{{ vault_ansible_become_password }}"
```

Przykład przygotowania dev:

```bash
cp inventories/dev/vault.example.yml \
   inventories/dev/group_vars/all/vault.yml

ansible-vault encrypt \
  --vault-id dev@prompt \
  inventories/dev/group_vars/all/vault.yml
```

Edycja istniejącego Vaulta:

```bash
ansible-vault edit \
  --vault-id dev@prompt \
  inventories/dev/group_vars/all/vault.yml
```

Uruchomienie playbooka:

```bash
ansible-playbook \
  --inventory inventories/dev/hosts.yml \
  site.yml \
  --vault-id dev@prompt
```

Ansible odszyfruje `ansible_become_password` w pamięci i przekaże je do `sudo`.
Hasła nie należy wpisywać bezpośrednio do `hosts.yml`, `all.yml`, `ansible.cfg` ani
argumentów polecenia.

Jeżeli nie chcesz przechowywać hasła `sudo` nawet w Vaulcie, usuń mapowanie
`ansible_become_password` z `group_vars/all/vars.yml` i używaj interaktywnego pytania:

```bash
ansible-playbook \
  --inventory inventories/dev/hosts.yml \
  site.yml \
  --ask-become-pass \
  --vault-id dev@prompt
```

Nie należy konfigurować pełnego `NOPASSWD: ALL` wyłącznie po to, aby ominąć hasło.
Jeśli w przyszłości zostanie użyte `NOPASSWD`, wpis `sudoers` powinien być możliwie
wąski i wynikać z udokumentowanego modelu administracji.

## Pierwsze połączenie

Po uzupełnieniu `ansible_host` i `ansible_user` sprawdź dostęp do hosta:

```bash
ansible \
  --inventory inventories/dev/hosts.yml \
  binturo_hosts \
  --module-name ansible.builtin.ping \
  --ask-become-pass
```

Jeżeli konto SSH używa bezhasłowego `sudo`, opcja `--ask-become-pass` nie jest
potrzebna.

## Klucze SSH do połączeń Ansible

### Rekomendowany sposób przechowywania

Prywatnych kluczy SSH nie należy przechowywać w repozytorium, nawet jeśli plik jest
zaszyfrowany przez Ansible Vault. Dla każdego administratora i środowiska należy
utworzyć osobny klucz chroniony hasłem, zapisać go w `~/.ssh` wewnątrz WSL i ładować
przez `ssh-agent`.

Takie rozwiązanie zapewnia:

- brak prywatnego klucza w repozytorium i jego historii;
- możliwość niezależnego odebrania dostępu konkretnej osobie;
- oddzielenie dostępu do dev i prod;
- obsługę hasła klucza przez `ssh-agent`;
- standardową współpracę z klientem OpenSSH używanym przez Ansible.

### Generowanie osobnych kluczy

W terminalu WSL wykonaj:

```bash
install -d -m 700 ~/.ssh

ssh-keygen \
  -t ed25519 \
  -a 100 \
  -f ~/.ssh/binturo_ansible_dev \
  -C "ansible-dev"

ssh-keygen \
  -t ed25519 \
  -a 100 \
  -f ~/.ssh/binturo_ansible_prod \
  -C "ansible-prod"
```

Podczas generowania ustaw inne, silne hasło dla każdego klucza. Powstaną pliki:

```text
~/.ssh/binturo_ansible_dev       # klucz prywatny
~/.ssh/binturo_ansible_dev.pub   # klucz publiczny
~/.ssh/binturo_ansible_prod
~/.ssh/binturo_ansible_prod.pub
```

Ustaw właściwe uprawnienia:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/binturo_ansible_dev
chmod 600 ~/.ssh/binturo_ansible_prod
chmod 644 ~/.ssh/binturo_ansible_dev.pub
chmod 644 ~/.ssh/binturo_ansible_prod.pub
```

Klucz prywatny nie może być kopiowany na zarządzany host. Na serwer instaluje się
wyłącznie odpowiadający mu klucz publiczny.

### Instalacja kluczy publicznych na hostach

```bash
ssh-copy-id \
  -i ~/.ssh/binturo_ansible_dev.pub \
  UZYTKOWNIK_SSH@ADRES_HOSTA_DEV

ssh-copy-id \
  -i ~/.ssh/binturo_ansible_prod.pub \
  UZYTKOWNIK_SSH@ADRES_HOSTA_PROD
```

Po instalacji przetestuj zwykłe połączenie SSH przed uruchomieniem Ansible:

```bash
ssh -i ~/.ssh/binturo_ansible_dev UZYTKOWNIK_SSH@ADRES_HOSTA_DEV
ssh -i ~/.ssh/binturo_ansible_prod UZYTKOWNIK_SSH@ADRES_HOSTA_PROD
```

### Używanie `ssh-agent`

Ansible nie udostępnia interaktywnego kanału, w którym klient SSH mógłby poprosić o
hasło do klucza prywatnego. Dlatego klucze chronione hasłem należy wcześniej dodać
do `ssh-agent`:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/binturo_ansible_dev
ssh-add ~/.ssh/binturo_ansible_prod
```

Sprawdź załadowane klucze:

```bash
ssh-add -l
```

Po dodaniu kluczy Ansible automatycznie korzysta z agenta. Nie trzeba umieszczać
prywatnego klucza ani jego hasła w inventory.

Po zakończeniu pracy klucze można usunąć z agenta:

```bash
ssh-add -D
```

Polecenie `ssh-add -D` usuwa z bieżącego agenta wszystkie załadowane tożsamości.

### Opcjonalna konfiguracja `~/.ssh/config`

W pliku `~/.ssh/config` można przypisać klucze do konkretnych hostów:

```sshconfig
Host binturo-dev
    HostName ADRES_HOSTA_DEV
    User UZYTKOWNIK_SSH
    IdentityFile ~/.ssh/binturo_ansible_dev
    IdentitiesOnly yes

Host binturo-prod
    HostName ADRES_HOSTA_PROD
    User UZYTKOWNIK_SSH
    IdentityFile ~/.ssh/binturo_ansible_prod
    IdentitiesOnly yes
```

Zabezpiecz plik i sprawdź połączenia:

```bash
chmod 600 ~/.ssh/config
ssh binturo-dev
ssh binturo-prod
```

Inventory może wtedy używać aliasów SSH jako `ansible_host`. Nadal zaleca się
wcześniejsze dodanie kluczy do `ssh-agent`, aby Ansible nie musiał obsługiwać pytania
o hasło klucza.

### Czy prywatny klucz można zapisać w Ansible Vault?

Technicznie jest to możliwe, ale nie jest to wariant preferowany. Vault chroni dane
wyłącznie w spoczynku. Każda osoba mająca dostęp do repozytorium i hasła Vault może
odzyskać klucz, a zaszyfrowany plik pozostaje trwale w historii Git.

Ten wariant można rozważyć dla kontrolowanego, współdzielonego konta automatyzacji,
jeśli organizacja nie posiada dedykowanego secrets managera. Nie powinien zastępować
indywidualnych kluczy administratorów.

Utwórz katalog i skopiuj klucz pod nazwą wskazującą, że docelowo będzie zaszyfrowany:

```bash
mkdir -p secrets/ssh
chmod 700 secrets/ssh
cp ~/.ssh/binturo_ansible_prod secrets/ssh/binturo_ansible_prod.vault
```

Natychmiast zaszyfruj kopię klucza:

```bash
ansible-vault encrypt \
  --vault-id prod@prompt \
  secrets/ssh/binturo_ansible_prod.vault
```

Sprawdź nagłówek pliku:

```bash
head -n 1 secrets/ssh/binturo_ansible_prod.vault
```

Powinien wyglądać następująco:

```text
$ANSIBLE_VAULT;1.2;AES256;prod
```

Zaszyfrowanego pliku nie można wskazać bezpośrednio jako
`ansible_ssh_private_key_file` ani przekazać przez `--private-key`. Najbezpieczniej
odszyfrować jego zawartość bezpośrednio do `ssh-agent`, bez tworzenia jawnego pliku:

```bash
eval "$(ssh-agent -s)"

ansible-vault view \
  --vault-id prod@prompt \
  secrets/ssh/binturo_ansible_prod.vault |
ssh-add -
```

Następnie można uruchomić playbook w zwykły sposób:

```bash
ansible-playbook \
  --inventory inventories/prod/hosts.yml \
  site.yml \
  --limit binturo-prod \
  --vault-id prod@prompt
```

Hasła Vault nie wolno zapisywać w repozytorium. Preferowane źródła hasła to:

- interaktywny prompt, np. `--vault-id prod@prompt`;
- systemowy menedżer haseł;
- firmowy secrets manager;
- wykonywalny Vault password client pobierający hasło z bezpiecznego magazynu.

Jeśli hasło Vault jest przechowywane w pliku, plik musi znajdować się poza
repozytorium, mieć uprawnienia `0600` i być chroniony szyfrowaniem dysku. Nie należy
zapisywać go w `.vault-password` wewnątrz projektu tylko dlatego, że ta nazwa jest
ignorowana przez Git.

### Zalecany model dla Binturo

- osobne klucze dla dev i prod;
- osobny klucz dla każdego administratora;
- prywatne klucze w `~/.ssh` wewnątrz WSL;
- silne hasło na każdym kluczu;
- obsługa kluczy przez `ssh-agent`;
- wyłącznie klucze publiczne w `authorized_keys` hostów;
- szyfrowanie dysku control node;
- Vault dla haseł PostgreSQL i innych sekretów konfiguracyjnych;
- brak prywatnych kluczy SSH w repozytorium.

## Kontrola przed wykonaniem zmian

```bash
ansible-playbook \
  --inventory inventories/dev/hosts.yml \
  site.yml \
  --check \
  --diff \
  --ask-vault-pass
```

Nie wszystkie moduły i polecenia mogą idealnie symulować działanie w trybie
`--check`. Pierwsze rzeczywiste uruchomienie należy wykonać najpierw na hoście dev.

## Uruchomienie

Dev:

```bash
ansible-playbook \
  --inventory inventories/dev/hosts.yml \
  site.yml \
  --ask-vault-pass
```

Prod:

```bash
ansible-playbook \
  --inventory inventories/prod/hosts.yml \
  site.yml \
  --limit binturo-prod \
  --ask-vault-pass
```

Jawny `--limit binturo-prod` zmniejsza ryzyko wykonania playbooka na niewłaściwym
hoście.

## Zakończenie pracy

Środowisko wirtualne wyłącza się poleceniem:

```bash
deactivate
```

Przy kolejnej sesji nie trzeba ponownie instalować zależności. Wystarczy:

```bash
source .venv/bin/activate
```

## Odtworzenie środowiska

Katalog `.venv` nie jest przechowywany w Git i można go bezpiecznie odtworzyć:

```bash
python3.14 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install --requirement requirements.txt
ansible-galaxy collection install --requirements-file requirements.yml
```

Nie należy kopiować `.venv` między komputerami ani między różnymi wersjami Pythona.
Nie należy też współdzielić jednego `.venv` pomiędzy Windows i WSL.

## Aktualizacja zależności

Wersję `ansible-core` zmienia się świadomie w `requirements.txt`, a zakresy wersji
kolekcji w `requirements.yml`. Po zmianie należy odtworzyć środowisko i wykonać:

```bash
ansible-playbook --inventory inventories/dev/hosts.yml site.yml --syntax-check
yamllint .
ansible-lint site.yml playbooks/ roles/
```

Aktualizację należy sprawdzić na dev przed zastosowaniem jej do konfiguracji prod.
