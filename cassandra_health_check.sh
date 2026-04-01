# https://github.com/Mo7amedMostafa/Cassandra_Health_Check/tree/main
# curl -fsSL https://raw.githubusercontent.com/Mo7amedMostafa/Cassandra_Health_Check/refs/heads/main/cassandra_health_check.sh | bash

#!/bin/bash
# Cassandra cluster health check script (run on each node)
#set -euo pipefail

NODETOOL=${NODETOOL:-"/usr/bin/nodetool"}
CQLSH=${CQLSH:-"/usr/bin/cqlsh"}
LOG_DIR=${LOG_DIR:-"/var/log/cassandra"}
CASS_DIR=${CASS_DIR:-"/var/lib/cassandra"}

# Get hostname (this will be part of the filename)
NODE_HOSTNAME=$(hostname -s)
OUTPUT_FILE="${NODE_HOSTNAME}_$(date '+%Y-%m-%d_%H:%M').txt"

# Send output to screen + file
exec > >(tee -a "$OUTPUT_FILE") 2>&1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Cassandra Cluster Health Check"
echo "Node: $NODE_HOSTNAME"
echo "Run time: $(date '+%Y-%m-%d %H:%M')"
echo "=========================================="
echo

# 1. Cluster status
echo "1. Cluster Status (nodetool status)"
echo "-----------------------------------"
echo "Explanation: Checks if all nodes are UP (UN) and in Normal state; any DN or multiple schema versions can indicate ring or node issues."
echo "------------------"
echo
echo 
"$NODETOOL" status
echo

# 2. Ring / token distribution
echo "============================================================="
echo "2. Token Ring Distribution"
echo "--------------------------"
echo "Explanation: Shows how data is distributed across nodes via tokens; uneven distribution can cause hotspots."
echo "------------------"
echo
echo  
"$NODETOOL" ring 
echo

# 3. Gossip info (load, schema, status)
echo "============================================================="
echo "3. Gossip Information"
echo "---------------------"
echo "Explanation: Displays gossip‑based status, load, and schema versions; inconsistency here can mean node communication or schema problems."
echo "------------------"
echo
echo 
"$NODETOOL" gossipinfo | grep -E "(STATUS|LOAD|SCHEMA)"
echo

# 4. Thread pool stats
echo "============================================================="
echo "4. Thread Pool Statistics"
echo "-------------------------"
echo "Explanation: Reports active/pending/blocked tasks; high pending or blocked counts indicate overload or GC pressure."
echo "------------------"
echo
echo  
"$NODETOOL" tpstats | grep -E "(Pool Name|Active|Pending|Blocked)" 
echo

# 5. Dropped messages (overload indicator)
echo "============================================================="
echo "5. Dropped Messages"
echo "--------------------"
echo "Explanation: Counts dropped messages in thread pools; any non‑zero value is a sign of overload or timeouts."
echo "------------------"
echo
echo  
dropped=$("$NODETOOL" tpstats | grep -E "(MUTATION|READ|COUNTER)" | awk '{sum += $5} END {print sum+0}')
if [ "$dropped" -gt 0 ]; then
echo -e "${RED}WARNING: $dropped dropped messages detected${NC}"
else
    echo -e "${GREEN}OK: No dropped messages${NC}"
fi
echo

# 6. Compaction stats
echo "============================================================="
echo "6. Compaction Statistics"
echo "------------------------"
echo "Explanation: Shows pending compactions and their impact on disk and CPU; high pending count can degrade performance."
echo "------------------"
echo
echo  
"$NODETOOL" compactionstats
echo

# 7. Schema agreement
echo "============================================================="
echo "7. Schema Agreement"
echo "-------------------"
echo "Explanation: Verifies that all nodes agree on the same schema version; disagreement can cause query or replication issues."
echo "------------------"
echo
echo  
schema_lines=$("$NODETOOL" describecluster | grep -A 100 "Schema versions:" | grep -c "\[" || echo 0)
if [ "$schema_lines" -eq 1 ]; then
    echo -e "${GREEN}OK: All nodes agree on schema${NC}"
