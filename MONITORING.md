# Monitoring notes (Prometheus + Grafana)

Running notes for the RK1 cluster monitoring work. Deployment is done with
`just deploy tag=prometheus` / `just deploy tag=smartctl` (or `just deploy_all`).

## What has been done

### Grafana dashboard
- `Cluster Dashboard (Prometheus).json` is a Grafana v2 export
  (`dashboard.grafana.app/v2`, `kind: Dashboard`, `metadata.name: fihq2bj`).
  The original source export is no longer present in the working tree.
- Every query targets the Prometheus datasource UID `ffhsn15fwruo0c`; all
  InfluxDB queries were replaced.
- Node panels resolve host names via
  `* on (instance) group_left (nodename) node_uname_info{sbc="true"}` and use
  `{{nodename}}`, so legends show `rk1-cluster01…04` instead of IPs.
- NVMe Usage now computes percentage used for `/mnt/nvme`; Bulk Storage shows
  used + total for `/mnt/storage`.
- 26 panels total (id 7, 8, 20, 21, 29, 32–36 from the export plus 100–115):
  filesystem/inode usage, disk throughput/IOPS/utilization/latency, CPU,
  memory, filesystem health, conntrack, network errors/drops, SMART health /
  temperature / wear / media errors, and container memory.
- SMART metric names were corrected against smartctl_exporter v0.15.0:
  `smartctl_device_smart_status` (1 = passed), `temperature_type="current"`,
  and `smartctl_device_attribute{attribute_name="Reallocated_Sector_Ct",
  attribute_value_type="raw"}` for reallocated sectors.

### smartctl-exporter (per node, outside Docker Swarm)
- Swarm cannot run this workload privileged: `docker service create` has no
  `--privileged` flag and `community.docker.docker_swarm_service` has no
  privileged option. Without it smartctl cannot read the drives, so the
  previous global service produced no usable SMART data.
- `tasks/smartctl-exporter.yml` runs a standalone (non-Swarm) container on
  every node via `community.docker.docker_container`:
  `prometheuscommunity/smartctl-exporter:v0.15.0`, `privileged: true`,
  `user: root`, `network_mode: host` (listens on node IP:9633),
  `restart_policy: unless-stopped`, log rotation, `TZ=America/Chicago`.
- `deploy.yml` has a new play `Deploy node exporters outside Docker Swarm`
  targeting all nodes (`tags: [prometheus, smartctl]`).
  `tasks/prometheus.yml` removes the old Swarm service if present.
- Prometheus scrapes static targets `10.1.1.31–34:9633` with
  `host: rk1-cluster0X` labels (the IP → host mapping matches
  `node_uname_info` / DNS).
- Deployed and verified: one container per node, privileged + host network,
  all four targets `up`, six drives (four `nvme0` + `sda`/`sdb` on
  rk1-cluster03), and a rerun reports `changed=0`.

### cAdvisor
- Image moved from `gcr.io/cadvisor/cadvisor` (amd64-only and no longer
  publishing these tags) to `ghcr.io/google/cadvisor:v0.60.6`, which is a
  multi-arch index including `linux/arm64`.
- The service is enabled again as a global Swarm service: `state: absent`
  removed, the `node.platform.arch == x86_64` constraint dropped, and
  `-docker_only` passed through `args` (the module's `command` overwrites the
  image entrypoint).
- Removed the copy-pasted Traefik labels (they reused Prometheus' router name
  and port 9090) and the stray `prometheus-data` mount.
- Prometheus now runs as `user: root`: the official image runs as `nobody`
  and the Docker socket is `root:docker 0660`, which caused
  `permission denied` for Swarm service discovery.
- Deployed and verified: four cAdvisor targets `up` on the `traefik_proxy`
  overlay; `container_cpu_usage_seconds_total`,
  `container_memory_working_set_bytes`, `container_last_seen` and
  `container_label_com_docker_swarm_service_name` all return data with the
  correct `host` labels.

### node_exporter mount-error false positives
- The dashboard's `Filesystem Health` panel was showing 3–4 "Mount errors".
  All of them were `node_filesystem_device_error{mountpoint="/run/user/1000"}`:
  node_exporter runs as `node-exp` (uid 998) and cannot `statfs()` the
  per-user tmpfs `/run/user/1000` (mode 0700, owned by `ubuntu`). The mount
  only exists while an `ubuntu` login session is active, so the count came and
  went with logins. No drive or filesystem was actually failing.
