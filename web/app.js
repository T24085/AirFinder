const DATA_URL = "./data/locations.json";
const STORAGE_KEY = "airfinder.pending-submissions";
const DEFAULT_CENTER = [41.8781, -87.6298];
const DEFAULT_ZOOM = 11;

const state = {
  locations: [],
  pending: loadPending(),
  activeSegment: "all",
  query: "",
  selectedId: null,
  viewMode: "results",
  map: null,
  markerLayer: null,
  userMarker: null,
  searchRadiusMeters: 24000,
  mapCenter: DEFAULT_CENTER
};

const els = {
  searchInput: document.getElementById("searchInput"),
  locateButton: document.getElementById("locateButton"),
  submitButton: document.getElementById("submitButton"),
  statsBar: document.getElementById("statsBar"),
  panelContent: document.getElementById("panelContent"),
  submissionTemplate: document.getElementById("submissionTemplate"),
  detailTemplate: document.getElementById("detailTemplate"),
  locationCardTemplate: document.getElementById("locationCardTemplate"),
  queueTemplate: document.getElementById("queueTemplate")
};

const currencyFormatter = new Intl.NumberFormat("en-US", {
  style: "unit",
  unit: "mile",
  maximumFractionDigits: 1
});

const dateFormatter = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "numeric",
  year: "numeric"
});

const fmt = {
  address(location) {
    return [location.addressLine1, location.city, location.state, location.postalCode]
      .filter(Boolean)
      .join(", ");
  },
  badge(location) {
    switch (location.pricingStatus) {
      case "free":
        return "Free";
      case "paid":
        return "$";
      default:
        return "Unknown";
    }
  },
  badgeClass(location) {
    switch (location.pricingStatus) {
      case "free":
        return "badge--free";
      case "paid":
        return "badge--paid";
      default:
        return "badge--pending";
    }
  },
  markerClass(location) {
    if (location.status === "pending") return "marker--pending";
    switch (location.pricingStatus) {
      case "free":
        return "marker--free";
      case "paid":
        return "marker--paid";
      default:
        return "marker--unknown";
    }
  },
  source(location) {
    if (location.status === "pending") return "Pending review";
    return location.source === "demo-seed" ? "Demo seed" : "Crowd-sourced";
  },
  date(value) {
    if (!value) return "Not verified";
    try {
      return dateFormatter.format(new Date(value));
    } catch {
      return "Not verified";
    }
  }
};

function loadPending() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function savePending(nextPending) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(nextPending));
}

