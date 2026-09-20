"""Build the provisioned Grafana dashboards from concise panel definitions."""

import json
from pathlib import Path


OUTPUT = Path(__file__).resolve().parents[1] / "roles/central_monitoring/files/dashboards"
SOURCE = {"type": "prometheus", "uid": "prometheus-staging"}
WINDOW = "48h"


def panel(title, expr, *, kind="timeseries", unit="short", legend="", width=12,
          instant=False, description=None):
    return dict(title=title, expr=expr, kind=kind, unit=unit, legend=legend,
                width=width, instant=instant, description=description)


def dashboard(filename, uid, title, tags, definitions, *, period="now-7d", variables=None):
    panels = []
    x = y = row_height = 0
    for number, spec in enumerate(definitions, 1):
        width = spec["width"]
        height = 5 if spec["kind"] == "stat" else 8
        if x + width > 24:
            x, y, row_height = 0, y + row_height, 0
        target = {"refId": "A", "expr": spec["expr"], "legendFormat": spec["legend"]}
        if spec["instant"]:
            target["instant"] = True
            target["range"] = False
        item = {
            "id": number, "title": spec["title"], "type": spec["kind"],
            "gridPos": {"x": x, "y": y, "w": width, "h": height},
            "datasource": SOURCE, "targets": [target],
            "fieldConfig": {"defaults": {"unit": spec["unit"]}, "overrides": []},
            "options": {},
        }
        if spec["description"]:
            item["description"] = spec["description"]
        if spec["kind"] == "stat":
            item["options"] = {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                               "orientation": "auto", "textMode": "auto", "colorMode": "value"}
        panels.append(item)
        x += width
        row_height = max(row_height, height)

    data = {
        "uid": uid, "title": title, "tags": ["binturo", "staging", *tags],
        "timezone": "browser", "schemaVersion": 39, "version": 2,
        "editable": False, "refresh": "5m", "time": {"from": period, "to": "now"},
        "panels": panels,
    }
    if variables:
        data["templating"] = {"list": [{
            "name": "organizer_code", "type": "query", "label": "Organizacja",
            "datasource": SOURCE, "query": {"query": "label_values(binturo_organizer_info, organizer_code)", "refId": "StandardVariableQuery"},
            "refresh": 1, "includeAll": True, "allValue": ".*", "multi": True,
            "sort": 1, "current": {"selected": True, "text": "All", "value": "$__all"},
        }]}
    with (OUTPUT / filename).open("w", encoding="utf-8", newline="\n") as result:
        result.write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def main():
    last = lambda metric: f"last_over_time({metric}[{WINDOW}])"
    dashboard("01-stan-stagingu.json", "binturo-staging-status", "Binturo / Stan stagingu",
              ["infrastruktura"], [
        panel("Wiek ostatniej próbki", "time() - max_over_time(timestamp(up{job=\"prometheus\"})[48h:5m])",
              kind="stat", unit="s", instant=True, width=8,
              description="Czas od ostatniej próbki w migawce. Duża wartość oznacza nieaktualne dane centralne."),
        panel("Cele — ostatni znany stan", f"{last('up{job=~\"prometheus|node|caddy|postgres|binturo-platform|binturo-organizers\"}')}",
              kind="stat", instant=True, width=16, legend="{{job}}",
              description="Stan z ostatnich 48 godzin, nie bieżący test dostępności."),
        panel("Dostępność celów w czasie", 'up{job=~"prometheus|node|caddy|postgres|binturo-platform|binturo-organizers"}',
              width=24, legend="{{job}}"),
        panel("Błędy HTTP 5xx / s", 'sum by (service) (rate(binturo_http_requests_total{status_class="5xx"}[5m]))',
              unit="reqps", legend="{{service}}"),
        panel("Wiek ostatniego crona", f"time() - {last('binturo_platform_cron_last_run_timestamp_seconds')}",
              kind="stat", unit="s", instant=True),
        panel("Ostatni wynik crona", last('binturo_platform_cron_last_run_success'),
              kind="stat", instant=True, legend="1 = sukces", width=8),
        panel("Zajętość dysku %", '100 * (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay|squashfs"})',
              unit="percent", legend="{{mountpoint}}", width=16),
    ], period="now-24h")

    dashboard("02-zasoby-hosta.json", "binturo-staging-host", "Binturo / Zasoby hosta i bazy",
              ["infrastruktura"], [
        panel("CPU hosta %", '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))', unit="percent"),
        panel("Pamięć używana %", '100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)', unit="percent"),
        panel("Dostępne miejsce na dysku", 'node_filesystem_avail_bytes{fstype!~"tmpfs|overlay|squashfs"}', unit="bytes", legend="{{mountpoint}}"),
        panel("Odczyt i zapis dysku", 'sum by (device) (rate(node_disk_read_bytes_total[5m]) + rate(node_disk_written_bytes_total[5m]))', unit="Bps", legend="{{device}}"),
        panel("Ruch sieciowy", 'sum by (device) (rate(node_network_receive_bytes_total{device!="lo"}[5m]) + rate(node_network_transmit_bytes_total{device!="lo"}[5m]))', unit="Bps", legend="{{device}}"),
        panel("Połączenia PostgreSQL", 'sum(pg_stat_database_numbackends)', legend="połączenia"),
        panel("Rozmiar baz PostgreSQL", 'pg_database_size_bytes', unit="bytes", legend="{{datname}}"),
        panel("Transakcje PostgreSQL / s", 'sum by (datname) (rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))', unit="ops", legend="{{datname}}"),
    ])

    dashboard("03-backendy.json", "binturo-staging-backends", "Binturo / Backend i HTTP",
              ["backend"], [
        panel("Żądania HTTP / s", 'sum by (service) (rate(binturo_http_requests_total[5m]))', unit="reqps", legend="{{service}}"),
        panel("Czas odpowiedzi p50", 'histogram_quantile(0.50, sum by (service, le) (rate(binturo_http_request_duration_seconds_bucket[5m])))', unit="s", legend="p50 {{service}}"),
        panel("Czas odpowiedzi p95", 'histogram_quantile(0.95, sum by (service, le) (rate(binturo_http_request_duration_seconds_bucket[5m])))', unit="s", legend="p95 {{service}}"),
        panel("Czas odpowiedzi p99", 'histogram_quantile(0.99, sum by (service, le) (rate(binturo_http_request_duration_seconds_bucket[5m])))', unit="s", legend="p99 {{service}}"),
        panel("Odpowiedzi 5xx / s", 'sum by (service) (rate(binturo_http_requests_total{status_class="5xx"}[5m]))', unit="reqps", legend="{{service}}"),
        panel("Odpowiedzi 4xx / s", 'sum by (service) (rate(binturo_http_requests_total{status_class="4xx"}[5m]))', unit="reqps", legend="{{service}}"),
        panel("Udział błędów 5xx %", '100 * sum by (service) (rate(binturo_http_requests_total{status_class="5xx"}[5m])) / clamp_min(sum by (service) (rate(binturo_http_requests_total[5m])), 0.000001)', unit="percent", legend="{{service}}"),
        panel("Najczęściej wywoływane trasy", 'topk(10, sum by (service, route) (rate(binturo_http_requests_total[5m])))', unit="reqps", legend="{{service}} {{route}}"),
        panel("Najwięcej błędów 5xx według trasy", 'topk(10, sum by (service, route) (increase(binturo_http_requests_total{status_class="5xx"}[1h])))', legend="{{service}} {{route}}"),
    ])

    dashboard("04-wykorzystanie-biznesowe.json", "binturo-staging-business", "Binturo / Wzrost platformy",
              ["biznes"], [
        panel("Organizacje według statusu", f"count by (status) ({last('binturo_organizer_info')})", kind="stat", instant=True, legend="{{status}}"),
        panel("Unikalni użytkownicy — ostatni stan", last('binturo_global_users_total'), kind="stat", instant=True),
        panel("Aktywni klienci organizacji — suma członkostw", f"sum({last('binturo_organizer_clients_active_total')})", kind="stat", instant=True,
              description="Jedna osoba w kilku organizacjach liczy się kilka razy."),
        panel("Nowe konta / tydzień", 'increase(binturo_global_user_registered_total[7d])', legend="rejestracje"),
        panel("Unikalni użytkownicy w czasie", 'binturo_global_users_total', legend="osoby"),
        panel("Aktywni klienci organizacji w czasie", 'sum(binturo_organizer_clients_active_total)', legend="członkostwa"),
        panel("Liczba organizacji w czasie", 'count(binturo_organizer_info)', legend="organizacje"),
        panel("Nowe organizacje / 7 dni", f"count({last('binturo_platform_organizer_registered_at_timestamp_seconds')} > time() - 7 * 86400) or vector(0)",
              kind="stat", instant=True,
              description="Liczba organizacji z datą rejestracji w ostatnich siedmiu dniach."),
        panel("Organizacje według planu", f"count by (plan_name) ({last('binturo_platform_organizer_subscription_info')})", kind="stat", instant=True, legend="{{plan_name}}"),
    ], period="now-7d")

    org = '{organizer_code=~"$organizer_code"}'
    dashboard("05-organizacje.json", "binturo-staging-organizers", "Binturo / Organizacje i zaangażowanie",
              ["biznes", "organizacje"], [
        panel("Klienci aktywni", f"binturo_organizer_clients_active_total{org}", legend="{{organizer_code}}"),
        panel("Wszyscy klienci", f"binturo_organizer_clients_total{org}", legend="{{organizer_code}}",
              description="Różnica względem aktywnych klientów nie jest samodzielną miarą churnu."),
        panel("Zajęcia w bieżącym tygodniu", f"binturo_organizer_classes_current_week_total{org}", legend="{{organizer_code}}"),
        panel("Zapisy w bieżącym tygodniu", f"sum by (organizer_code, status) (binturo_organizer_enrollments_current_week_total{{organizer_code=~\"$organizer_code\",status=~\"confirmed|waitlist\"}})", legend="{{organizer_code}} {{status}}"),
        panel("Trenerzy i personel", f"binturo_organizer_trainers_active_total{org} or binturo_organizer_staff_active_total{org}", legend="{{organizer_code}} {{__name__}}"),
        panel("Lokalizacje i sale", f"binturo_organizer_locations_active_total{org} or binturo_organizer_rooms_total{org}", legend="{{organizer_code}} {{__name__}}"),
        panel("Dni od ostatniej aktywności", f"(time() - {last('binturo_organizer_last_activity_timestamp_seconds' + org)}) / 86400", kind="stat", instant=True, unit="d", legend="{{organizer_code}}"),
        panel("Ruch organizacji — Top 10", 'topk(10, sum by (organizer_code) (increase(binturo_organizer_traffic_events_total[1d])))', legend="{{organizer_code}}"),
        panel("Ruch według roli", 'sum by (role) (rate(binturo_organizer_traffic_events_total[1h]))', unit="reqps", legend="{{role}}"),
    ], variables=True)

    dashboard("06-zapisy-komunikacja.json", "binturo-staging-engagement", "Binturo / Zapisy i komunikacja",
              ["biznes"], [
        panel("Zapisy i anulowania / 24 h", 'sum by (event, channel) (increase(binturo_enrollment_events_total[1d]))', legend="{{event}} · {{channel}}"),
        panel("Zapisy samoobsługowe i przez personel", 'sum by (channel) (increase(binturo_enrollment_events_total{event=~"created_confirmed|created_waitlist"}[1d]))', legend="{{channel}}"),
        panel("Sfinalizowane płatności / 24 h", 'sum by (kind) (increase(binturo_payment_finalized_total[1d]))', legend="{{kind}}"),
        panel("Wiadomości organizacji / 24 h", 'sum by (channel, direction) (increase(binturo_message_events_total[1d]))', legend="{{channel}} {{direction}}"),
        panel("Wiadomości platformy / 24 h", 'sum by (channel, source) (increase(binturo_platform_message_events_total[1d]))', legend="{{channel}} {{source}}"),
        panel("Webhooki Stripe / 24 h", 'sum by (outcome) (increase(binturo_stripe_webhook_events_total[1d]))', legend="{{outcome}}"),
        panel("Decyzje moderacji / 24 h", 'sum by (status) (increase(binturo_moderation_decisions_total[1d]))', legend="{{status}}"),
        panel("Decyzje po przeglądzie / 24 h", 'sum by (decision) (increase(binturo_moderation_review_decisions_total[1d]))', legend="{{decision}}"),
    ])

    dashboard("07-subskrypcje-platnosci.json", "binturo-staging-subscriptions", "Binturo / Subskrypcje i płatności",
              ["biznes"], [
        panel("Subskrypcje według statusu", f"count by (subscription_status) ({last('binturo_platform_organizer_subscription_info')})", kind="stat", instant=True, legend="{{subscription_status}}"),
        panel("Plany subskrypcji", f"count by (plan_name) ({last('binturo_platform_organizer_subscription_info')})", kind="stat", instant=True, legend="{{plan_name}}"),
        panel("Wygasają w ciągu 7 dni", f"count(({last('binturo_platform_organizer_subscription_valid_until_timestamp_seconds')} - time() < 7 * 86400) and ({last('binturo_platform_organizer_subscription_valid_until_timestamp_seconds')} > time())) or vector(0)", kind="stat", instant=True),
        panel("Zdarzenia subskrypcji / 24 h", 'sum by (outcome) (increase(binturo_subscription_payment_events_total[1d]))', legend="{{outcome}}"),
        panel("Kwota płatności brutto / 24 h", 'sum by (outcome) (increase(binturo_subscription_payment_amount_gross_total[1d]))', unit="currencyPLN", legend="{{outcome}}",
              description="Kwota brutto w PLN; applied_mock oznacza płatności testowe, nie rzeczywisty przychód ani MRR."),
        panel("Płatności testowe / 24 h", 'sum(increase(binturo_subscription_payment_amount_gross_total{outcome="applied_mock"}[1d]))', unit="currencyPLN", legend="mock"),
        panel("Płatności rzeczywiste / 24 h", 'sum(increase(binturo_subscription_payment_amount_gross_total{outcome="finalized"}[1d]))', unit="currencyPLN", legend="finalized"),
        panel("Cron: kończące się i wygasłe subskrypcje", 'binturo_platform_cron_limits_expiring_soon or binturo_platform_cron_limits_expired', legend="{{__name__}}"),
    ])


if __name__ == "__main__":
    main()
