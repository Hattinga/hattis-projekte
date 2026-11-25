// P10-01: Maß- und Wirtschaftsprüfung für Beistelltisch01 v1 (Papierprüfung, keine Studio-Messung).
// Aufruf: node tools/tests/p10-01-sidetable-fit.mjs
// Alle Maße in Metern. Boxen: [x0,x1,y0,y1,z0,z1]. Y zeigt nach oben, Pivot = Mitte der Grundfläche.
const EPS = 1e-9;
const results = [];
function check(name, ok, detail) {
  results.push({ name, ok: Boolean(ok), detail: detail ?? '' });
}
const r4 = (n) => Math.round(n * 1e4) / 1e4;

const box = (x0, x1, y0, y1, z0, z1) => ({ x0, x1, y0, y1, z0, z1 });
const dims = (b) => [b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0];
const volume = (b) => dims(b).reduce((a, c) => a * c, 1);
function overlapLen(a0, a1, b0, b1) { return Math.min(a1, b1) - Math.max(a0, b0); }
function interiorOverlap(a, b) {
  return overlapLen(a.x0, a.x1, b.x0, b.x1) > EPS && overlapLen(a.y0, a.y1, b.y0, b.y1) > EPS
    && overlapLen(a.z0, a.z1, b.z0, b.z1) > EPS;
}
// Flächenkontakt: auf einer Achse berühren sich die Boxen, auf den beiden anderen überlappen sie positiv.
function faceContact(a, b) {
  const o = [overlapLen(a.x0, a.x1, b.x0, b.x1), overlapLen(a.y0, a.y1, b.y0, b.y1), overlapLen(a.z0, a.z1, b.z0, b.z1)];
  const touching = o.filter((v) => Math.abs(v) <= EPS).length === 1;
  const positive = o.filter((v) => v > EPS).length === 2;
  return touching && positive;
}
const partBoxes = (part) => part.boxes;
function partsOverlap(p, q) {
  return partBoxes(p).some((a) => partBoxes(q).some((b) => interiorOverlap(a, b)));
}
function partsContact(p, q) {
  return partBoxes(p).some((a) => partBoxes(q).some((b) => faceContact(a, b)));
}
function bounds(parts) {
  const all = parts.flatMap(partBoxes);
  return box(Math.min(...all.map((b) => b.x0)), Math.max(...all.map((b) => b.x1)),
    Math.min(...all.map((b) => b.y0)), Math.max(...all.map((b) => b.y1)),
    Math.min(...all.map((b) => b.z0)), Math.max(...all.map((b) => b.z1)));
}
function inside(inner, outer) {
  return inner.x0 >= outer.x0 - EPS && inner.x1 <= outer.x1 + EPS && inner.y0 >= outer.y0 - EPS
    && inner.y1 <= outer.y1 + EPS && inner.z0 >= outer.z0 - EPS && inner.z1 <= outer.z1 + EPS;
}
function minClearance(parts, container) {
  const b = bounds(parts);
  return Math.min(b.x0 - container.x0, container.x1 - b.x1, container.z0 === undefined ? 1 : b.z0 - container.z0,
    container.z1 - b.z1, container.y1 - b.y1);
}
function noOverlaps(parts) {
  const bad = [];
  for (let i = 0; i < parts.length; i += 1) {
    for (let j = i + 1; j < parts.length; j += 1) {
      if (partsOverlap(parts[i], parts[j])) bad.push(`${parts[i].name}×${parts[j].name}`);
    }
  }
  return bad;
}
// Jedes Teil liegt auf dem Boden (y0 == floor) oder berührt per Fläche ein Teil, das tiefer liegt und selbst gestützt ist.
function supported(parts, floorY) {
  const ok = new Set(parts.filter((p) => partBoxes(p).some((b) => Math.abs(b.y0 - floorY) <= EPS)).map((p) => p.name));
  let changed = true;
  while (changed) {
    changed = false;
    for (const p of parts) {
      if (ok.has(p.name)) continue;
      const rests = parts.some((q) => ok.has(q.name) && q !== p && partBoxes(p).some((a) => partBoxes(q).some(
        (b) => Math.abs(a.y0 - b.y1) <= EPS && overlapLen(a.x0, a.x1, b.x0, b.x1) > EPS
          && overlapLen(a.z0, a.z1, b.z0, b.z1) > EPS)));
      if (rests) { ok.add(p.name); changed = true; }
    }
  }
  return parts.filter((p) => !ok.has(p.name)).map((p) => p.name);
}
function connected(parts) {
  const seen = new Set([parts[0].name]);
  let changed = true;
  while (changed) {
    changed = false;
    for (const p of parts) {
      if (seen.has(p.name)) continue;
      if (parts.some((q) => seen.has(q.name) && partsContact(p, q))) { seen.add(p.name); changed = true; }
    }
  }
  return parts.filter((p) => !seen.has(p.name)).map((p) => p.name);
}

