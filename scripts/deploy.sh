#!/usr/bin/env bash
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Использование: $0 [--dry-run]" >&2; exit 2 ;;
esac

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует, доставка отменена" >&2
    exit 1
fi

if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена" >&2
    exit 1
fi

RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ $DRY_RUN -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
fi

rsync "${RSYNC_OPTS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/" || {
    echo "Ошибка: синхронизация не выполнена" >&2
    exit 1
}

if [[ $DRY_RUN -eq 1 ]]; then
    exit 0
fi

if ! curl -fsS -m 10 --cacert "$CA_CERT" -o /dev/null "$SITE_URL"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки" >&2
    exit 1
fi

echo "Доставлен коммит $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
exit 0
