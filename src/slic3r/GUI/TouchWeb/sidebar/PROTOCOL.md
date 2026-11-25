# Touch sidebar bridge protocol, version 1.0

Native is the source of truth. The web UI never assumes a command succeeded: a command shows a busy state until native sends `ack` or `error`, and displayed values change only when a `snapshot` or `patch` arrives. A mock bridge (`src/lib/mock.ts`) is created only when neither `window.chrome.webview` nor `window.webkit.messageHandlers.wx` exists.

## Transport (same as DeviceWeb/DeviceWebBridge.cpp)
- Web to native: `JSON.stringify({head, body})` through `chrome.webview.postMessage` (WebView2) or `webkit.messageHandlers.wx.postMessage` (WKWebView), fallback `app://` navigation. Native parses in `DeviceWebBridge::DispatchRawJson` (DeviceWebBridge.cpp:132), `head.version` checked by `ValidateHeader` against `DEVICE_WEB_BRIDGE_VERSION` ("1.0", DeviceWebBridge.hpp:27).
- Native to web: `window.__cppPush(pkt)` (injected at DeviceWebBridge.cpp:55) dispatches `CustomEvent('cpp:' + pkt.event)`. This page listens on `cpp:touch_sidebar`, so native must add `"event":"touch_sidebar"` to the packet (the DeviceWeb `SendMsg` template, DeviceWebBridge.hpp:~55-65, does not set it itself; confirm when wiring). The page also accepts a JSON string.
- Envelope: `{"head":{"version":"1.0","type":"request|response|report","seq":N,"ts":ms},"body":{"module":"touch_sidebar","action":"...","payload":{...}}}`. Web sends `type:"request"`, native sends `type:"report"`. Messages with another version or module are dropped (web logs a warning; native should log and ignore).

## Web to native (`body.action`)
| action | payload | meaning |
|---|---|---|
| `init` | `{protocol, lang}` | page loaded; native replies with `init` |
| `resync` | `{have}` | patch base mismatch; native replies with `snapshot` |
| `layout` | `{open:boolean, panel:string\|null, width:int}` | rail/panel open or closed; `width` is CSS px of the whole sidebar: 60 closed, 360 open (60 rail + 300 panel). Native resizes the webview (multiply by DPI scale) |
| `command` | `{id, cmd, args}` | `id` is a unique request id (`c1`, `c2`...); native must answer with `ack` or `error` carrying the same id |

## Native to web (`body.action`)
- `init` `{protocol:"1.0", state, theme:"dark"|"light", lang:"en"|"vi"|...}`
- `snapshot` `{state}`: full state, replaces everything. Older revisions than the current one are ignored.
- `patch` `{base, revision, ops:[{op:"set",path:[...],value}|{op:"remove",path:[...]}]}`: applied only if `base` equals the current revision; otherwise (or on a bad path) web sends `resync`.
- `ack` `{id, revision?}`; `error` `{id?, code, message}` (id omitted for unsolicited errors). Web times out a command after 15 s and shows an error.
- `theme` `{theme, lang?}`

### State (`SidebarState`, see `src/lib/protocol.ts`)
`revision`, `printer{presets,preset,nozzles,nozzle,plateTypes,plate}`, `filament{items[{id,color,type,preset}],presets,max}`, `quality{presets,preset,values{<option key>:value}}`, `objects[tree of {id,kind:plate|object|part,name,visible,selected,children}]`, `slice{status:idle|slicing|ready|error,progress 0-100,message,canPrint}`. Native should bump `revision` on every change.

## Commands and likely native targets
Line numbers verified by grep on 2026-11-25 in the working tree; Plater.cpp is being edited concurrently so expect drift of a few lines.

| cmd (args) | most likely native call |
|---|---|
| `select_printer_preset {id}` | `Tab::select_preset` (Tab.cpp:7132) on the printer tab; `PlaterPresetComboBox::OnSelect` (PresetComboBoxes.cpp:1500) is the existing UI path |
| `select_nozzle {diameter}` | `Sidebar::priv::switch_dual_variant` (Plater.cpp:3281) for dual-nozzle; single nozzle goes through the printer preset variant (`nozzle_diameter`) |
| `select_plate_type {id}` | `Sidebar::set_bed_type` (Plater.cpp:6524) / `Sidebar::on_bed_type_change` (Plater.cpp:7474); option key `curr_bed_type` (PrintConfig.cpp:2089) |
| `filament_add` | `Sidebar::add_filament` (Plater.cpp:7005) |
| `filament_remove {index}` | `Sidebar::delete_filament` (Plater.cpp:7178) |
| `filament_edit {index}` | `Sidebar::edit_filament` (Plater.cpp:7274) |
| `filament_set_preset {index,id}` | `PresetBundle::set_filament_preset` (PresetBundle.cpp:8191) then refresh combos |
| `filament_set_color {index,color}` | `PlaterPresetComboBox::change_extruder_color` (PresetComboBoxes.cpp:1612) |
| `select_process_preset {id}` | `Tab::select_preset` (Tab.cpp:7132) on the process tab |
| `set_option {key,value}` | set via the process Tab config then `Tab::on_value_change` (Tab.cpp:2117) to run dependency updates and mark dirty |
| `open_advanced {tab}` | `MainFrame::select_tab` (MainFrame.cpp:4517) |
| `object_select {id}` | `ObjectList::select_item(const ObjectVolumeID&)` (GUI_ObjectList.cpp:5779) |
| `object_set_visible {id,visible}` | `ObjectList::toggle_printable_state` (GUI_ObjectList.cpp:7397) / `update_printable_state` (7386); closest existing per-object toggle |
| `object_delete {id}` | `Plater::remove` (Plater.cpp:27461) or `ObjectList::remove` (GUI_ObjectList.cpp:5029) |
| `object_action {id,action}` | `arrange` -> `Plater::arrange` (Plater.cpp:30780); `menu` -> open the native object context menu |
| `slice` | `Plater::reslice` (Plater.cpp:28960); event path `Plater::priv::on_action_slice_plate` (Plater.cpp:17983) |
| `print` | `Plater::priv::on_action_print_plate` (Plater.cpp:20536) |
| `export` | `Plater::export_gcode` (Plater.cpp:27847) / `Plater::priv::on_action_export_gcode` (Plater.cpp:20724) |
| `cancel` | `BackgroundSlicingProcess::stop` (BackgroundSlicingProcess.cpp:577) |

Progress source for `slice.progress`: `Plater::priv::on_slicing_update` (Plater.cpp:17363) and `on_slicing_completed` (Plater.cpp:17449). Quality option keys used (PrintConfig.cpp): `layer_height` 1792, `wall_loops` 5607, `top_shell_layers` 7105, `bottom_shell_layers` 2156, `sparse_infill_density` 3961, `sparse_infill_pattern` 3979, `enable_support` 6532, `brim_type` 2499, `brim_width` 2489. Values: percent as number, enums as the config string (for example `grid`, `auto_brim`).

## Gaps
No native handler exists yet. Object ids (`plate:N`, `obj:N`, `vol:N:M`) are a proposal. Nozzle selection for single-nozzle printers has no verified single function.
