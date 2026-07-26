#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly BINTURO_ROOT='/srv/binturo'
readonly BINTURO_USER='binturo'
readonly REQUIRED_CONFIRMATION='DELETE /srv/binturo'

environment_name=''
execute=false
backup_confirmed=false
stop_caddy=false

usage() {
  cat <<'EOF'
Bezpieczne usunięcie środowiska Binturo z /srv/binturo.

Domyślnie skrypt wykonuje tylko kontrolę i podgląd. Usunięcie wymaga wszystkich
opcji --execute i --backup-confirmed oraz interaktywnego potwierdzenia.

Użycie:
  remove-binturo.sh --environment dev
  sudo remove-binturo.sh --environment dev --execute --backup-confirmed

Opcje:
  --environment dev|staging|prod  Nazwa projektów Docker Compose (wymagana).
  --execute                       Zezwól na zatrzymanie usług i usunięcie danych.
  --backup-confirmed              Potwierdź, że backup znajduje się poza hostem.
  --stop-caddy                    Zatrzymaj Caddy; użyj, jeśli nie obsługuje innych witryn.
  --help                          Wyświetl pomoc.

Skrypt nie usuwa /srv, konta binturo, pakietów, obrazów Dockera ani zasobów
Docker Compose niezwiązanych z wybranym środowiskiem.
EOF
}

log() {
  printf '[binturo-remove] %s\n' "$*"
}

fail() {
  printf '[binturo-remove] ERROR: %s\n' "$*" >&2
  exit 1
}

on_error() {
  local exit_code=$?
  printf '[binturo-remove] ERROR: przerwano w linii %s (kod %s).\n' \
    "${BASH_LINENO[0]:-unknown}" "$exit_code" >&2
  exit "$exit_code"
}
trap on_error ERR

while (($# > 0)); do
  case "$1" in
    --environment)
      (($# >= 2)) || fail 'Brak wartości po --environment.'
      environment_name=$2
      shift 2
      ;;
    --execute)
      execute=true
      shift
      ;;
    --backup-confirmed)
      backup_confirmed=true
      shift
      ;;
    --stop-caddy)
      stop_caddy=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Nieznana opcja: $1"
      ;;
  esac
done

case "$environment_name" in
  dev|staging|prod) ;;
  '') fail 'Opcja --environment jest wymagana.' ;;
  *) fail '--environment musi mieć wartość dev, staging albo prod.' ;;
esac

command -v realpath >/dev/null || fail 'Brak polecenia realpath.'
command -v systemctl >/dev/null || fail 'Brak polecenia systemctl.'
command -v runuser >/dev/null || fail 'Brak polecenia runuser.'
command -v findmnt >/dev/null || fail 'Brak polecenia findmnt.'

[[ -e "$BINTURO_ROOT" ]] || fail "$BINTURO_ROOT nie istnieje."
[[ -d "$BINTURO_ROOT" ]] || fail "$BINTURO_ROOT nie jest katalogiem."
[[ ! -L "$BINTURO_ROOT" ]] || fail "$BINTURO_ROOT nie może być dowiązaniem symbolicznym."

resolved_root=$(realpath --canonicalize-existing -- "$BINTURO_ROOT")
[[ "$resolved_root" == '/srv/binturo' ]] || {
  fail "Nieprawidłowa ścieżka docelowa: $resolved_root"
}

id "$BINTURO_USER" >/dev/null 2>&1 || fail "Nie istnieje użytkownik $BINTURO_USER."
readonly binturo_uid=$(id -u "$BINTURO_USER")
readonly runtime_dir="/run/user/$binturo_uid"
readonly docker_host="unix://$runtime_dir/docker.sock"
readonly compose_dir="$BINTURO_ROOT/compose"
readonly postgres_compose="$compose_dir/compose.postgres.yml"
readonly monitoring_compose="$compose_dir/compose.monitoring.yml"
readonly postgres_project="binturo-$environment_name"
readonly monitoring_project="binturo-monitoring-$environment_name"

run_docker() {
  runuser -u "$BINTURO_USER" -- env \
    "XDG_RUNTIME_DIR=$runtime_dir" \
    "DOCKER_HOST=$docker_host" \
    docker "$@"
}

log "Środowisko: $environment_name"
log "Dokładny katalog docelowy: $resolved_root"
log "Rootless Docker: $BINTURO_USER (UID $binturo_uid), $docker_host"
log 'Rozmiar katalogu:'
du -sh -- "$BINTURO_ROOT" || true
log 'Najważniejsze elementy katalogu:'
find "$BINTURO_ROOT" -xdev -mindepth 1 -maxdepth 2 -print | sort

