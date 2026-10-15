# Pokémon Card Shop

A simple website for selling Pokémon cards from your collection. It needs no server, database, or build step: it's just HTML, CSS, and JavaScript files.

## Features
- A grid of cards showing image, set, rarity, condition, price, and stock
- Search, filter by set, sort by price or name, and an "in stock only" toggle
- A cart that stays put when the page is refreshed and won't let buyers add more copies than you have
- Checkout opens the buyer's email app with the order already written and addressed to you. You reply with payment details (PayPal, Venmo, etc.).

## Adding your cards
Edit **`cards.js`**:
1. In `SHOP_SETTINGS`, set `contactEmail` to your email, and change the shop name, tagline, and shipping note if you like.
2. Edit the `CARDS` list. Each card is one `{ ... }` block. Copy an existing block to add a new card. Set `quantity: 0` to show a card as sold out.

**Card images:** you can either
- use an official scan from the [Pokémon TCG API](https://pokemontcg.io/). Images follow the pattern `https://images.pokemontcg.io/<set-id>/<number>_hires.png`. Or,
- take photos of your actual cards (buyers like this best), put them in an `images/` folder, and use `image: "images/my-card.jpg"`.

## Previewing locally
Open `index.html` in your browser by double-clicking it.

## Putting it online (free) with GitHub Pages
1. Merge this into your `main` branch.
2. On GitHub, go to **Settings → Pages**.
3. Under "Build and deployment", choose **Deploy from a branch**, then pick `main` and `/ (root)`, and click Save.
4. After a minute your shop will be live at `https://<your-username>.github.io/myfirstrepo/`.

## Ideas for later
- Accept payment directly with a PayPal or Stripe "Buy" button for each card
- Add a "Recently sold" section
