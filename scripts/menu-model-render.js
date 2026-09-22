#!/usr/bin/env node
// Headless render of the Omarchy menu: what the shell would actually show for a
// panel, without screenshots. It drives the shell's own model code
// (shell/plugins/menu/MenuModel.js is plain JS and exports everything), so the
// answer comes from the same parse -> merge -> guard -> isVisible path the menu
// itself runs:
//
//   1. parseMenuJsonc()   reads default/omarchy/omarchy-menu.jsonc and, unless
//                         --default-only, ~/.config/omarchy/extensions/omarchy-menu.jsonc
//   2. mergeMenuSources() applies the user layer over the default one (per-field)
//   3. guardScript()      builds the one bash script holding every when:/checked:/
//                         disabled: expression, which we run to get real answers
//   4. isVisible()/labelFor()/displayRow()  turn that into rows
//
// Usage:
//   node scripts/menu-model-render.js [parent-id] [--default-only]
//
//   parent-id       panel to render, e.g. update, update.password, root (default)
//   --default-only  ignore the user override layer, i.e. "what upstream ships"
//                   (run both ways to prove an override is what changed a row)
//
// Replaces the grim + tesseract dance: submenu panels are small and land in
// unpredictable places, and OCR happily reads the terminal behind them as menu
// content.
const fs = require('fs')
const os = require('os')
const path = require('path')
const cp = require('child_process')

const home = os.homedir()
const modelPath = path.join(home, '.local/share/omarchy/shell/plugins/menu/MenuModel.js')
const defaultPath = path.join(home, '.local/share/omarchy/default/omarchy/omarchy-menu.jsonc')
const userPath = path.join(home, '.config/omarchy/extensions/omarchy-menu.jsonc')

if (!fs.existsSync(modelPath)) {
  console.error(`menu-model-render: no menu model at ${modelPath} (is omarchy-shell installed?)`)
  process.exit(2)
}

const M = require(modelPath)
const read = p => fs.readFileSync(p, 'utf8')
const parent = process.argv.slice(2).find(a => !a.startsWith('--')) || 'root'
const defaultOnly = process.argv.includes('--default-only')

const defaults = M.parseMenuJsonc(read(defaultPath))
const user = defaultOnly || !fs.existsSync(userPath) ? [] : M.parseMenuJsonc(read(userPath))

const merged = M.mergeMenuSources(defaults, user)
const items = merged.items
const itemOrder = merged.itemOrder

// The shell evaluates every guard in one bash batch; reuse that script verbatim
// rather than reimplementing `when` semantics here.
const whenResults = {}
const checkedResults = {}
const disabledResults = {}
const script = M.guardScript(items)
if (script) {
  const out = cp.execFileSync('bash', ['-c', script], { encoding: 'utf8', env: process.env })
  for (const line of out.split('\n')) {
    const [id, tag, value] = line.split(':')
    if (!id || (tag !== 'w' && tag !== 'c' && tag !== 'd')) continue
    const bucket = tag === 'w' ? whenResults : tag === 'c' ? checkedResults : disabledResults
    bucket[id] = value === '1'
  }
}

const isShown = entry => M.isVisible(items, itemOrder, whenResults, entry, 0)

// childCount() counts every declared child, hidden ones included; a panel is
// only as long as its visible children, so count those.
const visibleChildCount = id => {
  let n = 0
  for (const cid of itemOrder) {
    const child = M.item(items, cid)
    if (child && child.parent === id && isShown(child)) n++
  }
  return n
}

const rows = []
for (const id of itemOrder) {
  const entry = M.item(items, id)
  if (!entry || entry.parent !== parent) continue
  if (!isShown(entry)) continue
  rows.push({
    id: id,
    label: M.labelFor(entry, checkedResults, disabledResults),
    kind: entry.kind,
    icon: entry.icon,
    iconFont: entry.iconFont,
    target: entry.target || entry.action || '',
    children: visibleChildCount(entry.kind === 'link' ? entry.target : entry.id),
    disabled: M.isDisabled(disabledResults, entry)
  })
}

console.log(`parent=${parent}${defaultOnly ? '  [default only: user override ignored]' : ''}  rows=${rows.length}`)
for (const r of rows) {
  console.log(
    '  ' + r.label.padEnd(22) +
    ' id=' + r.id.padEnd(28) +
    ' ' + r.kind + (r.disabled ? ' [disabled]' : '') + (r.children ? ' +' + r.children : '') +
    '  icon="' + r.icon + '" iconFont="' + r.iconFont + '"  ' + r.target
  )
}
