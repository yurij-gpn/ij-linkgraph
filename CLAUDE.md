# IT-JIM Link Graph — Claude Code Context

## What this is
A visual internal link management tool for it-jim.com.
Single HTML file (`index.html`). No build step. Open in browser directly.
Data is stored in `data.json` — user loads/saves it from the UI.

## Running it
Open `index.html` directly in a browser. Or:
```bash
python3 -m http.server 8080
# then open http://localhost:8080
```
No Node.js, no npm, no dependencies.

## File layout
```
index.html   ← entire app: HTML structure + <style> CSS + <script> JS (~1500 lines)
data.json    ← the IT-JIM graph data (loaded via UI, not auto-loaded)
CLAUDE.md    ← this file
```

## Where things are in index.html
The file has three major sections — search for these exact markers:

| Section | Search for |
|---------|-----------|
| CSS variables & global styles | `:root {` |
| HTML structure | `<div class="app">` |
| JavaScript (all logic) | `<script>` |

Within the JavaScript block, functions are grouped — search for these comments:
- `// CORE STATE` — the `state` object and `hasUnsaved`, `selectedNodeId`, etc.
- `// HELPERS` — `genId`, `esc`, `fullUrl`, `fmt`, `getNode`, etc.
- `// STATE MUTATIONS` — `addNode`, `updateNode`, `deleteNode`, `addLink`, etc.
- `// GRAPH GEOMETRY` — `nodeRadius`, `curvePath`, `edgeGeom`, `fitGraph`
- `// RENDER GRAPH` — main SVG rendering, edge and node drawing
- `// RIGHT PANEL` — `renderPanel()`, `renderLinkRow()`
- `// BACKLINKS TABLE VIEW` — `renderBLTable()`, `toggleBLGroup()`
- `// SIDEBAR RENDER` — `renderSidebar()`
- `// PAN / ZOOM / DRAG` — mouse event handlers
- `// NODE MODAL` — `openAddNodeModal`, `openEditNodeModal`, form wiring
- `// LINK MODAL` — same pattern
- `// BACKLINK MODAL` — same pattern
- `// CLUSTERS MODAL` — cluster CRUD
- `// IMPORT / EXPORT` — `loadJSON`, save button, `handleFile`

## Data model

```js
// Top-level state object (null until user loads JSON)
state = {
  clusters: [{ id, name, stroke, fill }],
  nodes: [{
    id,          // string, immutable, kebab-case
    label,       // display name
    url,         // path, e.g. "/blog/fiducial-markers-types/"
    cluster,     // cluster id
    source,      // "ahrefs" | "manual"
    status,      // "active" | "new" | "redirected" | "deprecated"
    redirectTo,  // string (only if redirected)
    ur, bl, rh,  // Ahrefs metrics
    dataDate,    // ISO date string
    x, y,        // SVG canvas position (0-720, 0-760)
    notes,
  }],
  links: [{
    id,
    source, target,   // node ids
    type,             // "contextual" | "nav" | "proposed"
    origin,           // "ahrefs" | "manual"
    anchors,          // string[]
    priority,         // "none"|"high"|"medium"|"low" (proposed only)
    status,           // "n/a"|"pending"|"implemented"
    implementedDate,
    rationale,
    implementationNotes,
    notes,
  }],
  backlinks: [{
    id,
    targetNodeId,  // node id of the page being linked TO
    sourceUrl,     // full URL of external page linking in
    vendorUrl,     // who arranged the link
    anchor,
    doFollow,      // "yes" | "no"
    price, currency,  // currency: USD|EUR|GBP|UAH
    acquiredDate, liveDate,
    notes,
  }]
}
```

## Key globals
- `state` — the graph data (null until loaded)
- `siteUrl` — prepended to node URLs for clickable links (default: `https://www.it-jim.com`)
- `selectedNodeId` — currently open right panel node
- `panelHistory` — array of `{id, label}` for back navigation
- `hasUnsaved` — boolean, triggers beforeunload warning
- `currentView` — `'graph'` | `'backlinks'`

## Graph rendering
- Canvas: 720×760 SVG logical units
- viewBox is panned/zoomed by modifying `vbX, vbY, vbW, vbH`
- Node radius scales with UR + backlink count (see `nodeRadius()`)
- Hub pages (home, services, industries) → `<rect>`. Others → `<circle>`
- Edges: quadratic bezier curves via `curvePath(source, target, offset)`
- Layer order (back to front): nav → ctx → impl → prop → ext → nodes

## SEO badges
- Orange halo: node has Ahrefs backlinks (bl > 0)
- Gold ring: node has external (paid) backlinks in our records
- Red dashed ring: orphan page (no inbound contextual links)
- ⚡ badge: stranded authority (has bl > 0 but no contextual outbound)
- ⚠ badge: data is stale (dataDate > 90 days ago)

## CSS design tokens (in :root)
```
--bg: #F7F5EF        warm off-white background
--ink: #14140F       near-black text
--muted: #6B6A65     secondary text
--rule: #D5D3C9      borders
--card: #FFFFFF      panel backgrounds
--accent: #C84B20    orange-red (errors, highlights)
--ctx: #4A42AA       indigo (contextual links)
--prop: #2E6010      dark green (proposed)
--impl: #145E30      darker green (implemented)
--nav: #BFBDB4       gray (nav links)
--ext: #8B5E00       gold-brown (external backlinks)
```

## Common tasks

**Add a field to nodes:**
1. Add `<input>` to the node modal HTML (search `modal-node`)
2. Read it in `mn-save` click handler
3. Display it in `renderPanel()` in the rp-stats or rp-section area
4. Optionally show in SVG node tooltip (`showNodeTT`)

**Add a new proposed link type or edge style:**
1. Add CSS color variable in `:root`
2. Add `<marker>` in SVG `<defs>`
3. Add filter checkbox in sidebar HTML
4. Handle in the edge rendering loop in `renderGraph()`

**Change the site base URL:**
Edit the `siteUrl` variable default, or use the Settings section in the sidebar.

**The renderAll() function** — call this after any state mutation. It calls:
`renderGraph()` + `renderPanel()` + `renderSidebar()`
(and `renderBLTable()` if currentView === 'backlinks')
