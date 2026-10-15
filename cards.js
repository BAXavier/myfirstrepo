// ============================================================
//  YOUR CARD INVENTORY
//  Edit this list to add, remove, or update cards for sale.
//
//  Fields:
//    id        - any unique text (no spaces)
//    name      - card name
//    set       - set / expansion name
//    number    - card number in the set, e.g. "4/102"
//    rarity    - e.g. "Common", "Uncommon", "Rare", "Holo Rare", "Ultra Rare"
//    condition - "Mint", "Near Mint", "Lightly Played", "Moderately Played", "Heavily Played"
//    price     - price in dollars (number, no $ sign)
//    quantity  - how many you have (set to 0 to show "Sold out")
//    image     - link to a picture of the card (or a file in an "images" folder,
//                e.g. "images/charizard.jpg")
// ============================================================

const SHOP_SETTINGS = {
  shopName: "My Pokémon Card Shop",
  tagline: "Hand-picked cards from my personal collection",
  // Orders are sent as an email to this address. Change it to yours!
  contactEmail: "you@example.com",
  currency: "USD",
  shippingNote: "Shipping: $1 for plain white envelope, $5 tracked. Combined shipping on multiple cards.",
};

const CARDS = [
  {
    id: "charizard-base",
    name: "Charizard",
    set: "Base Set",
    number: "4/102",
    rarity: "Holo Rare",
    condition: "Lightly Played",
    price: 350,
    quantity: 1,
    image: "https://images.pokemontcg.io/base1/4_hires.png",
  },
  {
    id: "blastoise-base",
    name: "Blastoise",
    set: "Base Set",
    number: "2/102",
    rarity: "Holo Rare",
    condition: "Moderately Played",
    price: 120,
    quantity: 1,
    image: "https://images.pokemontcg.io/base1/2_hires.png",
  },
  {
    id: "venusaur-base",
    name: "Venusaur",
    set: "Base Set",
    number: "15/102",
    rarity: "Holo Rare",
    condition: "Near Mint",
    price: 140,
    quantity: 1,
    image: "https://images.pokemontcg.io/base1/15_hires.png",
  },
  {
    id: "pikachu-base",
    name: "Pikachu",
    set: "Base Set",
    number: "58/102",
    rarity: "Common",
    condition: "Near Mint",
    price: 8,
    quantity: 3,
    image: "https://images.pokemontcg.io/base1/58_hires.png",
  },
  {
    id: "mewtwo-base",
    name: "Mewtwo",
    set: "Base Set",
    number: "10/102",
    rarity: "Holo Rare",
    condition: "Lightly Played",
    price: 45,
    quantity: 1,
    image: "https://images.pokemontcg.io/base1/10_hires.png",
  },
  {
    id: "gengar-fossil",
    name: "Gengar",
    set: "Fossil",
    number: "5/62",
    rarity: "Holo Rare",
    condition: "Near Mint",
    price: 40,
    quantity: 1,
    image: "https://images.pokemontcg.io/base3/5_hires.png",
  },
  {
    id: "snorlax-jungle",
    name: "Snorlax",
    set: "Jungle",
    number: "11/64",
    rarity: "Holo Rare",
    condition: "Lightly Played",
    price: 22,
    quantity: 2,
    image: "https://images.pokemontcg.io/base2/11_hires.png",
  },
  {
    id: "eevee-jungle",
    name: "Eevee",
    set: "Jungle",
    number: "51/64",
    rarity: "Common",
    condition: "Near Mint",
    price: 3,
    quantity: 0,
    image: "https://images.pokemontcg.io/base2/51_hires.png",
  },
];
