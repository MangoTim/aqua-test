# Aqua Security Pipeline Demo — Runbook

End-to-end setup for the **Jenkins → local registry → Aqua Console scan**
demo. Follows the steps in order; each section is a hard prerequisite for
the next.

## 0. Prerequisites

Verify these are in place before starting:

- **Aqua Console + Gateway** running and licensed
  - Console UI: `https://192.168.147.105:8443` (or `:8080` for HTTP)
  - Admin login works
- **Postgres** at `192.168.147.103:5432` with `scalock` + `slk_audit` databases
- **Internet access** from `192.168.147.105` (the scanner CLI pulls vuln feeds from `cybercenter.aquasec.com`)
- **Podman** on `192.168.147.105`
- **Git** on `192.168.147.105`
- **Admin SSH** to `192.168.147.105` as `root`

## 1. Start a local Docker registry

A local registry is used so the demo is fully self-contained (no Azure /
no cloud cost). Skip if you already have one running.

```bash
podman run -d --name registry \
  -p 8082:8082 \
  -v registry_data:/var/lib/registry \
  -e REGISTRY_HTTP_ADDR=:8082 \
  docker.io/library/registry:2
```

Verify:
```bash
curl -s http://192.168.147.105:8082/v2/_catalog
# expected: {"repositories":[]}
```

## 2. Register the registry in Aqua Console

In the Console UI:

1. **Registries → Add Registry**
2. Name: `jenkins-demo`
3. URL: `http://192.168.147.105:8082`
4. Username / Password: leave blank (no auth on the demo registry)
5. Click **Test Connection** (may hang on actual blob pull; that's OK —
   `wget` from inside the `aqua-web` container can confirm reachability
   independently)
6. **Save** even if Test Connection hangs

## 3. Create the assurance policy

**Images → Assurance → Policies → Create Policy**

For this demo, the policy only gates on malware + non-root user (it does
NOT gate on CVEs):

| Setting | Value |
|---|---|
| Name | `testing-image-assurance` |
| Scope | `Registry = jenkins-demo` |
| Controls | `malware`, `root_user` |

To gate on CVEs in production, add a vulnerability-based control with a
score threshold (e.g. "fail if score ≥ 7.0").

## 4. Build the Jenkins image

```bash
cd infra/jenkins
podman build -t localhost/jenkins-with-podman:latest .
```

See `infra/jenkins/README.md` for the rationale behind this image.

## 5. Start the Jenkins container

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

Wait ~30–60 sec, then:
```bash
podman logs jenkins 2>&1 | grep -i "fully up and running"
curl -sI http://192.168.147.105:8081/login | head -1
# expected: HTTP/1.1 200  (or 403 — both mean Jenkins is up)
```

## 6. First-time Jenkins setup

Open `http://192.168.147.105:8081` in your browser.

1. **Unlock Jenkins** — the initial admin password is in the container log:
   ```bash
   podman exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
   ```
2. **Install suggested plugins** — wait for the default set to finish
3. **Create the first admin user** — e.g. `admin` / your password

## 7. Install the additional plugins

**Manage Jenkins → Plugins → Available** → search and install:

- **Aqua Security Scanner** 3.2.10
  - Provides `org.jenkinsci.plugins.aquadockerscannerbuildstep.AquaScannerAction`
    (used by the Jenkinsfile's `script {}` block to render the
    "Aqua Scan - <image>" sidebar)

After install, **restart Jenkins once** to fully activate the plugin:
```bash
podman restart jenkins
```

## 8. Create the Aqua Console credential

**Manage Jenkins → Credentials → (global) → Add Credentials**

| Field | Value |
|---|---|
| Kind | Username with password |
| ID | `aqua-console` |
| Username | `administrator` |
| Password | the Aqua Console admin password |
| Description | Aqua Console admin |

The Jenkinsfile references this credential by the ID `aqua-console` via
`withCredentials([usernamePassword(credentialsId: 'aqua-console', ...)])`
to inject the password for the scanner CLI's `--user` / `--password` flags.

## 9. Configure the pipeline

**New Item → Pipeline** → name it `aqua-demo`.

In the job config:

- **Definition**: `Pipeline script from SCM`
- **SCM**: `Git`
- **Repository URL**: `https://github.com/MangoTim/aqua-test.git`
- **Branch**: `test-v1`
- **Script Path**: `Jenkinsfile`

## 10. Place the Jenkinsfile in the repo

