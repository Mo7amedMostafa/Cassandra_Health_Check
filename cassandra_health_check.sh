#!/bin/bash
# Cassandra cluster health check script (run on each node)
#set -euo pipefail

NODETOOL=${NODETOOL:-"/usr/bin/nodetool"}
CQLSH=${CQLSH:-"/usr/bin/cqlsh"}
LOG_DIR=${LOG_DIR:-"/var/log/cassandra"}
CASS_DIR=${CASS_DIR:-"/var/lib/cassandra"}

# Get hostname (this will be part of the filename)
NODE_HOSTNAME=$(hostname -s)
OUTPUT_FILE="${NODE_HOSTNAME}.txt"

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
echo "Run time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo

# 1. Cluster status
echo "1. Cluster Status (nodetool status)"
echo "-----------------------------------"
"$NODETOOL" status
echo

# 2. Ring / token distribution
echo "2. Token Ring Distribution"
echo "--------------------------"
"$NODETOOL" ring | head -20
echo

# 3. Gossip info (load, schema, status)
echo "3. Gossip Information"
echo "---------------------"
"$NODETOOL" gossipinfo | grep -E "(STATUS|LOAD|SCHEMA)" | head -20
echo

# 4. Thread pool stats
echo "4. Thread Pool Statistics"
echo "-------------------------"
"$NODETOOL" tpstats | grep -E "(Pool Name|Active|Pending|Blocked)" | head -15
echo

# 5. Dropped messages (overload indicator)
echo "5. Dropped Messages"
echo "--------------------"
dropped=$("$NODETOOL" tpstats | grep -E "(MUTATION|READ|COUNTER)" | awk '{sum += $5} END {print sum+0}')
if [ "$dropped" -gt 0 ]; then
echo -e "${RED}WARNING: $dropped dropped messages detected${NC}"
else
    echo -e "${GREEN}OK: No dropped messages${NC}"
fi
echo

# 6. Compaction stats
echo "6. Compaction Statistics"
echo "------------------------"
"$NODETOOL" compactionstats
echo

# 7. Schema agreement
echo "7. Schema Agreement"
echo "-------------------"
schema_lines=$("$NODETOOL" describecluster | grep -A 100 "Schema versions:" | grep -c "\[" || echo 0)
if [ "$schema_lines" -eq 1 ]; then
    echo -e "${GREEN}OK: All nodes agree on schema${NC}"
else
    echo -e "${RED}WARNING: Schema disagreement detected ($schema_lines versions)${NC}"
    "$NODETOOL" describecluster | grep -A 20 "Schema versions:"
fi
echo

# 8. Node info (load, heap, uptime)
echo "8. Node Info (Load, Heap, Uptime)"
echo "----------------------------------"
"$NODETOOL" info | grep -E "(Load|ID|Gossip|Load|Uptime|Heap|Off)"
echo

# 9. Quick CQL connectivity
echo "9. CQL Connectivity Test"
echo "------------------------"
if "$CQLSH" -e "SELECT cluster_name FROM system.local;" > /dev/null 2>&1; then
    echo -e "${GREEN}OK: CQL connection successful${NC}"
else
    echo -e "${RED}FAIL: Cannot connect via CQL${NC}"
fi
echo

# 10. Disk usage
echo "10. Disk Usage (Cassandra data dir)"
echo "------------------------------------"
if [ -d "$CASS_DIR" ]; then
    df -h "$CASS_DIR"
else
    echo -e "${YELLOW}WARNING: Cassandra data dir not found: $CASS_DIR${NC}"
fi
echo

# 11. Recent log errors/warnings
echo "11. Recent log errors and warnings (last 100 lines)"
echo "---------------------------------------------------"
if [ -r "$LOG_DIR/system.log" ]; then
#    tail -100 "$LOG_DIR/system.log" | grep -i -E "(error|warn|exception|dropped|gc)" | tail -20
#else
    echo -e "${YELLOW}Log file not found or not readable: $LOG_DIR/system.log${NC}"
fi
echo

# 12. Performance metrics: latency and throughput
echo "12. Performance Metrics (Latency & Throughput)"
echo "---------------------------------------------"

echo "Proxy histograms (network operations, last ~5 min):"
"$NODETOOL" proxyhistograms
echo

echo "Recent request rates (read/write per second, last 15 min):"
"$NODETOOL" tablestats --all | grep -E "(Read|Write|Local|Latency)" | head -30
echo

echo "Per‑table histograms (top tables, last 15 min):"
for keyspace in $($CQLSH -e "desc keyspaces;" | tr ' ' '\n' | grep -v "^$"); do
    if "$CQLSH" -e "USE $keyspace; DESC TABLES;" >/dev/null 2>&1; then
        for table in $($CQLSH -e "USE $keyspace; DESC TABLES;" | tr ' ' '\n' | head -3); do
            if [ -n "$table" ] && [ "$table" != "keyspace_name" ]; then
                echo "=== $keyspace.$table ==="
                "$NODETOOL" tablehistograms "$keyspace" "$table" | head -20
            fi
        done
    fi
done

# 13. GC pauses
echo "GC STATISTICS:"
echo "----------------"
"$NODETOOL" gcstats | head -20
echo

# 14. Node system health (CPU, memory, load, disk)
echo "14. Node System Health (CPU, Memory, Load, Disk)"
echo "-------------------------------------------------"

echo "Uptime:"
uptime
echo

echo "CPU Load (1, 5, 15 min):"
uptime | awk -F'[a-z]:' '{print $2}' | xargs
echo

echo "CPU Cores and model:"
lscpu | grep -E "Architecture|CPU\(s\)|Thread|Model name" | head -8
echo

echo "Memory usage:"
free -h
echo

echo "Swap usage:"
free -h | grep Swap
echo

echo "Disk usage (all partitions):"
df -h | grep -v "tmpfs\|udev"
echo

echo "Top 5 CPU‑heavy processes:"
ps aux --sort=-%cpu | head -6 | awk 'NR==1{print; next} {printf "%-10s %-6s %-5s %-5s %-8s %-8s %-6s %-6s %-8s %-6s %.60s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,substr($0,index($0,$11))}'
echo

echo "Top 5 Memory‑heavy processes:"
ps aux --sort=-%mem | head -6 | awk 'NR==1{print; next} {printf "%-10s %-6s %-5s %-5s %-8s %-8s %-6s %-6s %-8s %-6s %.60s\n", $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,substr($0,index($0,$11))}'
echo

# 15. Disk I/O statistics
echo "15. Disk I/O Statistics"
echo "------------------------"

if command -v iostat >/dev/null 2>&1; then
    echo "Disk I/O stats (all devices, one snapshot):"
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
