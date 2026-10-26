#!/bin/sh
# Install the nox-protocol server on Ubuntu 24.04 next to an existing xray/panel.
# Does not touch xray. Listens on its own port until you point a real certificate at it.
set -eu

PREFIX="${PREFIX:-/usr/local}"
CFG_DIR="${CFG_DIR:-/etc/nox}"
UNIT_SRC="${UNIT_SRC:-deploy/nox-server.service}"
BIN_SRC="${BIN_SRC:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "запустите от root: sudo sh scripts/install-nox-server.sh" >&2
  exit 1
fi

if [ -z "$BIN_SRC" ]; then
  if [ -x "$PREFIX/bin/nox-server" ]; then
    BIN_SRC="$PREFIX/bin/nox-server"
  else
    echo "собираю nox-server..."
    ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
    if ! command -v go >/dev/null 2>&1; then
      echo "нужен Go (пакет golang-go не подойдёт, если он старше 1.21) либо готовый бинарник: BIN_SRC=/path/nox-server" >&2
      exit 1
    fi
    (cd "$ROOT/go" && GOTOOLCHAIN=auto go build -o "$PREFIX/bin/nox-server" ./cmd/nox-server)
    BIN_SRC="$PREFIX/bin/nox-server"
  fi
else
  install -m 0755 "$BIN_SRC" "$PREFIX/bin/nox-server"
fi

if ! id nox >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/nox --shell /usr/sbin/nologin nox
fi
mkdir -p /var/lib/nox "$CFG_DIR"
chown nox:nox /var/lib/nox

if [ ! -f "$CFG_DIR/identity" ]; then
  "$PREFIX/bin/nox-server" -genkey "$CFG_DIR/identity"
  chown nox:nox "$CFG_DIR/identity"
  chmod 600 "$CFG_DIR/identity"
fi

if [ ! -f "$CFG_DIR/server.json" ]; then
  cat > "$CFG_DIR/server.json" <<'EOF'
{
  "listen": "0.0.0.0:8443",
  "h3": "0.0.0.0:8443",
  "cert": "/etc/nox/fullchain.pem",
  "key": "/etc/nox/privkey.pem",
  "identity": "/etc/nox/identity",
  "cover": "",
  "path": "/api/v1/events",
  "profile": "mixed"
}
EOF
  chmod 644 "$CFG_DIR/server.json"
  echo "конфиг: $CFG_DIR/server.json (порт 8443, чтобы не занять 443 у xray)"
fi

if [ -f "$UNIT_SRC" ]; then
  install -m 0644 "$UNIT_SRC" /etc/systemd/system/nox-server.service
elif [ -f "deploy/nox-server.service" ]; then
  install -m 0644 deploy/nox-server.service /etc/systemd/system/nox-server.service
else
  echo "не найден nox-server.service (запустите из корня репозитория)" >&2
  exit 1
fi

systemctl daemon-reload
echo
echo "Дальше, сертификат на ВАШ домен (не самоподпись):"
echo "  apt-get install -y certbot"
echo "  certbot certonly --standalone -d your.domain"
echo "  ln -sf /etc/letsencrypt/live/your.domain/fullchain.pem $CFG_DIR/fullchain.pem"
echo "  ln -sf /etc/letsencrypt/live/your.domain/privkey.pem $CFG_DIR/privkey.pem"
echo "  systemctl enable --now nox-server"
echo
echo "Ссылку для подписки печатает: $PREFIX/bin/nox-server -genkey (уже создана) — смотрите вывод выше,"
echo "либо поля pub/pass в $CFG_DIR/identity. В ссылке SNI должен совпадать с сертификатом."
echo "Клиенты без ключа видят пустую страницу или сайт из поля cover."
