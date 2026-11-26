#!/usr/bin/env bash
# Boots GitLab Omnibus inside a container with ONE persistent disk (Render allows one per service).
set -euo pipefail

DATA="${DATA_DIR:-/data}"
export PORT="${PORT:-10000}"
export GITLAB_URL="${EXTERNAL_URL:-${RENDER_EXTERNAL_URL:?set EXTERNAL_URL}}"
: "${GITLAB_ROOT_PASSWORD:?set GITLAB_ROOT_PASSWORD (12+ chars)}"

mkdir -p "$DATA"

# Map the three GitLab state dirs onto the single disk via symlinks
link_dir() {
  local src=$1 name=$2
  if [ ! -L "$src" ]; then
    mkdir -p "$DATA/$name"
    if [ -z "$(ls -A "$DATA/$name")" ] && [ -d "$src" ]; then cp -a "$src/." "$DATA/$name/"; fi
    rm -rf "$src"; ln -s "$DATA/$name" "$src"
  fi
}
link_dir /etc/gitlab etc
link_dir /var/opt/gitlab opt
link_dir /var/log/gitlab log

# gitlab.rb is regenerated each boot; secrets live in gitlab-secrets.json on the disk
cat > /etc/gitlab/gitlab.rb <<'RB'
external_url ENV['GITLAB_URL']
letsencrypt['enable'] = false
nginx['listen_addresses'] = ['127.0.0.1']   # internal only; socat exposes $PORT
nginx['listen_port'] = 8081
nginx['listen_https'] = false          # Render terminates TLS
nginx['proxy_set_headers'] = { 'X-Forwarded-Proto' => 'https', 'X-Forwarded-Ssl' => 'on' }
nginx['real_ip_header'] = 'X-Forwarded-For'
nginx['real_ip_recursive'] = 'on'

gitlab_rails['initial_root_password'] = ENV['GITLAB_ROOT_PASSWORD']
gitlab_rails['usage_ping_enabled'] = false
gitlab_rails['backup_keep_time'] = 604800   # 7 days
package['modify_kernel_parameters'] = false
package['detect_init'] = false            # no systemd in containers; we start runit ourselves

# Low-memory profile (single private team)
puma['worker_processes'] = 0
puma['min_threads'] = 1
puma['max_threads'] = 4
sidekiq['concurrency'] = 5
prometheus_monitoring['enable'] = false
gitlab_kas['enable'] = false
postgresql['shared_buffers'] = '256MB'
gitlab_rails['env'] = { 'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000' }

eval ENV['GITLAB_OMNIBUS_CONFIG'] if ENV['GITLAB_OMNIBUS_CONFIG']
RB

# Make sure the container hostname resolves (Chef refuses to run otherwise)
H="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo gitlab)"
grep -q "$H" /etc/hosts 2>/dev/null || echo "127.0.0.1 $H $H.localdomain" >> /etc/hosts

# Open Render's port IMMEDIATELY so the deploy is not killed while GitLab runs its
# first-boot DB migration (10-30 min). socat forwards $PORT -> nginx on 127.0.0.1:8081.
# Until GitLab is ready, connections are simply refused (just retry).
socat TCP-LISTEN:"$PORT",bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:8081 &
echo ">> port $PORT open; GitLab still starting - watch for 'GitLab up' below"

# Tell GitLab's installer this is a container (no init system)
touch /.dockerenv

echo ">> starting runit + reconfigure (first boot takes several minutes)"
/opt/gitlab/embedded/bin/runsvdir-start &
gitlab-ctl reconfigure

if [ ! -f "$DATA/.hardened" ]; then
  echo ">> applying private/offline hardening"
  gitlab-rails runner /opt/gl/harden.rb && touch "$DATA/.hardened"
fi

# Daily backup: app data + config/secrets (gitlab-backup does NOT include secrets)
(
  while sleep 86400; do
    gitlab-backup create CRON=1 || echo "backup failed"
    mkdir -p "$DATA/opt/backups"
    tar -C "$DATA" -czf "$DATA/opt/backups/config_$(date +%F).tgz" etc || true
    find "$DATA/opt/backups" -name 'config_*.tgz' -mtime +7 -delete
  done
) &

trap 'gitlab-ctl stop; exit 0' TERM INT
echo ">> GitLab up at $GITLAB_URL"
tail -F /var/log/gitlab/nginx/gitlab_access.log /var/log/gitlab/gitlab-rails/production.log 2>/dev/null &
wait $!
