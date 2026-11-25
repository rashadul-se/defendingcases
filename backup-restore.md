# Backup / restore (run in Render > Shell)
gitlab-backup create                         # app data -> /data/opt/backups
tar -C /data -czf /data/opt/backups/config_manual.tgz etc   # secrets + config
# Download both off-box regularly (render shell + scp/rclone) — the disk is your only copy.

# Restore on a fresh service of the SAME GitLab version:
tar -C /data -xzf config_xxx.tgz              # restore /data/etc first
gitlab-ctl reconfigure && gitlab-ctl stop puma && gitlab-ctl stop sidekiq
gitlab-backup restore BACKUP=<timestamp_gitlab_version>
gitlab-ctl restart