The Jenkinsfile at the repo root is what Jenkins reads. The current
working version lives at:
`https://github.com/MangoTim/aqua-test/blob/test-v1/Jenkinsfile`

(Or `C:\Users\tim.wong\Desktop\claude\claude-code\Jenkinsfile.aqua-demo` on
your laptop — that's the editable source. Copy it into the repo root as
`Jenkinsfile` and push.)

The Jenkinsfile header has a `One-time setup required` block listing every
admin step that's required before the **first** build — re-read it before
running.

## 11. Pre-approve script signatures (FIRST BUILD ONLY)

The Jenkinsfile has a `script {}` block that uses `Class.forName` and
`Run.addAction` to recreate the "Aqua Scan - <image>" sidebar. Jenkins'
sandbox rejects both signatures by default.

**Approve them before the first build to skip the back-and-forth:**

1. Navigate to `http://192.168.147.105:8081/scriptApproval`
2. Sign in if prompted
3. You should see 2 pending signatures:
   - `staticMethod java.lang.Class forName java.lang.String`
   - `method hudson.model.Run addAction hudson.model.Action`
4. Click **Approve** for each

If you skip this step, Jenkins will fail the first build with a sandbox
rejection message that includes the exact signature to approve — copy it
back into the approval page and retry.

## 12. Run the first build

Click **Build Now** on the `aqua-demo` pipeline.

Expected flow:
1. **Checkout** — git clone of `test-v1`
2. **Build Image** — `podman build` of the Flask app (~30s)
3. **Push to Registry** — pushes to `192.168.147.105:8082/aqua-demo:<N>`
4. **Aqua Security Scan** — runs the scanner CLI against the pushed image;
   console ends with `Image Is Compliant` or `Image Is Non-compliant`
5. **Post** — archives `aqua-report.html`, runs the sidebar script

If everything works, the build page should show an **"Aqua Scan - <image>"**
link in the left sidebar (rendered by the Aqua plugin's Action class).
Click it to view the full HTML report.

## 13. Demo CVE detection (optional)

To show the scanner catching vulnerabilities:

1. Edit `requirements.txt` in the repo:
   ```
   Flask==2.1.1
   Werkzeug==2.0.2      # ← revert from 3.0.3 to introduce CVEs
   ```
2. Commit + push to `test-v1`
3. Trigger a new build
4. The scanner will still report `Image Is Compliant` because
   `testing-image-assurance` only gates on malware + `root_user`. To
   actually fail the pipeline on CVEs, you have three options:
   - **A** — Add a vulnerability-based control to the Aqua Console policy
     (e.g. "fail on critical CVEs")
   - **B** — Parse `aqua-report.json` in the Jenkinsfile and fail the
     build on `vulnerability_summary.critical > 0`
   - **C** — Leave it informational (the report still shows all CVEs;
     the pipeline just doesn't fail on them)

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `accepts 1 arg(s), received 2` from scanner | Plugin v3.2.10's broken command (not used in this Jenkinsfile) | Already worked around — we use the manual sidecar scanner |
| `ClassNotFoundException: AquaScannerAction` | Aqua plugin JAR not loaded | Verify Aqua Scanner 3.2.10 is in **Manage Plugins → Installed** and shows no warning; restart Jenkins |
| `Scripts not permitted to use staticMethod java.lang.Class forName` | Sandbox rejection | Approve the signature at `/scriptApproval` |
| Build dies with `cp: can't stat 'requirements.txt'` | Wrong branch or wrong repo | Confirm Jenkinsfile points to `MangoTim/aqua-test` branch `test-v1` |
| Scanner timeout (60s) | Local registry hung or scanner can't pull | Check `curl http://192.168.147.105:8082/v2/_catalog` works |
| Pipeline fails: `apt-get update` inside build | Base image lacks network | Verify `192.168.147.105` has internet — `ping google.com` from the Jenkins host |

## Files in this repo

| Path | Purpose |
|---|---|
| `Dockerfile` | Flask demo app — used by Jenkinsfile's **Build Image** stage |
| `requirements.txt` | Flask deps — `pip install -r` inside the Flask Dockerfile |
| `app.py` | The Flask welcome page |
| `Jenkinsfile` | The pipeline definition Jenkins reads |
| `infra/jenkins/Dockerfile` | Recipe for the Jenkins+podman image |
| `infra/jenkins/README.md` | How to build and run the Jenkins container |
| `docs/DEMO-RUNBOOK.md` | This file |