- `vars/main.yml` now overrides `node_exporter_enabled_collectors` for the
  `node_exporter` role: it keeps `systemd` + `textfile` and adds the
  `filesystem` collector with a `mount-points-exclude` regex that preserves
  the binary's defaults (`/dev`, `/proc`, `/sys`, `/var/lib/docker`, …) and
  additionally excludes `run/user/.+`.
- Deployed with `--tags node_exporter`. Verified: the running process has the
  new flag, `sum(node_filesystem_device_error{sbc="true"})` is 0, no
  `/run/user/1000` series remain, and `/run` / `/run/lock` are still exported.

### SMART dashboard panel drift
- The `Drive Health (SMART)` panel showed "No data" even though smartctl-exporter
  was scraping correctly. The dashboard in Grafana was an older revision than
  `Cluster Dashboard (Prometheus).json` and still queried metric names that do
  not exist in smartctl_exporter v0.15.0:
  `smartctl_device_health_ok` (0 series) instead of
  `smartctl_device_smart_status` (6 series).
- Two more SMART panels had the same drift: `Drive Temperature` queried
  `smartctl_device_temperature` without `{temperature_type="current"}`, mixing
  all temperature types; `Drive Errors` queried
  `smartctl_device_reallocated_sector_ct` (0 series) instead of the
  `smartctl_device_attribute{attribute_name="Reallocated_Sector_Ct",
  attribute_value_type="raw"}` series (ATA disks only).
- Patched the live dashboard (`fihq2bj`, version 7) to the queries already in
  the repo file. Verified through Grafana's own datasource query API: Drive
  Health and Drive Temperature each return 6 series, media errors 4, ATA
  reallocated sectors 2 (rk1-cluster03 `sda`/`sdb`).

### Fleet state at time of writing
- Branches: `main`. Nothing committed yet.
- Prometheus: v3.7.3, running on `rk1-cluster01` (Swarm leader).
- Grafana datasource UID: `ffhsn15fwruo0c`.

## TODO

1. Commit the work: dashboard JSON, `tasks/smartctl-exporter.yml`, and the
   changes to `deploy.yml`, `tasks/prometheus.yml`,
   `templates/prometheus/prometheus.yml.j2`, `vars/main.yml`.
2. Import/provision `Cluster Dashboard (Prometheus).json` in Grafana and check
   every panel renders. There is no dashboard provisioning yet — the JSON has
   to be imported by hand.
3. The datasource UID `ffhsn15fwruo0c` is hardcoded in all panels. Make Grafana
   provisioning stable (or switch the dashboard to a datasource variable) so a
   rebuilt Grafana does not break every panel.
4. Add alert rules (SMART failure/temperature, filesystem/inode usage, node
   down, conntrack pressure). There are currently no rule files and no
   Alertmanager targets.
5. Review the security posture: Prometheus runs as root with the Docker socket,
   and smartctl-exporter is privileged on every node. A socket proxy and
   per-device mounts (`/dev/nvme*`, `/dev/sd*`) would reduce the blast radius.
6. cAdvisor runs unprivileged because of the Swarm limitation. If per-container
   network or disk metrics turn out to be missing, evaluate `cap_add` /
   `device` options or move cAdvisor out of Swarm like smartctl.
7. Container CPU/memory panels group by `name`, which shows Swarm task names
   with random suffixes. Group by
   `container_label_com_docker_swarm_service_name` for readable legends.
8. Swarm service discovery requires Prometheus to run on a manager. It works
   today because `node.labels.bigmem == true` resolves to `rk1-cluster01`
   (leader); add an explicit manager constraint or document that dependency.
9. `force_update: true` recreates Prometheus and cAdvisor on every deploy.
   cAdvisor task IPs churn, and discovery can take up to 60s to refresh (short
   scrape gaps). Consider a shorter SD `refresh_interval` and dropping
   `force_update` where it is not needed.
10. Investigate the TSDB warnings from the restart during this work
    (`lock DB directory: resource temporarily unavailable`,
    `out of sequence m-mapped chunk ... discarding chunk files`); confirm no
    data loss, e.g. with `promtool tsdb analyze`.
11. Prune the old `gcr.io/cadvisor/cadvisor:v0.35.0` images from the nodes.
12. Decide whether the node exporters should also be deployed by
    `just update_all` (infrastructure.yml); today they only run through
    `deploy.yml`.
