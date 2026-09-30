# Jenkins image with podman pre-installed.
#
# Used by the Aqua Security pipeline demo to run `podman build/push/run`
# inside the Jenkins agent. Built once on the Jenkins host (192.168.147.105)
# and tagged as `localhost/jenkins-with-podman:latest`.
#
# Build:
#   cd infra/jenkins
#   podman build -t localhost/jenkins-with-podman:latest .
#
# See README.md for the full `podman run` command to start the Jenkins
# container, including the SELinux and socket-mount flags this image
# depends on.

FROM docker.io/jenkins/jenkins:lts
USER root
RUN apt-get update && apt-get install -y --no-install-recommends podman \
    && rm -rf /var/lib/apt/lists/*
USER jenkins
