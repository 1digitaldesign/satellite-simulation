# 30 Transmission Algorithms

The physics simulation supports 30 selectable transmission algorithms. Choose one from the **Algorithm** dropdown in the UI; all nodes use the same algorithm for the run. Packet transfer remains physics-based (packets move as bodies along links); the algorithm controls **which** packet is sent next, **which** link is used when several are up, and **what** to drop when storage is full.

---

## 1–10: Queue scheduling (which bundle to send next)

| # | Name | Behavior |
|---|------|----------|
| 1 | FIFO | First In First Out: oldest bundle for that destination. |
| 2 | LIFO | Last In First Out: newest bundle for that destination. |
| 3 | Priority (dest) | Prefer lower destination node ID. |
| 4 | Shortest Job First | Prefer smallest bundle (by size in bits). |
| 5 | Longest Job First | Prefer largest bundle. |
| 6 | Round Robin (dest) | Rotate among destinations. |
| 7 | Earliest Deadline First | Prefer earliest creation time. |
| 8 | Largest Bundle First | Same as Longest Job First. |
| 9 | Smallest Bundle First | Same as Shortest Job First. |
| 10 | Weighted Fair Queuing | Per-destination fairness (FIFO per dest). |

---

## 11–18: Routing / link selection (which link to drain when multiple are up)

| # | Name | Behavior |
|---|------|----------|
| 11 | Contact Plan Only | Default order from contact plan. |
| 12 | Earliest Contact | Prefer link whose contact window opens soonest. |
| 13 | Longest Contact | Prefer link with longest remaining window. |
| 14 | Max Rate | Prefer highest rate (bits/sec) link. |
| 15 | Random Link | Random order among up links. |
| 16 | Round Robin Link | Rotate among links each step. |
| 17 | Min Delay | Prefer earliest contact start (like Earliest Contact). |
| 18 | Shortest Path (hops) | Same as Contact Plan Only (single hop in this sim). |

---

## 19–22: Retransmission (ARQ)

| # | Name | Behavior |
|---|------|----------|
| 19 | No ARQ | No retransmission; drop on loss. |
| 20 | Go-Back-N | Placeholder (same queue behavior as No ARQ in this sim). |
| 21 | Selective Repeat | Placeholder (same as No ARQ). |
| 22 | Stop-and-Wait | Placeholder (same as No ARQ). |

*ARQ algorithms currently use the same forwarding and drop behavior as No ARQ; they are reserved for future retransmission logic.*

---

## 23–30: Drop / congestion policy (when storage is full)

| # | Name | Behavior |
|---|------|----------|
| 23 | Drop New | Reject the incoming bundle (HDTN-style). |
| 24 | Drop Oldest | Evict the oldest bundle (by creation time) to make room. |
| 25 | Drop Newest | Evict the newest stored bundle. |
| 26 | Random Drop | Evict a randomly chosen stored bundle. |
| 27 | RED-like | Probabilistic drop based on fill ratio. |
| 28 | Priority Drop (low) | Evict a bundle destined for the lowest node ID. |
| 29 | Fair Share Drop | Evict from one destination’s queue (tail). |
| 30 | Drop Tail | Reject new (same as Drop New). |

---

## How to compare

1. Run the simulation (F5).
2. Use the **Algorithm** dropdown to switch among the 30 algorithms.
3. Observe **Storage**, **In flight**, **Delivered**, and per-node telemetry (including drops).
4. All packets still move as physics bodies along links; only scheduling, link choice, and drop policy change with the algorithm.