function normalize(value) {
  return String(value ?? "")
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function matches(location, query) {
  const normalizedQuery = normalize(query);
  if (!normalizedQuery) return true;
  const haystack = [
    location.name,
    location.addressLine1,
    location.city,
    location.state,
    location.postalCode,
    location.notes,
    location.source
  ]
    .map(normalize)
    .join(" ");
  return haystack.includes(normalizedQuery);
}

function haversineMiles(a, b) {
  if (!a || !b) return null;
  const [lat1, lng1] = a;
  const [lat2, lng2] = b;
  const r = 3958.7613;
  const toRad = (value) => (value * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const la1 = toRad(lat1);
  const la2 = toRad(lat2);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(la1) * Math.cos(la2) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

function resolveLocations() {
  return [...state.locations, ...state.pending];
}

function filteredLocations() {
  const list = resolveLocations().filter((location) => {
    const segmentMatch =
      state.activeSegment === "all" ||
      location.status === state.activeSegment ||
      location.pricingStatus === state.activeSegment;
    return segmentMatch && matches(location, state.query);
  });

  return list
    .map((location) => ({
      ...location,
      distanceMiles: haversineMiles(
        state.userMarker ? [state.userMarker.getLatLng().lat, state.userMarker.getLatLng().lng] : state.mapCenter,
        [location.latitude, location.longitude]
      )
    }))
    .sort((a, b) => {
      if (a.distanceMiles != null && b.distanceMiles != null && Math.abs(a.distanceMiles - b.distanceMiles) > 0.05) {
        return a.distanceMiles - b.distanceMiles;
      }
      if (a.status === "pending" && b.status !== "pending") return -1;
      if (a.status !== "pending" && b.status === "pending") return 1;
      if (a.pricingStatus === "free" && b.pricingStatus !== "free") return -1;
      if (a.pricingStatus !== "free" && b.pricingStatus === "free") return 1;
      return a.name.localeCompare(b.name);
    });
}

function statsFor(list) {
  const total = list.length;
  const free = list.filter((item) => item.pricingStatus === "free").length;
  const paid = list.filter((item) => item.pricingStatus === "paid").length;
  const pending = list.filter((item) => item.status === "pending").length;

  return [
    { label: `${total} stops`, tone: "stat-pill" },
    { label: `${free} free`, tone: "stat-pill" },
    { label: `${paid} paid`, tone: "stat-pill" },
    { label: `${pending} pending`, tone: "stat-pill" }
  ];
}

function updateStats(list) {
  els.statsBar.innerHTML = "";
  for (const stat of statsFor(list)) {
    const pill = document.createElement("div");
    pill.className = stat.tone;
    pill.textContent = stat.label;
    els.statsBar.appendChild(pill);
  }
}

function iconHtml(location, selected = false) {
  return `
    <div class="marker ${fmt.markerClass(location)} ${selected ? "is-selected" : ""}">
      <div class="marker__badge">${escapeHtml(fmt.badge(location))}</div>
      <div class="marker__stem"></div>
    </div>
  `;
}

function markerIcon(location, selected = false) {
  return L.divIcon({
    className: "",
    html: iconHtml(location, selected),
    iconSize: [52, 56],
    iconAnchor: [26, 56]
  });
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function renderMarkers() {
  state.markerLayer.clearLayers();

  for (const location of filteredLocations()) {
    const marker = L.marker([location.latitude, location.longitude], {
      icon: markerIcon(location, location.id === state.selectedId),
      keyboard: true
    });

    marker.on("click", () => {
      state.selectedId = location.id;
      state.viewMode = "detail";
      render();
    });

    marker.addTo(state.markerLayer);
  }
}

function fitMapToResults() {
  const list = filteredLocations();
  if (!list.length) return;

  const bounds = L.latLngBounds(list.map((location) => [location.latitude, location.longitude]));
  if (bounds.isValid()) {
    state.map.fitBounds(bounds.pad(0.15), { animate: true, duration: 0.8 });
  }
}

function mapUrl(location) {
  return `https://maps.apple.com/?ll=${location.latitude},${location.longitude}&q=${encodeURIComponent(location.name)}`;
}

function renderLocationCard(location) {
  const card = els.locationCardTemplate.content.cloneNode(true);
  const article = card.querySelector("article");
  article.dataset.id = location.id;
  article.querySelector("h2").textContent = location.name;
  article.querySelector(".location-card__address").textContent = fmt.address(location);
  article.querySelector(".badge").textContent = fmt.badge(location);
  article.querySelector(".badge").classList.add(fmt.badgeClass(location));

  const meta = article.querySelector(".location-card__meta");
  meta.innerHTML = "";

  const source = document.createElement("span");
  source.textContent = fmt.source(location);

  const verified = document.createElement("span");
  verified.textContent = `Verified ${fmt.date(location.lastVerifiedAt)}`;

  meta.append(source, verified);
  if (location.distanceMiles != null) {
    const distance = document.createElement("span");
    distance.textContent = `${currencyFormatter.format(location.distanceMiles)} away`;
    meta.append(distance);
  }

  article.addEventListener("click", () => {
    state.selectedId = location.id;
    state.viewMode = "detail";
    render();
  });

  return article;
}

function renderDetail(location) {
  const detail = els.detailTemplate.content.cloneNode(true);
  const article = detail.querySelector("article");
  article.querySelector("h2").textContent = location.name;
  article.querySelector("p").textContent = fmt.address(location);
  const badge = article.querySelector(".badge");
  badge.textContent = fmt.badge(location);
  badge.classList.add(fmt.badgeClass(location));

  const grid = article.querySelector(".detail-grid");
  const fields = [
    ["Price", location.status === "pending" ? "Pending review" : location.pricingStatus === "free" ? "Free" : location.pricingStatus === "paid" ? "Paid" : "Unknown"],
    ["Source", fmt.source(location)],
    ["Coordinates", `${location.latitude.toFixed(5)}, ${location.longitude.toFixed(5)}`],
    ["Verified", fmt.date(location.lastVerifiedAt)]
  ];

  for (const [label, value] of fields) {
    const dt = document.createElement("dt");
    dt.textContent = label;
    const dd = document.createElement("dd");
    dd.textContent = value;
    grid.append(dt, dd);
  }

  const notes = article.querySelector(".detail-card__notes");
  notes.textContent = location.notes || "No notes attached yet.";

  article.querySelector('[data-action="maps"]').addEventListener("click", () => {
    window.open(mapUrl(location), "_blank", "noopener,noreferrer");
  });
  article.querySelector('[data-action="close"]').addEventListener("click", () => {
    state.selectedId = null;
    state.viewMode = "results";
    render();
  });

  return article;
}

function renderQueue() {
  const queue = els.queueTemplate.content.cloneNode(true);
  const list = queue.querySelector("#queueList");
  const pendingItems = state.pending.slice().sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

  if (!pendingItems.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No pending submissions yet. Add a stop and it will appear here until reviewed.";
    list.append(empty);
    return queue;
  }

  for (const item of pendingItems) {
    const row = document.createElement("div");
    row.className = "queue-item";
    row.innerHTML = `
      <div class="queue-item__top">
        <div class="queue-item__name">${escapeHtml(item.name)}</div>
        <div class="badge badge--pending">Pending</div>
      </div>
      <div class="queue-item__meta">${escapeHtml(fmt.address(item))}</div>
      <div class="queue-item__meta">${escapeHtml(item.notes || "No notes added.")}</div>
    `;
    list.append(row);
  }

  return queue;
}

function renderSubmissionForm() {
  const formTemplate = els.submissionTemplate.content.cloneNode(true);
  const article = formTemplate.querySelector("article");
  const form = article.querySelector("#submissionForm");
  const useCenterButton = article.querySelector("#useCenterButton");
  const setFormCoordinates = () => {
    const center = state.map.getCenter();
    form.elements.namedItem("latitude").value = center.lat.toFixed(6);
    form.elements.namedItem("longitude").value = center.lng.toFixed(6);
  };

  setFormCoordinates();

  useCenterButton.addEventListener("click", () => {
    setFormCoordinates();
  });

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const data = new FormData(form);
    const draft = {
      id: `pending-${crypto.randomUUID()}`,
      name: String(data.get("name") || "").trim(),
      addressLine1: String(data.get("addressLine1") || "").trim(),
      city: String(data.get("city") || "").trim(),
      state: String(data.get("state") || "").trim(),
      postalCode: String(data.get("postalCode") || "").trim(),
      latitude: Number(data.get("latitude")),
      longitude: Number(data.get("longitude")),
      pricingStatus: String(data.get("pricingStatus") || "unknown"),
      notes: String(data.get("notes") || "").trim(),
      source: "anonymous",
      status: "pending",
      lastVerifiedAt: null,
      createdAt: new Date().toISOString()
    };

    if (!draft.name || !draft.addressLine1 || Number.isNaN(draft.latitude) || Number.isNaN(draft.longitude)) {
      alert("Please fill in the stop name, address, and map coordinates.");
      return;
    }

    state.pending.unshift(draft);
    savePending(state.pending);
    state.viewMode = "queue";
    state.selectedId = null;
    render();
  });

  return article;
}

function renderResults() {
  const fragment = document.createDocumentFragment();
  const list = filteredLocations();

  if (!list.length) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.innerHTML =
      "No matches yet. Try another search or submit a nearby place so it shows up in the queue.";
    fragment.append(empty);
    return fragment;
  }

  for (const location of list) {
    fragment.append(renderLocationCard(location));
  }

  return fragment;
}

function renderPanel() {
  const list = filteredLocations();
  updateStats(list);
  els.panelContent.innerHTML = "";

  if (state.viewMode === "submit") {
    els.panelContent.append(renderSubmissionForm());
    return;
  }

  if (state.viewMode === "queue") {
    els.panelContent.append(renderQueue());
    return;
  }

  if (state.viewMode === "detail" && state.selectedId) {
    const location = resolveLocations().find((item) => item.id === state.selectedId);
    if (location) {
      els.panelContent.append(renderDetail(location));
      return;
    }
    state.viewMode = "results";
  }

  const results = renderResults();
  els.panelContent.append(results);
}

function updateMarkersAndPanel() {
  renderMarkers();
  renderPanel();
}

function syncSegments() {
  document.querySelectorAll(".segment").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.segment === state.activeSegment);
  });
}

