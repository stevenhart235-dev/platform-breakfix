const componentNames = ['Nodes', 'Pods', 'PVCs', 'Services', 'Endpoints', 'Cilium', 'Istio'];
let lastObservedAt = null;

function stateClass(status) {
  return `state-${String(status).toLowerCase().replace('_', '-')}`;
}

function applyContract(health) {
  document.getElementById('overall-status').textContent = health.Overall;
  document.getElementById('observed-at').textContent = `Observed: ${health.ObservedAt}`;
  lastObservedAt = health.ObservedAt;
  const banner = document.getElementById('availability');
  banner.textContent = '';
  banner.className = 'availability hidden';
  for (const name of componentNames) {
    const key = name.toLowerCase();
    const component = health.Components[name];
    const card = document.getElementById(`component-${key}`);
    card.className = `component ${stateClass(component.Status)}`;
    document.getElementById(`${key}-status`).textContent = component.Status;
    document.getElementById(`${key}-summary`).textContent = component.Summary;
    let version = card.querySelector('.version');
    if (component.Version) {
      if (!version) { version = document.createElement('span'); version.className = 'version'; card.appendChild(version); }
      version.textContent = `Version: ${component.Version}`;
    } else if (version) { version.remove(); }
  }
}

function showUnavailable() {
  document.getElementById('overall-status').textContent = 'UNKNOWN';
  document.getElementById('observed-at').textContent = lastObservedAt ? `Last observed (stale): ${lastObservedAt}` : 'Observed: Unavailable';
  const banner = document.getElementById('availability');
  banner.textContent = 'Current health is unavailable. Any retained observation is stale.';
  banner.className = 'availability';
  for (const name of componentNames) {
    const key = name.toLowerCase();
    document.getElementById(`component-${key}`).className = 'component state-unknown';
    document.getElementById(`${key}-status`).textContent = 'UNKNOWN';
    document.getElementById(`${key}-summary`).textContent = 'Current health unavailable.';
  }
}

async function refresh() {
  try {
    const response = await fetch('/api/health', { cache: 'no-store' });
    if (!response.ok) throw new Error('Health unavailable');
    applyContract(await response.json());
  } catch (_) { showUnavailable(); }
}

setInterval(refresh, 5000);