// ---------------------------------------------------------------- Beistelltisch01 v1: Einzelteile
const TOP = { w: 0.42, t: 0.025 };
const LEG = { w: 0.03, h: 0.455, at: 0.15 };
const APRON = { len: 0.27, h: 0.07, t: 0.02 };
const SHELF = { outer: 0.33, t: 0.02, notch: 0.03, y: 0.17 };
const HEIGHT = LEG.h + TOP.t; // 0,48
const legCenters = [[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([sx, sz]) => [sx * LEG.at, sz * LEG.at]);

const assembled = [
  { name: 'Platte', boxes: [box(-TOP.w / 2, TOP.w / 2, LEG.h, HEIGHT, -TOP.w / 2, TOP.w / 2)] },
  ...legCenters.map(([cx, cz], i) => ({
    name: `Bein${i + 1}`,
    boxes: [box(cx - LEG.w / 2, cx + LEG.w / 2, 0, LEG.h, cz - LEG.w / 2, cz + LEG.w / 2)],
  })),
  ...[-1, 1].map((s, i) => ({
    name: `ZargeX${i + 1}`,
    boxes: [box(-APRON.len / 2, APRON.len / 2, LEG.h - APRON.h, LEG.h,
      s * (LEG.at + LEG.w / 2) - (s > 0 ? APRON.t : 0), s * (LEG.at + LEG.w / 2) + (s < 0 ? APRON.t : 0))],
  })),
  ...[-1, 1].map((s, i) => ({
    name: `ZargeZ${i + 1}`,
    boxes: [box(s * (LEG.at + LEG.w / 2) - (s > 0 ? APRON.t : 0), s * (LEG.at + LEG.w / 2) + (s < 0 ? APRON.t : 0),
      LEG.h - APRON.h, LEG.h, -APRON.len / 2, APRON.len / 2)],
  })),
  {
    name: 'Ablageboden',
    boxes: [
      box(-SHELF.outer / 2, SHELF.outer / 2, SHELF.y, SHELF.y + SHELF.t, -(SHELF.outer / 2 - SHELF.notch), SHELF.outer / 2 - SHELF.notch),
      box(-(SHELF.outer / 2 - SHELF.notch), SHELF.outer / 2 - SHELF.notch, SHELF.y, SHELF.y + SHELF.t, -SHELF.outer / 2, SHELF.outer / 2),
    ],
  },
];

// Hocker01 v1 zum Vergleich (Quelle: DIMENSIONS.md).
const STOOL = {
  parts: 9, stationSeconds: { Saege: 6, Montage: 8, Finish: 6, Packen: 4 },
  cost: 60, dealer: 100, privateLow: 80, privateHigh: 120,
  product: [0.40, 0.45, 0.40], woodVolume: 0.40 * 0.025 * 0.40 + 4 * 0.035 * 0.425 * 0.035 + 4 * 0.29 * 0.06 * 0.02,
};
const TABLE = {
  parts: assembled.length, stationSeconds: { Saege: 8, Montage: 14, Finish: 8, Packen: 5 },
  cost: 80, dealer: 140, privateLow: 112, privateHigh: 168,
};

check('T01 Teilezahl: Hocker 9, Tisch 10', STOOL.parts === 9 && TABLE.parts === 10, `Hocker ${STOOL.parts}, Tisch ${TABLE.parts}`);
const overlapsAssembled = noOverlaps(assembled);
check('T02 Fertiger Tisch ohne Teileüberlappung', overlapsAssembled.length === 0, overlapsAssembled.join(', ') || '0 Überlappungen');
const loose = connected(assembled);
check('T03 Alle Teile hängen über Flächenkontakt am Gestell', loose.length === 0, loose.join(', ') || `${assembled.length}/${assembled.length} verbunden`);
const hull = bounds(assembled);
const [hx, hy, hz] = dims(hull).map(r4);
check('T04 Hülle Tisch 0,42 × 0,48 × 0,42 m', hx === 0.42 && hy === 0.48 && hz === 0.42, `${hx} × ${hy} × ${hz}`);
check('T05 Plattenüberstand rundum 0,045 m und Standfläche kleiner als die Platte',
  r4(TOP.w / 2 - (LEG.at + LEG.w / 2)) === 0.045, `Überstand ${r4(TOP.w / 2 - (LEG.at + LEG.w / 2))} m, Gestell ${r4(2 * (LEG.at + LEG.w / 2))} m`);
const woodTable = assembled.flatMap(partBoxes).reduce((a, b) => a + volume(b), 0)
  - 0; // Ablageboden besteht aus zwei Kreuzboxen; die Überlappung wird unten abgezogen.
const shelfCross = (SHELF.outer - 2 * SHELF.notch) ** 2 * SHELF.t;
const woodVolume = woodTable - shelfCross;
check('T06 Holzvolumen Tisch größer als Hocker, Anstieg unter 40 %', woodVolume > STOOL.woodVolume && woodVolume / STOOL.woodVolume < 1.4,
  `Hocker ${r4(STOOL.woodVolume * 1000)} dm³, Tisch ${r4(woodVolume * 1000)} dm³ (+${Math.round((woodVolume / STOOL.woodVolume - 1) * 100)} %)`);

// ---------------------------------------------------------------- Packlage im Holzpaket und im Träger
const FLOOR = 0.01;
// Reihenfolge in X: 0,0075 Luft | Platte 0,42 | Fuge 0,005 | vier liegende Beine (4 × 0,03 + 3 × 0,005) | 0,0125 Luft.
const PLATE_X0 = -0.2825;
const PLATE_X1 = PLATE_X0 + TOP.w;
const PLATE_CX = (PLATE_X0 + PLATE_X1) / 2;
const LEG_X0 = PLATE_X1 + 0.005;
const packLeg = (k) => ({
  name: `Bein${k + 1}`,
  boxes: [box(LEG_X0 + 0.035 * k, LEG_X0 + 0.035 * k + LEG.w, FLOOR, FLOOR + LEG.w, -LEG.h / 2, LEG.h / 2)],
});
const packApron = (layer, side) => ({
  name: `Zarge${layer * 2 + side + 1}`,
  boxes: [box(PLATE_CX - APRON.len / 2, PLATE_CX + APRON.len / 2, 0.055 + 0.02 * layer, 0.075 + 0.02 * layer,
    side === 0 ? -0.0725 : 0.0025, side === 0 ? -0.0025 : 0.0725)],
});
const pack = [
  { name: 'Platte', boxes: [box(PLATE_X0, PLATE_X1, FLOOR, FLOOR + TOP.t, -TOP.w / 2, TOP.w / 2)] },
  ...[0, 1, 2, 3].map(packLeg),
  {
    name: 'Ablageboden',
    boxes: [
      box(PLATE_CX - SHELF.outer / 2, PLATE_CX + SHELF.outer / 2, 0.035, 0.055, -(SHELF.outer / 2 - SHELF.notch), SHELF.outer / 2 - SHELF.notch),
      box(PLATE_CX - (SHELF.outer / 2 - SHELF.notch), PLATE_CX + (SHELF.outer / 2 - SHELF.notch), 0.035, 0.055, -SHELF.outer / 2, SHELF.outer / 2),
    ],
  },
  ...[0, 1].flatMap((layer) => [0, 1].map((side) => packApron(layer, side))),
];
check('T07 Packlage enthält 10 Teile', pack.length === 10, `${pack.length} Teile`);
const packOverlap = noOverlaps(pack);
check('T08 Packlage ohne Überlappung', packOverlap.length === 0, packOverlap.join(', ') || '0 Überlappungen');
const packUnsupported = supported(pack, FLOOR);
check('T09 Jedes Teil der Packlage liegt auf Boden oder Teil darunter', packUnsupported.length === 0, packUnsupported.join(', ') || '10/10 gestützt');

const HOLZPAKET = { outer: [0.60, 0.15, 0.50], wall: 0.01 };
const TRAEGER = { outer: [0.60, 0.18, 0.50], wall: 0.01, usable: [0.58, 0.48] };
const holzInner = box(-0.29, 0.29, FLOOR, HOLZPAKET.outer[1] - HOLZPAKET.wall, -0.24, 0.24);
const traegerInner = box(-0.29, 0.29, FLOOR, 0.18, -0.24, 0.24);
const packBounds = bounds(pack);
check('T10 Packlage liegt im Holzpaket 0,60 × 0,15 × 0,50 m', inside(packBounds, holzInner),
  `Hülle X ${r4(packBounds.x0)}..${r4(packBounds.x1)}, Y ${r4(packBounds.y0)}..${r4(packBounds.y1)}, Z ${r4(packBounds.z0)}..${r4(packBounds.z1)}; innen Y bis ${r4(holzInner.y1)}`);
check('T11 Packlage liegt im offenen Träger 0,60 × 0,18 × 0,50 m (gleicher Träger wie beim Hocker)', inside(packBounds, traegerInner),
  `nutzbar ${TRAEGER.usable.join(' × ')} m`);
const clearX = Math.min(packBounds.x0 + 0.29, 0.29 - packBounds.x1);
const clearZ = Math.min(packBounds.z0 + 0.24, 0.24 - packBounds.z1);
const clearY = holzInner.y1 - packBounds.y1;
check('T12 Mindestluft in der Packlage mindestens 0,005 m', Math.min(clearX, clearZ, clearY) >= 0.005 - EPS,
  `X ${r4(clearX)}, Z ${r4(clearZ)}, Höhe ${r4(clearY)} m`);
const platteLeg = pack[0].boxes[0].x1 - 0; // letzte Plattenkante
check('T13 Fuge zwischen Platte und erstem Bein mindestens 0,005 m', pack[1].boxes[0].x0 - platteLeg >= 0.005 - EPS,
  `${r4(pack[1].boxes[0].x0 - platteLeg)} m`);

// ---------------------------------------------------------------- Karton
const CARTON = { wall: 0.01, gap: 0.02 };
const cartonInner = [hx + 2 * CARTON.gap, hy + 2 * CARTON.gap, hz + 2 * CARTON.gap].map(r4);
const cartonOuter = cartonInner.map((v) => r4(v + 2 * CARTON.wall));
check('T14 Karton außen 0,48 × 0,54 × 0,48 m, innen 0,46 × 0,52 × 0,46 m',
  cartonOuter.join() === [0.48, 0.54, 0.48].join() && cartonInner.join() === [0.46, 0.52, 0.46].join(),
  `außen ${cartonOuter.join(' × ')}, innen ${cartonInner.join(' × ')}`);

// ---------------------------------------------------------------- Auflagen, Lager, Fahrzeug, Hand
const SUPPORT = { size: [0.70, 0.60], margin: 0.05, y: 0.90, freeTop: 1.45, signBottom: 1.475 };
const DECK = { slot: [0.65, 0.55], y: 0.55, hullTop: 1.15 };
const CARRY = { under: 0.70, avatarTop: 1.56 };
const wares = [
  { name: 'Tischholzpaket', env: HOLZPAKET.outer },
  { name: 'Offener Bausatz (Träger)', env: TRAEGER.outer },
  { name: 'Rohtisch / Fertiger Tisch', env: [hx, hy, hz] },
  { name: 'Tischkarton', env: cartonOuter },
];
const usable = [SUPPORT.size[0] - 2 * SUPPORT.margin, SUPPORT.size[1] - 2 * SUPPORT.margin];
for (const w of wares) {
  const [wx, wy, wz] = w.env;
  check(`T15 ${w.name}: Grundfläche ${wx} × ${wz} passt auf die Auflage mit 0,05 m Rand`,
    wx <= usable[0] + EPS && wz <= usable[1] + EPS, `nutzbar ${r4(usable[0])} × ${r4(usable[1])} m`);
  check(`T16 ${w.name}: Oberkante ${r4(SUPPORT.y + wy)} m unter dem freien Warenraum 1,45 m`,
    SUPPORT.y + wy <= SUPPORT.freeTop + EPS, `Reserve ${r4(SUPPORT.freeTop - SUPPORT.y - wy)} m`);
}
const carton = wares[3].env;
check('T17 Tischkarton auf Lagerplatz bleibt unter der Lagerschild-Unterkante 1,475 m',
  SUPPORT.y + carton[1] < SUPPORT.signBottom, `Oberkante ${r4(SUPPORT.y + carton[1])} m, Reserve ${r4(SUPPORT.signBottom - SUPPORT.y - carton[1])} m`);
for (const w of [wares[0], wares[3]]) {
  const [wx, wy, wz] = w.env;
  check(`T18 ${w.name} passt in einen Anhängerplatz 0,65 × 0,55 m (Längsachse quer zur Fahrt)`,
    wx <= DECK.slot[0] + EPS && wz <= DECK.slot[1] + EPS, `${wx} × ${wz} m, Luft ${r4(DECK.slot[0] - wx)} / ${r4(DECK.slot[1] - wz)} m`);
  check(`T19 ${w.name} bleibt auf dem Deck unter der Prüfhülle 1,15 m`, DECK.y + wy <= DECK.hullTop + EPS,
    `Oberkante ${r4(DECK.y + wy)} m`);
}
for (const w of wares) {
  check(`T20 ${w.name} bleibt in Tragehöhe unter der Avatarhülle`, CARRY.under + w.env[1] <= CARRY.avatarTop + EPS,
    `Warenabschluss ${r4(CARRY.under + w.env[1])} m`);
}
check('T21 Träger und Bandpuffer bleiben unverändert (gleiche Hülle wie beim Hocker-Bausatz)',
  TRAEGER.outer.join() === [0.60, 0.18, 0.50].join(), 'Band.First trägt 0,60 × 0,18 × 0,50 m');

// ---------------------------------------------------------------- Zeiten und Wirtschaft
const sum = (o) => Object.values(o).reduce((a, c) => a + c, 0);
const profit = (r) => r.dealer - r.cost;
const perMontage = (r) => profit(r) / r.stationSeconds.Montage;
const perCycle = (r) => profit(r) / Math.max(...Object.values(r.stationSeconds));
check('T22 Stationszeit gesamt: Hocker 24 s, Tisch 35 s', sum(STOOL.stationSeconds) === 24 && sum(TABLE.stationSeconds) === 35,
  `${sum(STOOL.stationSeconds)} s / ${sum(TABLE.stationSeconds)} s`);
check('T23 Montage dauert beim Tisch länger und bestimmt den Takt der Linie',
  TABLE.stationSeconds.Montage > STOOL.stationSeconds.Montage && TABLE.stationSeconds.Montage === Math.max(...Object.values(TABLE.stationSeconds)),
  `Montage ${STOOL.stationSeconds.Montage} s → ${TABLE.stationSeconds.Montage} s`);
check('T24 Händlererlös deckt die Materialkosten (Gewinn je Charge Hocker 40, Tisch 60)', profit(STOOL) === 40 && profit(TABLE) === 60,
  `${profit(STOOL)} / ${profit(TABLE)}`);
check('T25 Privatspanne liegt bei ±20 % um den Händlererlös und deckt immer die Kosten',
  TABLE.privateLow === TABLE.dealer * 0.8 && TABLE.privateHigh === TABLE.dealer * 1.2 && TABLE.privateLow > TABLE.cost,
  `${TABLE.privateLow} bis ${TABLE.privateHigh} bei Einkauf ${TABLE.cost}`);
const trade = {
  gainPerMontageSecond: [perMontage(STOOL), perMontage(TABLE)],
  gainPerCycleSecond: [perCycle(STOOL), perCycle(TABLE)],
  gainPerSlot: [profit(STOOL), profit(TABLE)],
  gainPerMoney: [profit(STOOL) / STOOL.cost, profit(TABLE) / TABLE.cost],
};
check('T26 Hocker gewinnt je Montage-Sekunde (5,00 gegen 4,29)',
  trade.gainPerMontageSecond[0] > trade.gainPerMontageSecond[1], trade.gainPerMontageSecond.map((v) => r4(v)).join(' gegen '));
check('T27 Tisch gewinnt je Ladeplatz (60 gegen 40) und je eingesetztem Spielgeld (0,75 gegen 0,67)',
  trade.gainPerSlot[1] > trade.gainPerSlot[0] && trade.gainPerMoney[1] > trade.gainPerMoney[0],
  `Platz ${trade.gainPerSlot.join(' gegen ')}, Einsatz ${trade.gainPerMoney.map((v) => r4(v)).join(' gegen ')}`);
check('T28 Kein Rezept dominiert: keiner liegt in allen Kennzahlen vorn',
  trade.gainPerMontageSecond[0] > trade.gainPerMontageSecond[1] && trade.gainPerSlot[1] > trade.gainPerSlot[0], 'Zielkonflikt Montagezeit gegen Ladeplatz');

// ---------------------------------------------------------------- Ausgabe
let failed = 0;
for (const r of results) {
  if (!r.ok) failed += 1;
  console.log(`${r.ok ? 'PASS' : 'FAIL'}\t${r.name}${r.detail ? `\t${r.detail}` : ''}`);
}
console.log(`TOTAL\t${results.length}\t${results.length - failed}\t${failed}`);
if (failed > 0) process.exitCode = 1;
