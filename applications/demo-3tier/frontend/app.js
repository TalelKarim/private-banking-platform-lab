const positions = document.getElementById('positions');
const errorBox = document.getElementById('error');
const total = document.getElementById('total');
const backendPod = document.getElementById('backend-pod');
const database = document.getElementById('database');

function money(value) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

async function loadPortfolio() {
  errorBox.hidden = true;
  positions.innerHTML = '<tr><td colspan="4">Loading…</td></tr>';
  try {
    const response = await fetch('/api/portfolio', { cache: 'no-store' });
    if (!response.ok) throw new Error(`backend returned HTTP ${response.status}`);
    const payload = await response.json();
    backendPod.textContent = payload.served_by;
    database.textContent = payload.database;
    total.textContent = `Total ${money(payload.total_market_value)}`;
    positions.innerHTML = payload.positions.map(item => `
      <tr>
        <td><strong>${item.symbol}</strong></td>
        <td>${item.quantity}</td>
        <td>${money(item.price)}</td>
        <td>${money(item.market_value)}</td>
      </tr>`).join('');
  } catch (error) {
    positions.innerHTML = '';
    errorBox.hidden = false;
    errorBox.textContent = `Request failed: ${error.message}`;
  }
}

document.getElementById('refresh').addEventListener('click', loadPortfolio);
loadPortfolio();
