# Jenkins image (jenkins-with-podman)

Custom Jenkins LTS image with **podman** pre-installed, used as the agent
for the Aqua Security pipeline demo.

## Why a custom image?

The Aqua pipeline runs `podman build`, `podman push`, and `podman run` from
inside the Jenkins container. The stock `jenkins/jenkins:lts` image ships
without podman, so we layer it on top.

## Build

Run on the Jenkins host (192.168.147.105):

```bash
cd infra/jenkins
podman build -t localhost/jenkins-with-podman:latest .
```

## Run

The container needs several non-default flags — SELinux workaround, the
host's podman socket mounted in, and host networking so Jenkins can reach
the local registry (`:8082`) and Aqua Console (`:8443`):

```bash
podman run -d --name jenkins --net=host --user root \
  --security-opt label=disable \
  -v jenkins_data:/var/jenkins_home \
  -v /run/podman/podman.sock:/var/run/docker.sock \
  -e JENKINS_USER=root \
  -e CONTAINER_HOST=unix:///var/run/docker.sock \
  -e PODMAN_IGNORE_CGROUPSV1_WARNING=1 \
  -e JENKINS_OPTS="--httpPort=8081 --httpListenAddress=0.0.0.0" \
  localhost/jenkins-with-podman:latest
```

### Flag rationale

| Flag | Why |
|---|---|
| `--net=host` | Jenkins needs to reach the local registry on `.105:8082` and Aqua Console on `.105:8443` directly. Bridge networking wouldn't route those. |
| `--security-opt label=disable` | SELinux on RHEL would otherwise deny the socket mount and overlay-on-overlay storage. |
| `-v /run/podman/podman.sock:/var/run/docker.sock` | Lets the *inner* podman (inside Jenkins) talk to the *host's* podman. Inner `podman build` then uses host storage and host image cache. |
| `-e CONTAINER_HOST=unix:///var/run/docker.sock` | Tells inner podman to use the mounted socket instead of trying rootless mode (which fails on `newuidmap`). |
| `--user root` + `JENKINS_USER=root` | Skips rootless complications for both the Jenkins agent and the inner podman. |
| `JENKINS_OPTS="--httpPort=8081"` | Avoid conflict with Aqua Console's alt UI on `:8080`. |

## Useful operations

```bash
podman logs -f jenkins          # follow the Jenkins startup log
podman exec -it jenkins bash    # shell into the Jenkins container
podman restart jenkins          # restart (safe — data is in the named volume)
podman stop jenkins && podman start jenkins   # same as restart
```

Data is persisted in the `jenkins_data` named volume, so restarts and even
container recreations don't lose jobs/builds/credentials.
