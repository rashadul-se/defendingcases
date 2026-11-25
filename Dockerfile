ARG FEDORA_VERSION=43
FROM fedora:${FEDORA_VERSION}

# GitLab only publishes EL packages; the EL9 RPM runs on Fedora (unsupported by GitLab, works in practice).
RUN dnf -y install --setopt=install_weak_deps=False \
      curl ca-certificates openssh-server perl tzdata procps-ng which cronie \
      python3 jq tar gzip glibc-langpack-en \
    && dnf clean all

RUN printf '%s\n' \
 '[gitlab_gitlab-ce]' \
 'name=gitlab_gitlab-ce' \
 'baseurl=https://packages.gitlab.com/gitlab/gitlab-ce/el/9/$basearch' \
 'repo_gpgcheck=1' 'gpgcheck=1' 'enabled=1' \
 'gpgkey=https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey' \
 > /etc/yum.repos.d/gitlab-ce.repo \
 && dnf -y install gitlab-ce && dnf clean all

COPY entrypoint.sh harden.rb /opt/gl/
RUN chmod +x /opt/gl/entrypoint.sh

ENV LANG=en_US.UTF-8 PORT=10000
EXPOSE 10000
ENTRYPOINT ["/opt/gl/entrypoint.sh"]