else
    echo -e "${RED}WARNING: Schema disagreement detected ($schema_lines versions)${NC}"
    "$NODETOOL" describecluster | grep -A 20 "Schema versions:"
fi
echo

# 8. Node info (load, heap, uptime)
echo "============================================================="
echo "8. Node Info (Load, Heap, Uptime)"
echo "----------------------------------"
echo "Explanation: Checks node‑level load, heap usage, and uptime; high load or low heap can indicate resource pressure."
echo "------------------"
echo
echo  
"$NODETOOL" info | grep -E "(Load|ID|Gossip|Load|Uptime|Heap|Off)"
echo

# 9. Quick CQL connectivity
echo "============================================================="
echo "9. CQL Connectivity Test"
echo "------------------------"
echo "Explanation: Tests if CQL can connect to this node; failure here blocks application queries."
echo "------------------"
echo
echo  
if "$CQLSH" -e "SELECT cluster_name FROM system.local;" > /dev/null 2>&1; then
    echo -e "${GREEN}OK: CQL connection successful${NC}"
else
    echo -e "${RED}FAIL: Cannot connect via CQL${NC}"
fi
echo

# 10. Disk usage
echo "============================================================="
echo "10. Disk Usage (Cassandra data dir)"
echo "------------------------------------"
echo "Explanation: Checks disk space on the data directory; running out of space can cause node failure."
echo "------------------"
echo
echo  
if [ -d "$CASS_DIR" ]; then
    df -h "$CASS_DIR"
else
    echo -e "${YELLOW}WARNING: Cassandra data dir not found: $CASS_DIR${NC}"
fi
echo

# 11. Recent log errors/warnings
echo "============================================================="
echo "11. Recent log errors and warnings (last 100 lines)"
echo "---------------------------------------------------"
echo "Explanation: Scans recent log lines for critical issues (errors, GC, dropped messages) to catch transient problems."
echo "------------------"
echo
echo  
if [ -r "$LOG_DIR/system.log" ]; then
    # Capture last 100 lines matching keywords, then take last 20
    output=$(tail -100 "$LOG_DIR/system.log" | grep -i -E "(error|warn|exception|dropped|gc)" | tail -20)

    if [ -n "$output" ]; then
        echo "$output"
    else
        echo -e "${YELLOW}No recent errors/warnings (error|warn|exception|dropped|gc) in last 100 lines${NC}"
    fi
else
    echo -e "${YELLOW}Log file not found or not readable: $LOG_DIR/system.log${NC}"
fi
echo

# 12. Performance metrics: latency and throughput
echo "============================================================="
echo "12. Performance Metrics (Latency & Throughput)"
echo "---------------------------------------------"
echo "Explanation: Reports latency distributions and read/write rates per‑node and per‑table; spikes indicate performance degradation."
echo "------------------"
echo
echo  
echo "Proxy histograms (network operations, last ~5 min):"
echo "---------------------------------------------------"
"$NODETOOL" proxyhistograms
echo

echo "Recent request rates (read/write per second, last 15 min):"
echo "----------------------------------------------------------"
"$NODETOOL" tablestats --all | grep -E "(Read|Write|Local|Latency)" 
echo

echo "Per‑table histograms (top tables, last 15 min):"
echo "-----------------------------------------------"

for keyspace in $($CQLSH -e "DESC KEYSPACES;" | tr ' ' '\n' | grep -v "^$" | grep -E -v "^(system|system_.*|users_db)$"); do
    if "$CQLSH" -e "USE $keyspace; DESC TABLES;" >/dev/null 2>&1; then
        for table in $($CQLSH -e "USE $keyspace; DESC TABLES;" | tr ' ' '\n'); do
            if [ -n "$table" ] && [ "$table" != "keyspace_name" ]; then
                echo "=== $keyspace.$table ==="
                "$NODETOOL" tablehistograms "$keyspace" "$table" 
                echo
            fi
        done
    fi
