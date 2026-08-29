// Client-side directory search.
//
// The snapshot is a static file, so filtering happens entirely in the browser.
// Nothing about what someone searched for reaches the server, and the data a
// visitor can see is exactly the file they can download and inspect.

const SNAPSHOT_URL = "/snapshots/directory.json"

export function mountDirectory() {
  const form = document.getElementById("directory-filters")
  const results = document.getElementById("directory-results")
  if (!form || !results) return

  const count = document.getElementById("directory-count")
  const sql = document.getElementById("directory-sql")

  fetch(SNAPSHOT_URL)
    .then((response) => (response.ok ? response.json() : Promise.reject(response.status)))
    .then((snapshot) => {
      populateOptions(form, snapshot.rows)
      const render = () => {
        const filters = readFilters(form)
        const matched = snapshot.rows.filter((row) => matches(row, filters))
        results.innerHTML = matched.slice(0, 200).map(card).join("")
        count.textContent = `${matched.length} 件 / 公開 ${snapshot.count} 件（k=${snapshot.k}、抑制 ${snapshot.suppressed} 件）`
        sql.textContent = toSql(filters)
      }
      form.addEventListener("input", render)
      render()
    })
    .catch(() => {
      count.textContent = "スナップショットを読み込めませんでした。mix nerd.snapshot を実行してください。"
    })
}

function populateOptions(form, rows) {
  fill(form.elements.area, "すべての地域", unique(rows.map((row) => row.area)))
  fill(form.elements.experience, "すべての経験", unique(rows.map((row) => row.experience_band)))
}

function fill(select, placeholder, values) {
  select.innerHTML =
    `<option value="">${placeholder}</option>` +
    values.map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`).join("")
}

function unique(values) {
  return [...new Set(values.filter(Boolean))].sort()
}

function readFilters(form) {
  return {
    area: form.elements.area.value,
    experience: form.elements.experience.value,
    skill: form.elements.skill.value.trim().toLowerCase(),
    remote: form.elements.remote.checked
  }
}

function matches(row, filters) {
  if (filters.area && row.area !== filters.area) return false
  if (filters.experience && row.experience_band !== filters.experience) return false
  if (filters.remote && !row.remote_ok) return false
  if (filters.skill) {
    const haystack = [...(row.skills || []), ...(row.languages || []), ...(row.tools || [])]
    if (!haystack.some((entry) => entry.toLowerCase().includes(filters.skill))) return false
  }
  return true
}

function card(row) {
  const tags = [...(row.languages || []), ...(row.skills || [])]
    .slice(0, 6)
    .map((tag) => `<span class="rounded bg-zinc-100 px-2 py-0.5 text-xs text-zinc-700">${escapeHtml(tag)}</span>`)
    .join("")

  return `
    <article class="rounded-lg border border-zinc-200 p-4">
      <h3 class="font-medium text-zinc-900">${escapeHtml(row.display_name || "")}</h3>
      <p class="mt-1 text-sm text-zinc-600">${escapeHtml(row.headline || "")}</p>
      <p class="mt-2 text-xs text-zinc-500">
        ${escapeHtml(row.area)} ・ ${escapeHtml(row.age_band)} ・ 経験 ${escapeHtml(row.experience_band)}
        ${row.remote_ok ? " ・ リモート可" : ""}
      </p>
      <div class="mt-3 flex flex-wrap gap-1">${tags}</div>
    </article>`
}

// The same predicate the filters express, written out so it can be read,
// argued with, and saved to a profile.
function toSql(filters) {
  const conditions = []
  if (filters.area) conditions.push(`area = '${filters.area.replace(/'/g, "''")}'`)
  if (filters.experience) conditions.push(`experience_band = '${filters.experience.replace(/'/g, "''")}'`)
  if (filters.remote) conditions.push("remote_ok = true")
  if (filters.skill) conditions.push(`'${filters.skill.replace(/'/g, "''")}' = ANY(skills)`)

  return conditions.length === 0
    ? "SELECT * FROM directory"
    : `SELECT * FROM directory\n   WHERE ${conditions.join("\n     AND ")}`
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (char) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]
  )
}
