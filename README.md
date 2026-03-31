# Cassandra Health & Performance Check Script

A simple bash script to perform a one‑shot health and performance check of an Apache Cassandra node, including:

- Cluster and node health (via `nodetool`).  
- Performance metrics (latency, throughput, compaction, GC).  
- OS‑level system health (CPU, memory, disk usage, and I/O).  

The script outputs everything live on screen and simultaneously saves the result into a text file named after the node hostname (e.g., `myserver_node.txt`).

## Requirements

- Apache Cassandra node (or DSE) with `nodetool` and `cqlsh` in the `PATH`.
- `sysstat` and `iotop` (optional, recommended) for I/O stats:
  - Debian/Ubuntu:  
    ```bash
    sudo apt install sysstat iotop
    ```
  - RHEL/CentOS:  
    ```bash
    sudo yum install sysstat iotop
    # or
    sudo dnf install sysstat iotop
    ```

## How to Use

1. Clone this repo (or copy the script):

   ```bash
   git clone https://github.com/Mo7amedMostafa/Cassandra_Health_Check.git
   cd cassandra-health-check
   ```

2. Make the script executable:

   ```bash
   chmod +x cassandra_health_and_perf.sh
   ```

3. Run the script:

   ```bash
   ./cassandra_health_and_perf.sh
   ```

   - You will see the output **live in the terminal**.  
   - At the same time, everything is saved to a file named like `$(hostname -s)_node.txt` (e.g., `cassandra01_node.txt`).

4. (Optional) Run as a specific user that can access Cassandra and system tools:

   ```bash
   sudo -u cassandra ./cassandra_health_and_perf.sh
   ```

## Output File

The script generates a file with the format:

$(hostname -s)_node.txt

Example:
cassandra01_node.txt

This file can be used for:

- Comparing node behavior over time.  
- Sending logs to support or internal teams.  
- Automated collection via cron or orchestration tools.

## Customization

You can adjust:

- `NODETOOL` and `CQLSH` paths by editing:
  ```bash
  NODETOOL=${NODETOOL:-"/usr/bin/nodetool"}
  CQLSH=${CQLSH:-"/usr/bin/cqlsh"}
  ```
- Log and data directories (`LOG_DIR`, `CASS_DIR`).
- The output file path by changing `OUTPUT_FILE`:

  ```bash
  OUTPUT_FILE="/tmp/${NODE_HOSTNAME}_node.txt"
  ```

## Example Generated Output File

A typical run produces a text file with sections like:

- Cluster status (`nodetool status`).  
- Schema agreement.  
- Token ring.  
- Node info (load, uptime, heap).  
- Thread pool and dropped messages.  
- Compaction and GC stats.  
- Performance metrics (proxy histograms, table stats).  
- CQL connectivity test.  
- Disk usage and I/O statistics.

## License

This script is provided under the **MIT License** (see `LICENSE` file).  
Feel free to fork, modify, and integrate it into your monitoring workflows.