done

# 13. GC pauses
echo "============================================================="
echo "13. GC STATISTICS:"
echo "-------------------"
echo "Explanation: Shows garbage collection behavior; long GC pauses can cause timeouts and dropped requests."
echo "------------------"
echo
echo 
"$NODETOOL" gcstats 
echo

# 16. Repair Status (Percent Repaired, user keyspaces only)
echo "============================================================="
echo "14. Repair Status (Percent Repaired – user keyspaces)"
echo "-----------------------------------------------------"
echo "Explanation: Checks what percentage of data per table has been repaired; low values may indicate need for repair operations."
echo 
echo
# List all keyspaces (exclude system*, reaper_db, etc.)
for keyspace in $($CQLSH -e "DESC KEYSPACES;" | tr ' ' '\n' | grep -v "^$" | grep -E -v "^(system|system_.*|users_db)$"); do
    if "$CQLSH" -e "USE $keyspace; DESC TABLES;" > /dev/null 2>&1; then
        echo "Keyspace: $keyspace"
        "$NODETOOL" tablestats "$keyspace" | awk '
            /Table:/ { table = $2 }
            /Percent repaired:/ { printf "%s.%-30s -> %s\n", "'"$keyspace"'", table, $3 }
        '
        echo
    fi
done

# 14. Node system health (CPU, memory, load, disk)
echo "============================================================="
echo "15. Node System Health (CPU, Memory, Load, Disk)"
echo "-------------------------------------------------"
echo "Explanation: Monitors OS‑level health (CPU, memory, disk usage); poor node health can severely hurt Cassandra performance."
echo
echo  
echo "Uptime:"
echo "-------"
uptime
echo

echo "CPU Load (1, 5, 15 min):"
echo "------------------------"
uptime | awk -F'[a-z]:' '{print $2}' | xargs
echo

echo "CPU Cores and model:"
echo "---------------------"
lscpu | grep -E "Architecture|CPU\(s\)|Thread|Model name" | head -8
echo

echo "Memory usage:"
echo "-------------"
free -h
echo

echo "Swap usage:"
echo "-----------"
free -h | grep Swap
echo

echo "Disk usage (all partitions):"
echo "----------------------------"
df -h | grep -v "tmpfs\|udev"
echo

echo "Top 5 CPU‑heavy processes:"
echo "--------------------------"
ps aux --sort=-%cpu | head -6 | awk 'NR==1{print; next} {printf "%-10s %-6s %-5s %-5s %-8s %-8s %-6s %-6s %-8s %-6s %.60s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,substr($0,index($0,$11))}'
echo

echo "Top 5 Memory‑heavy processes:"
echo "-----------------------------"
ps aux --sort=-%mem | head -6 | awk 'NR==1{print; next} {printf "%-10s %-6s %-5s %-5s %-8s %-8s %-6s %-6s %-8s %-6s %.60s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,substr($0,index($0,$11))}'
echo

# 15. Disk I/O statistics
echo "============================================================="
echo "16. Disk I/O Statistics"
echo "------------------------"
echo "Explanation: Shows disk throughput, IOPS, and utilization; high utilization or long wait times can bottleneck Cassandra."
echo 

if command -v iostat >/dev/null 2>&1; then
    echo "Disk I/O stats (all devices, one snapshot):"
    echo "--------------------------------------------"
    iostat -x 1 1 | tail -n +4  # skip averages, show last sample only
    echo
else
    echo "iostat not found (usually in 'sysstat' package)."
    echo "Consider: apt install sysstat  or yum install sysstat"
    echo
fi


echo "=========================================="
echo "Health check complete"
echo "=========================================="
echo "Saved to: $OUTPUT_FILE"
