# Moonstone

A Godot 4.x project featuring an **HDTN (High-rate Delay Tolerant Network) demonstration** based on [NASA HDTN](https://github.com/nasa/HDTN).

## Requirements

- [Godot Engine 4.3+](https://godotengine.org/download) (standard or .NET for C#)

## Running the project

1. Open Godot and choose **Import** or **Scan** to add this folder as a project.
2. Select the project and click **Edit** (or double-click).
3. Press **F5** or click **Run Project** to run the HDTN simulation.

Or from the terminal (with Godot on your PATH):

```bash
godot --path . res://scenes/simulation/hdtn_sim.tscn
```

## HDTN simulation

The main scene runs a visual simulation of NASA-style Delay Tolerant Networking ([nasa/HDTN](https://github.com/nasa/HDTN)):

- **Contact plan** – Links between nodes (e.g. CubeSats, ground) are up only during scheduled windows (`data/contact_plan.json`). Optional `storageCapacityBytes` sets per-node storage cap (HDTN-style).
- **Router** – Decides link up/down from the contact plan; storage releases bundles when a link comes up.
- **Nodes** – Ingress (receive), Storage (hold when link down, capacity-limited), Egress (send at contact rate). Bundles over capacity are dropped; telemetry shows In/Out/Storage/Delivered/Dropped.
- **Contact timeline** – Bottom-left panel shows each contact’s window; green = link up at current sim time.
- **Telemetry panel** – Right side shows per-node HDTN-style stats: Ingress count, Egress sent, Storage used/cap, Delivered, Dropped.
- **Packet physics** – Packets move as physics bodies (CharacterBody2D) along links at configurable speed; delivery occurs when the body reaches the destination node. Toggle with `use_physics_packets` on the sim controller.
- **UI** – Sim time, Pause/Resume, speed (1x, 2x, 10x), global Storage / In flight / Delivered.

Green links = contact window open; gray = closed. Per-node stats: S (storage), E (egress queue), F (in flight), D (delivered).

## Project structure

- `project.godot` – Project settings; main scene is the HDTN sim
- `scenes/simulation/hdtn_sim.tscn` – HDTN simulation scene
- `scenes/simulation/dtn_node.tscn` – Single DTN node (visual + logic)
- `scenes/simulation/bundle_visual.tscn` – Bundle visual (for future use)
- `scripts/simulation/sim_controller.gd` – Sim time, contact plan, nodes, links, bundle spawn
- `scripts/simulation/router.gd` – Contact plan and link state
- `scripts/simulation/dtn_node.gd` – Ingress / Storage / Egress logic
- `scripts/simulation/bundle.gd` – Bundle data type
- `scripts/simulation/packet_body.gd` – Physics-driven packet (CharacterBody2D) for link traversal
- `scenes/simulation/packet_body.tscn` – Packet body scene
- `data/contact_plan.json` – NASA-style contact plan (source, dest, start/end time, rate, optional storageCapacityBytes)
- `icon.svg` – Project icon
