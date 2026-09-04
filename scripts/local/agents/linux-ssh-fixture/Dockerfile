FROM ubuntu:24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openssh-server python3 sudo systemd systemd-sysv ca-certificates unzip \
 && useradd --create-home --shell /bin/bash alloytest \
 && printf 'alloytest ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/alloytest \
 && chmod 0440 /etc/sudoers.d/alloytest \
 && mkdir -p /run/sshd /run/fixture \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/linux-fixture-entrypoint
RUN chmod 0755 /usr/local/bin/linux-fixture-entrypoint

ENTRYPOINT ["/usr/local/bin/linux-fixture-entrypoint"]
CMD ["/sbin/init"]