function bindEvents() {
  els.searchInput.addEventListener("input", () => {
    state.query = els.searchInput.value;
    state.viewMode = "results";
    state.selectedId = null;
    updateMarkersAndPanel();
  });

  els.locateButton.addEventListener("click", centerOnUser);

  els.submitButton.addEventListener("click", () => {
    state.viewMode = "submit";
    state.selectedId = null;
    renderPanel();
  });

  document.querySelectorAll(".segment").forEach((button) => {
    button.addEventListener("click", () => {
      state.activeSegment = button.dataset.segment;
      state.viewMode = "results";
      state.selectedId = null;
      syncSegments();
      updateMarkersAndPanel();
    });
  });
}

async function centerOnUser() {
  if (!navigator.geolocation) {
    alert("Your browser does not support location access.");
    return;
  }

  navigator.geolocation.getCurrentPosition(
    (position) => {
      const { latitude, longitude } = position.coords;
      const latlng = [latitude, longitude];
      state.mapCenter = latlng;
      if (state.userMarker) {
        state.userMarker.setLatLng(latlng);
      } else {
        state.userMarker = L.circleMarker(latlng, {
          radius: 10,
          color: "#11161d",
          weight: 2,
          fillColor: "#f4efe6",
          fillOpacity: 1
        }).addTo(state.map);
      }

      state.map.flyTo(latlng, 15, { animate: true, duration: 0.8 });
      renderPanel();
    },
    () => {
      alert("Location access is blocked in this browser session. You can still search and pan the map.");
    },
    { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
  );
}

function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return;
  if (!window.isSecureContext && location.hostname !== "localhost" && location.hostname !== "127.0.0.1") return;

  window.addEventListener("load", async () => {
    try {
      await navigator.serviceWorker.register("./sw.js");
    } catch {
      // Ignore failures on unsupported browsers or insecure contexts.
    }
  });
}