if [[ -S "$runtime_dir/docker.sock" ]]; then
  log 'Projekty Docker Compose:'
  run_docker compose ls || true
  log 'Kontenery rootless Docker:'
  run_docker ps -a || true
else
  log 'Socket rootless Docker nie działa; w trybie wykonania demon zostanie uruchomiony.'
fi

if [[ "$execute" != true ]]; then
  log 'TRYB PODGLĄDU: niczego nie zatrzymano ani nie usunięto.'
  log 'Po wykonaniu i sprawdzeniu backupu użyj --execute --backup-confirmed.'
  exit 0
fi

[[ $EUID -eq 0 ]] || fail 'Tryb --execute wymaga uruchomienia przez sudo/root.'
[[ "$backup_confirmed" == true ]] || {
  fail 'Brak --backup-confirmed. Najpierw wykonaj backup poza tym hostem.'
}
[[ -t 0 ]] || fail 'Usunięcie wymaga interaktywnego terminala.'

printf '\nOperacja bezpowrotnie usunie %s.\n' "$BINTURO_ROOT"
printf 'Aby kontynuować, wpisz dokładnie: %s\n> ' "$REQUIRED_CONFIRMATION"
IFS= read -r confirmation
[[ "$confirmation" == "$REQUIRED_CONFIRMATION" ]] || fail 'Potwierdzenie nie pasuje.'

log 'Zatrzymywanie i wyłączanie backendów.'
systemctl disable --now binturo-platform.service binturo-organizers.service || true

if [[ "$stop_caddy" == true ]]; then
  log 'Zatrzymywanie Caddy.'
  systemctl stop caddy.service
else
  log 'Caddy pozostaje uruchomiony. Po usunięciu plików witryny mogą zwracać błędy.'
fi

if [[ ! -S "$runtime_dir/docker.sock" ]]; then
  log 'Uruchamianie rootless Docker na czas kontrolowanego usunięcia Compose.'
  runuser -u "$BINTURO_USER" -- env "XDG_RUNTIME_DIR=$runtime_dir" \
    systemctl --user start docker.service
fi

[[ -f "$monitoring_compose" ]] || fail "Brak $monitoring_compose."
[[ -f "$postgres_compose" ]] || fail "Brak $postgres_compose."

log "Usuwanie projektu Compose $monitoring_project wraz z wolumenami."
run_docker compose \
  --project-name "$monitoring_project" \
  --file "$monitoring_compose" \
  down --volumes --remove-orphans

log "Usuwanie projektu Compose $postgres_project."
run_docker compose \
  --project-name "$postgres_project" \
  --file "$postgres_compose" \
  down --volumes --remove-orphans

remaining_monitoring_containers=$(
  run_docker ps -aq \
    --filter "label=com.docker.compose.project=$monitoring_project"
)
remaining_postgres_containers=$(
  run_docker ps -aq \
    --filter "label=com.docker.compose.project=$postgres_project"
)
[[ -z "$remaining_monitoring_containers" ]] || {
  fail "Pozostały kontenery projektu $monitoring_project: $remaining_monitoring_containers"
}
[[ -z "$remaining_postgres_containers" ]] || {
  fail "Pozostały kontenery projektu $postgres_project: $remaining_postgres_containers"
}

log 'Zatrzymywanie rootless Docker.'
runuser -u "$BINTURO_USER" -- env "XDG_RUNTIME_DIR=$runtime_dir" \
  systemctl --user stop docker.service

if findmnt --raw --noheadings --output TARGET | \
  awk -v root="$BINTURO_ROOT/" 'index($0, root) == 1 { found=1 } END { exit !found }'; then
  fail "Pod $BINTURO_ROOT nadal znajduje się punkt montowania. Nie usunięto katalogu."
fi

resolved_root=$(realpath --canonicalize-existing -- "$BINTURO_ROOT")
[[ "$resolved_root" == '/srv/binturo' ]] || {
  fail "Końcowa walidacja ścieżki nie powiodła się: $resolved_root"
}
[[ ! -L "$BINTURO_ROOT" ]] || fail 'Cel stał się dowiązaniem symbolicznym.'

log 'Usuwanie dokładnej ścieżki /srv/binturo.'
rm -rf --one-file-system -- /srv/binturo
[[ ! -e /srv/binturo ]] || fail 'Katalog nadal istnieje po operacji usuwania.'

log 'Zakończono. /srv/binturo został usunięty.'
log 'Jednostki systemd, Caddy, konto binturo i pakiety pozostają na hoście.'
