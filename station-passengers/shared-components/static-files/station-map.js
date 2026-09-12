window.nopInit = function () {
/* Source lines are retained; no point markers or station total aggregation. */
const yearSelect = document.querySelector('#year');
const search = document.querySelector('#search');
const status = document.querySelector('#status');
const details = document.querySelector('#details');
const results = document.querySelector('#results');
for (let y = 2024; y >= 2011; y--) yearSelect.add(new Option(`${y}年度`, y));
if (!window.L) {
  status.textContent = '地図ライブラリを読み込めません。インターネット接続を確認して再読み込みしてください。';
} else {
  const map = L.map('map', {renderer:L.canvas({tolerance:8})}).setView([35.630,139.7785], 15);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom:19, attribution:'&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  }).addTo(map);
  L.control.scale({imperial:false}).addTo(map);
  let lines = null;
  let request = 0;
  const text = (tag, value, cls) => {
    const el = document.createElement(tag); el.textContent = value;
    if (cls) el.className = cls;
    return el;
  };
  function info(p, compact=false) {
    const box = document.createElement('div');
    box.append(text(compact ? 'strong' : 'h2', p.name), document.createElement('br'));
    box.append(text('span', `${p.operator} · ${p.line}`), document.createElement('br'));
    box.append(text('span', `${p.year}年度`, 'small'), document.createElement('br'));
    box.append(text('span', p.passengers === null ? p.status : p.passengers.toLocaleString('ja-JP'), compact ? 'tooltip-value' : 'value'));
    if (p.passengers !== null) box.append(text('span', ' 人／日', 'unit'));
    if (p.remarks) box.append(text('p', p.remarks, 'small'));
    return box;
  }
  function showResults() {
    results.replaceChildren();
    const term = search.value.trim();
    if (!term || !lines) return;
    const matches = lines.getLayers().filter(l => l.feature.properties.name.includes(term));
    for (const layer of matches.slice(0,20)) {
      const p = layer.feature.properties;
      const button = text('button', p.name);
      button.type = 'button';
      button.append(text('small', `${p.operator} · ${p.line}`));
      button.onclick = () => {
        map.fitBounds(layer.getBounds(), {maxZoom:16, padding:[90,90]});
        details.replaceChildren(info(p));
      };
      results.append(button);
    }
    if (!matches.length) results.append(text('p', 'この年度の該当駅はありません。'));
    if (matches.length > 20) results.append(text('small', '先頭20件を表示。駅名を絞り込んでください。'));
  }
  async function load() {
    const id = ++request;
    if (lines) {lines.remove(); lines = null;}
    results.replaceChildren(); details.replaceChildren(text('p','駅の線にカーソルを合わせてください。'));
    status.textContent = `${yearSelect.value}年度を読み込み中…`;
    try {
      const data = await apex.server.process('GET_STATIONS', {x01:yearSelect.value}, {dataType:'json'});
      if (id !== request) return;
      lines = L.geoJSON(data, {
        style: f => ({color:f.properties.passengers === null ? '#83928e' : '#187f73',weight:5,opacity:.9}),
        onEachFeature: (f, layer) => {
          layer.bindTooltip(() => info(f.properties,true), {sticky:true});
          layer.on('mouseover', () => {layer.setStyle({weight:8,color:'#e18b36'}); details.replaceChildren(info(f.properties));});
          layer.on('mouseout', () => lines.resetStyle(layer));
        }
      }).addTo(map);
      status.textContent = `${data.year}年度 · ${data.features.length.toLocaleString('ja-JP')}件の駅の線`;
      showResults();
    } catch(error) {
      if (id === request) status.textContent = 'データ取得に失敗しました。再読み込みしてください。';
    }
  }
  yearSelect.addEventListener('change',load);
  search.addEventListener('input',showResults);
  load();
}

};