async function initMap() {
  state.map = L.map("map", {
    zoomControl: false,
    preferCanvas: true
  }).setView(DEFAULT_CENTER, DEFAULT_ZOOM);

  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: "&copy; OpenStreetMap contributors"
  }).addTo(state.map);

  state.markerLayer = L.layerGroup().addTo(state.map);

  state.map.on("moveend", () => {
    const center = state.map.getCenter();
    state.mapCenter = [center.lat, center.lng];
    if (state.viewMode !== "submit") {
      renderPanel();
    }
  });

  state.map.on("click", (event) => {
    if (state.viewMode === "submit") {
      const panel = document.querySelector("#submissionForm");
      if (panel) {
        panel.elements.namedItem("latitude").value = event.latlng.lat.toFixed(6);
        panel.elements.namedItem("longitude").value = event.latlng.lng.toFixed(6);
      }
    }
  });
}

async function loadSeedData() {
  const response = await fetch(DATA_URL, { cache: "no-store" });
  const data = await response.json();
  state.locations = data.map((item) => ({
    ...item,
    status: item.status || "approved"
  }));
}

async function bootstrap() {
  if (!window.L) {
    document.body.innerHTML = "<main class='app-shell'><div class='drawer'><div class='empty-state'>Leaflet failed to load. Check your internet connection and reload.</div></div></main>";
    return;
  }

  await Promise.all([loadSeedData(), initMap()]);
  bindEvents();
  syncSegments();
  updateMarkersAndPanel();
  fitMapToResults();
  registerServiceWorker();
}

bootstrap().catch((error) => {
  console.error(error);
  document.body.innerHTML = `<main class="app-shell"><div class="drawer"><div class="empty-state">AirFinder could not start: ${escapeHtml(error.message)}</div></div></main>`;
});
