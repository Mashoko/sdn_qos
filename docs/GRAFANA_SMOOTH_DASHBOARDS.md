# Smooth Grafana Dashboards for ZAN QoS Metrics

The telemetry collector writes to InfluxDB every **~2 seconds** (Prioritized and Unprioritized in parallel, then 2s sleep). (both Prioritized and Unprioritized in parallel). Use these settings so panels update smoothly instead of jumping.

## Dashboard-level settings

| Setting | Recommended | Why |
|--------|-------------|-----|
| **Refresh** | `5s` or `10s` | Matches data cadence; avoids heavy reloads every 1s |
| **Time range** | Last 15 minutes | Keeps query fast; enough history to see trends |

## Panel query settings (InfluxQL)

Use a **small group-by interval** and **fill** so the line interpolates between points:

| Setting | Recommended | Why |
|--------|-------------|-----|
| **GROUP BY time interval** | `5s` or `10s` | Aligns with data every ~2s; smooth curve |
| **Fill** | `previous` or `linear` | No gaps when a single iperf fails; line stays continuous |

### Example queries

**Jitter (ms) – by stream type**
```sql
SELECT mean("value") AS "jitter_ms"
FROM "network_jitter"
WHERE $timeFilter
GROUP BY time(5s), "stream_type" fill(previous)
```

**Bandwidth (bps) – by stream type**
```sql
SELECT mean("bandwidth_bps") AS "bandwidth_bps"
FROM "network_metrics"
WHERE $timeFilter
GROUP BY time(5s), "stream_type" fill(previous)
```

**Packet loss (%) – by stream type**
```sql
SELECT mean("packet_loss_percent") AS "packet_loss_percent"
FROM "network_metrics"
WHERE $timeFilter
GROUP BY time(5s), "stream_type" fill(previous)
```

## If the graph still looks choppy

1. **Check data is flowing**  
   InfluxDB Data Explorer / Explore: run  
   `SELECT * FROM network_metrics WHERE time > now() - 5m`  
   You should see points every few seconds.

2. **Shorten group-by interval**  
   Try `GROUP BY time(2s)` so each bucket has at most one point (no aggregation); use `fill(previous)` so missing buckets don’t create gaps.

3. **Avoid huge time ranges**  
   “Last 1 hour” with 5s interval = many buckets; use “Last 15 minutes” for smoother rendering.

4. **Panel resolution**  
   In Panel → Query options, ensure **Min step** or resolution isn’t forcing 1m or larger; 5s–10s is enough.

## Pre-built dashboard (smooth queries + refresh)

Import the provided dashboard so panels use the right interval and fill:

1. In Grafana: **Dashboards** → **New** → **Import**.
2. Upload or paste the contents of **`grafana/dashboards/zan_qos_smooth.json`**.
3. Select your **InfluxDB** data source (database `zan_qos_metrics`).
4. Click **Import**.

The dashboard uses **Refresh: 5s**, **Time range: Last 15 minutes**, and **GROUP BY time(5s) fill(previous)** for smooth curves.
