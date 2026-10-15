// Shop logic: rendering, filtering, cart, and checkout.
// You normally only need to edit cards.js.

const $ = (id) => document.getElementById(id);

const money = (n) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: SHOP_SETTINGS.currency }).format(n);

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const cardById = (id) => CARDS.find((c) => c.id === id);

// ---------- Cart (saved in the browser so it survives a refresh) ----------
let cart = {};
try {
  cart = JSON.parse(localStorage.getItem("cart") || "{}");
} catch (e) {
  cart = {};
}
// Drop anything no longer in the inventory, and cap at available stock.
for (const id of Object.keys(cart)) {
  const card = cardById(id);
  if (!card || card.quantity <= 0) delete cart[id];
  else cart[id] = Math.min(cart[id], card.quantity);
}

function saveCart() {
  try {
    localStorage.setItem("cart", JSON.stringify(cart));
  } catch (e) {
    /* storage unavailable; cart still works for this visit */
  }
}

function addToCart(id) {
  const card = cardById(id);
  const current = cart[id] || 0;
  if (current >= card.quantity) return;
  cart[id] = current + 1;
  saveCart();
  renderCart();
  renderCards();
}

function changeQty(id, delta) {
  const card = cardById(id);
  const next = (cart[id] || 0) + delta;
  if (next <= 0) delete cart[id];
  else cart[id] = Math.min(next, card.quantity);
  saveCart();
  renderCart();
  renderCards();
}

// ---------- Card grid ----------
function renderCards() {
  const query = $("search").value.trim().toLowerCase();
  const set = $("set-filter").value;
  const inStockOnly = $("in-stock").checked;
  const sort = $("sort").value;

  let list = CARDS.filter((c) => {
    if (set && c.set !== set) return false;
    if (inStockOnly && c.quantity <= 0) return false;
    if (query && !`${c.name} ${c.set} ${c.rarity}`.toLowerCase().includes(query)) return false;
    return true;
  });

  list.sort((a, b) => {
    if (sort === "price-asc") return a.price - b.price;
    if (sort === "price-desc") return b.price - a.price;
    return a.name.localeCompare(b.name);
  });

  $("result-count").textContent = `${list.length} card${list.length === 1 ? "" : "s"}`;

  $("card-grid").innerHTML = list
    .map((c) => {
      const inCart = cart[c.id] || 0;
      const soldOut = c.quantity <= 0;
      const maxed = !soldOut && inCart >= c.quantity;
      const label = soldOut ? "Sold out" : maxed ? "All in cart" : "Add to cart";
      return `
        <article class="card${soldOut ? " sold-out" : ""}">
          <div class="img-fallback" aria-hidden="true">${escapeHtml(c.name)}</div>
          <img src="${escapeHtml(c.image)}" alt="${escapeHtml(c.name)} card" loading="lazy" />
          <div class="card-body">
            <h3>${escapeHtml(c.name)}</h3>
            <p class="meta">${escapeHtml(c.set)} · ${escapeHtml(c.number)}</p>
            <div class="tags">
              <span class="tag">${escapeHtml(c.rarity)}</span>
              <span class="tag">${escapeHtml(c.condition)}</span>
            </div>
            <p class="meta">${soldOut ? "Sold out" : `${c.quantity} available`}</p>
            <div class="price-row">
              <span class="price">${money(c.price)}</span>
              <button class="add-button" data-id="${escapeHtml(c.id)}" ${soldOut || maxed ? "disabled" : ""}>${label}</button>
            </div>
          </div>
        </article>`;
    })
    .join("");
}

// ---------- Cart drawer ----------
function cartTotal() {
  return Object.entries(cart).reduce((sum, [id, qty]) => sum + cardById(id).price * qty, 0);
}

function renderCart() {
  const entries = Object.entries(cart);
  $("cart-count").textContent = entries.reduce((n, [, q]) => n + q, 0);
  $("cart-total").textContent = money(cartTotal());
  $("checkout").disabled = entries.length === 0;

  $("cart-items").innerHTML = entries.length
    ? entries
        .map(([id, qty]) => {
          const c = cardById(id);
          return `
            <li>
              <div>
                <strong>${escapeHtml(c.name)}</strong>
                <div class="muted small">${escapeHtml(c.set)} · ${escapeHtml(c.condition)} · ${money(c.price)}</div>
              </div>
              <div class="qty">
                <button data-id="${escapeHtml(id)}" data-delta="-1" aria-label="Remove one">−</button>
                <span>${qty}</span>
                <button data-id="${escapeHtml(id)}" data-delta="1" aria-label="Add one" ${qty >= c.quantity ? "disabled" : ""}>+</button>
              </div>
            </li>`;
        })
        .join("")
    : `<li class="muted">Your cart is empty.</li>`;
}

function openCart(open) {
  $("cart").classList.toggle("open", open);
  $("cart").setAttribute("aria-hidden", String(!open));
  $("backdrop").hidden = !open;
}

// ---------- Checkout: build an order email ----------
function checkout() {
  const lines = Object.entries(cart).map(([id, qty]) => {
    const c = cardById(id);
    return `- ${qty} x ${c.name} (${c.set} ${c.number}, ${c.condition}) @ ${money(c.price)} = ${money(c.price * qty)}`;
  });
  const name = $("buyer-name").value.trim();
  const notes = $("buyer-notes").value.trim();

  const body = [
    `Hi! I'd like to buy the following cards:`,
    ``,
    ...lines,
    ``,
    `Subtotal: ${money(cartTotal())} (plus shipping)`,
    ``,
    `Name: ${name || "(not given)"}`,
    notes ? `Notes: ${notes}` : "",
  ].join("\n");

  const subject = `Card order${name ? " from " + name : ""}`;
  window.location.href =
    `mailto:${SHOP_SETTINGS.contactEmail}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

// ---------- Setup ----------
function init() {
  document.title = SHOP_SETTINGS.shopName;
  $("shop-name").textContent = SHOP_SETTINGS.shopName;
  $("tagline").textContent = SHOP_SETTINGS.tagline;
  $("shipping-note").textContent = SHOP_SETTINGS.shippingNote;

  const sets = [...new Set(CARDS.map((c) => c.set))].sort();
  $("set-filter").innerHTML += sets.map((s) => `<option>${escapeHtml(s)}</option>`).join("");

  ["search", "set-filter", "sort", "in-stock"].forEach((id) =>
    $(id).addEventListener("input", renderCards)
  );

  // Show a placeholder if a card image link is broken.
  $("card-grid").addEventListener(
    "error",
    (e) => {
      if (e.target.tagName === "IMG") e.target.closest(".card").classList.add("no-image");
    },
    true
  );

  $("card-grid").addEventListener("click", (e) => {
    const btn = e.target.closest(".add-button");
    if (btn) addToCart(btn.dataset.id);
  });
  $("cart-items").addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-delta]");
    if (btn) changeQty(btn.dataset.id, Number(btn.dataset.delta));
  });

  $("cart-button").addEventListener("click", () => openCart(true));
  $("close-cart").addEventListener("click", () => openCart(false));
  $("backdrop").addEventListener("click", () => openCart(false));
  document.addEventListener("keydown", (e) => e.key === "Escape" && openCart(false));
  $("checkout").addEventListener("click", checkout);

  renderCards();
  renderCart();
}

init();
