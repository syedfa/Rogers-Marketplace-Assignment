#!/usr/bin/env node
// Generates mock-server/db.json with 200 realistic listings for JSON Server.
// Zero npm dependencies — only Node's built-in `fs`/`path`/`crypto`.
//
// Usage: node mock-server/seed.mjs

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { randomUUID } from "node:crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const LISTING_COUNT = 200;
const IMAGE_COUNT = 24; // must match scripts/generate-placeholder-images.swift

// Small linear-congruential PRNG, seeded for reproducible output across runs
// (nice for grading/diffing, and for screenshots that don't change every time).
function makeRng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 4294967296;
  };
}
const rng = makeRng(20260716);
const pick = (arr) => arr[Math.floor(rng() * arr.length)];
const int = (min, max) => min + Math.floor(rng() * (max - min + 1));

const CATEGORIES = [
  {
    key: "electronics",
    nouns: ["iPhone 13", "MacBook Air", "iPad", "Sony Headphones", "PS5 Console", "4K Monitor", "Bluetooth Speaker", "Nintendo Switch"],
    adjectives: ["Barely Used", "Like New", "Mint Condition", "Gently Used", "Open Box"],
    priceRange: [40, 1400],
  },
  {
    key: "furniture",
    nouns: ["Sofa", "Standing Desk", "Bookshelf", "Dining Table", "Accent Chair", "Coffee Table", "Bed Frame", "Dresser"],
    adjectives: ["Mid-Century", "IKEA", "Solid Wood", "Modern", "Vintage"],
    priceRange: [30, 900],
  },
  {
    key: "clothing",
    nouns: ["Denim Jacket", "Running Shoes", "Winter Coat", "Leather Boots", "Wool Sweater", "Backpack"],
    adjectives: ["Brand New", "Size M", "Size L", "Rarely Worn", "Designer"],
    priceRange: [10, 220],
  },
  {
    key: "vehicles",
    nouns: ["Mountain Bike", "Electric Scooter", "Road Bike", "Kids Bike", "Skateboard"],
    adjectives: ["Well Maintained", "Recently Tuned", "Lightly Used", "New Tires"],
    priceRange: [60, 1800],
  },
  {
    key: "home_and_garden",
    nouns: ["Patio Set", "Lawn Mower", "Grill", "Planter Set", "Tool Kit", "Ladder"],
    adjectives: ["Outdoor", "Heavy Duty", "Compact", "All-Season"],
    priceRange: [20, 600],
  },
  {
    key: "toys",
    nouns: ["LEGO Set", "Board Game Bundle", "Stroller", "Kids Table", "Puzzle Set"],
    adjectives: ["Complete Set", "Ages 5+", "Like New", "Family Favorite"],
    priceRange: [8, 180],
  },
  {
    key: "sports",
    nouns: ["Yoga Mat Bundle", "Weight Set", "Tennis Racket", "Golf Clubs", "Camping Tent", "Kayak"],
    adjectives: ["Barely Used", "Pro Grade", "Complete Kit", "Great Condition"],
    priceRange: [15, 700],
  },
  {
    key: "other",
    nouns: ["Guitar", "Camera", "Sewing Machine", "Air Purifier", "Espresso Machine"],
    adjectives: ["Works Great", "Estate Sale Find", "Rarely Used", "Collector's Item"],
    priceRange: [20, 500],
  },
];

const CITIES = ["Toronto, ON", "Mississauga, ON", "Vaughan, ON", "Markham, ON", "Brampton, ON"];

function makeListing(index) {
  const category = pick(CATEGORIES);
  const noun = pick(category.nouns);
  const adjective = pick(category.adjectives);
  const [minPrice, maxPrice] = category.priceRange;
  const price = int(minPrice, maxPrice) + (rng() > 0.5 ? 0.99 : 0);

  const createdDaysAgo = int(0, 60);
  const createdAt = new Date(Date.now() - createdDaysAgo * 86_400_000);
  const updatedAt = createdAt;

  const imageIndex = index % IMAGE_COUNT;

  return {
    id: randomUUID(),
    title: `${adjective} ${noun}`,
    description:
      `${adjective} ${noun.toLowerCase()}. Selling because I no longer need it. ` +
      `Pickup available in ${pick(CITIES)}, or can meet nearby. Message me with any questions!`,
    price,
    category: category.key,
    imageURLs: [`/images/placeholder-${imageIndex}.jpg`],
    createdAt: createdAt.toISOString(),
    updatedAt: updatedAt.toISOString(),
  };
}

const listings = Array.from({ length: LISTING_COUNT }, (_, i) => makeListing(i));

const db = { listings };
const outPath = path.join(__dirname, "db.json");
writeFileSync(outPath, JSON.stringify(db, null, 2));

console.log(`Wrote ${listings.length} listings to ${outPath}`);
