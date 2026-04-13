# Layer 1 Encounter Templates

Date: 2026-04-13

Runtime source of truth: `res://dungeon/game/encounters/layer_1_encounter_registry.gd`

Layer 1 combat rooms use generic spawn markers. Rooms do not name a specific encounter; the authoritative dungeon runtime chooses one template from the Layer 1 pool and places its composition into the room's available markers/volumes.

## Selection Rules

- Draw from the Layer 1 shuffled bag during room generation.
- Do not repeat a template within a run until the valid pool is exhausted.
- Use room tags such as `open`, `corridor`, `chokepoint`, `small`, `medium`, and `large` only for compatibility/fallback filtering.
- If room filtering is too narrow, fall back to broader unused Layer 1 templates before allowing repeats.
- Existing authored `enemy_spawn` markers are generic placement hints; template composition decides enemy types.

## Templates

| ID | Display Name | Composition | Tags |
| --- | --- | --- | --- |
| `flow_basics` | Flow Basics | 5 Scramblers | `open`, `small`, `low_intensity`, `flow` |
| `surge_basics` | Surge Basics | 6-8 Fizzlers | `open`, `medium`, `surge` |
| `edge_basics` | Edge Basics | 4 Skewers | `corridor`, `small`, `low_intensity`, `edge` |
| `volley_basics` | Volley Basics | 4 `spitter_flow` | `open`, `medium`, `range` |
| `phase_basics` | Phase Basics | 2-3 Lurkers | `open`, `small`, `phase`, `low_intensity` |
| `mass_basics` | Mass Basics | 2 Stumblers | `corridor`, `small`, `mass`, `low_intensity` |
| `echo_basics` | Echo Basics | 1 Splitter, 2 Scramblers | `open`, `small`, `echo` |
| `movement_projectiles` | Movement + Projectiles | 3 Scramblers, 2 `spitter_flow` | `open`, `medium`, `flow`, `range` |
| `movement_precision` | Movement + Precision | 3 Scramblers, 2 Skewers | `corridor`, `medium`, `flow`, `edge` |
| `aoe_opportunity` | AoE Opportunity | 5 Fizzlers, 2 Scramblers | `open`, `medium`, `surge` |
| `sustain_pressure` | Sustain Pressure | 1 Splitter, 3 Scramblers | `open`, `medium`, `echo` |
| `phase_distraction` | Phase Distraction | 2 Lurkers, 2 Scramblers | `open`, `medium`, `phase` |
| `zone_awareness` | Zone Awareness | 3 `spitter_mass`, 1 Stumbler | `open`, `medium`, `mass`, `range` |
| `first_dash_threat` | First Dash Threat | 1 Dasher, 3 Scramblers | `open`, `medium`, `flow` |
| `first_flank_puzzle` | First Flank Puzzle | 1 Shieldwall, 2 `spitter_flow` | `corridor`, `medium`, `mass`, `range` |
| `first_precision_punish` | First Precision Punish | 1 Glaiver, 2 Scramblers | `corridor`, `medium`, `edge` |
| `first_timer_threat` | First Timer Threat | 1 Burster, 2 Scramblers | `open`, `medium`, `surge` |
| `first_control_loss` | First Control Loss | 1 Leecher, 2 Scramblers | `open`, `medium`, `phase` |
| `first_spread_threat` | First Spread Threat | 1 `volley_edge`, 2 Scramblers | `open`, `medium`, `range`, `edge` |
| `flank_under_pressure` | Flank Under Pressure | 1 Shieldwall, 2 Scramblers, 1 `spitter_flow` | `corridor`, `large`, `mass`, `flow` |
| `dash_zone` | Dash + Zone | 1 Dasher, 2 `spitter_mass`, 1 Scrambler | `open`, `large`, `flow`, `mass`, `range` |
| `precision_range` | Precision + Range | 1 Glaiver, 2 `spitter_flow`, 1 Scrambler | `open`, `large`, `edge`, `range` |
| `splitter_protected` | Splitter Protected | 1 Splitter, 1 Shieldwall, 2 Scramblers | `corridor`, `large`, `echo`, `mass` |
| `phase_pressure` | Phase + Pressure | 2 Lurkers, 2 Scramblers, 1 `spitter_flow` | `open`, `large`, `phase`, `range` |
| `burster_chaos` | Burster Chaos | 1 Burster, 3 Scramblers | `open`, `medium`, `surge` |
| `movement_lock_test` | Movement Lock Test | 1 Shieldwall, 1 Glaiver, 2 Scramblers | `corridor`, `large`, `mass`, `edge` |
| `multi_timing_problem` | Multi-Timing Problem | 1 Dasher, 2 `spitter_flow`, 2 Scramblers | `open`, `large`, `flow`, `range` |
| `panic_check` | Panic Check | 1 Leecher, 1 Skewer, 2 Scramblers | `corridor`, `large`, `phase`, `edge` |
| `zone_pressure_stack` | Zone + Pressure Stack | 2 `spitter_mass`, 2 Scramblers, 1 Stumbler | `open`, `large`, `mass`, `range` |
| `layer_1_final_exam` | Layer 1 Final Exam | 1 from `{Shieldwall, Dasher}`, 1 from `{Glaiver, volley_edge}`, 2 Scramblers | `open`, `large`, `high_intensity` |

