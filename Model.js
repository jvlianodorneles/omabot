// Model.js - Advanced search, ranking, categories, and state management for Omabot
.pragma library

/**
 * Parses raw bots JSON string into a structured array of bot objects.
 */
function parseBots(jsonString) {
  if (!jsonString) return [];
  try {
    var data = JSON.parse(jsonString);
    if (Array.isArray(data)) return data;
    if (data && Array.isArray(data.bots)) return data.bots;
    return [];
  } catch (e) {
    return [];
  }
}

/**
 * Extracts all available categories, prepending special smart views (Favorites & Recent).
 */
function extractCategories(bots, customBots, favoritesList, recentsList) {
  var list = ["All"];
  
  if (favoritesList && favoritesList.length > 0) {
    list.push("⭐ Favorites");
  }
  if (recentsList && recentsList.length > 0) {
    list.push("🕒 Recent");
  }

  var map = {};
  var allItems = (bots || []).concat(customBots || []);
  
  for (var i = 0; i < allItems.length; i++) {
    var cat = allItems[i].category;
    if (cat && typeof cat === "string") {
      cat = cat.trim();
      if (cat && cat !== "General" && !map[cat]) {
        map[cat] = true;
      }
    }
  }

  var sortedCats = Object.keys(map).sort(function(a, b) {
    return a.localeCompare(b);
  });

  for (var j = 0; j < sortedCats.length; j++) {
    list.push(sortedCats[j]);
  }

  if (customBots && customBots.length > 0 && !map["Custom"]) {
    list.push("📁 Custom");
  }

  return list;
}

/**
 * Computes relevance score for search query matching.
 */
function scoreBot(bot, query) {
  if (!query) return 0;
  var q = query.toLowerCase();
  var name = (bot.name || "").toLowerCase();
  var cat = (bot.category || "").toLowerCase();
  var prompt = (bot.prompt || "").toLowerCase();
  var contrib = (bot.contributor || "").toLowerCase();
  var score = 0;

  // Exact or prefix name match
  if (name === q) score += 200;
  else if (name.indexOf(q) === 0) score += 100;
  else if (name.indexOf(q) !== -1) score += 50;

  // Category match
  if (cat === q) score += 40;
  else if (cat.indexOf(q) !== -1) score += 20;

  // Integrations match
  if (bot.integrations && Array.isArray(bot.integrations)) {
    for (var i = 0; i < bot.integrations.length; i++) {
      var intName = String(bot.integrations[i]).toLowerCase();
      if (intName === q) score += 30;
      else if (intName.indexOf(q) !== -1) score += 15;
    }
  }

  // Contributor match
  if (contrib.indexOf(q) !== -1) score += 10;

  // Prompt body match
  if (prompt.indexOf(q) !== -1) score += 5;

  return score;
}

/**
 * Filters and ranks bots based on search query, category filter, favorites, and recents.
 */
function filterBots(allBots, customBots, query, selectedCategory, favoritesSet, recentsList) {
  var pool = [];
  var isRecentFilter = selectedCategory === "🕒 Recent";
  var isFavFilter = selectedCategory === "⭐ Favorites";
  var isCustomFilter = selectedCategory === "📁 Custom";

  // Combine standard bots and custom bots
  var combined = (allBots || []).concat(
    (customBots || []).map(function(b) {
      b.isCustom = true;
      return b;
    })
  );

  // If Recent filter is selected, maintain recents order
  if (isRecentFilter) {
    if (!recentsList || !recentsList.length) return [];
    var botMap = {};
    for (var i = 0; i < combined.length; i++) {
      var slug = combined[i].slug || combined[i].name;
      botMap[slug] = combined[i];
    }
    for (var r = 0; r < recentsList.length; r++) {
      var rSlug = recentsList[r];
      if (botMap[rSlug]) pool.push(botMap[rSlug]);
    }
  } else {
    pool = combined;
  }

  var q = (query || "").trim().toLowerCase();
  var hasQuery = q.length > 0;
  var hasCatFilter = (
    selectedCategory &&
    selectedCategory !== "All" &&
    !isRecentFilter &&
    !isFavFilter &&
    !isCustomFilter
  );

  var results = [];

  for (var k = 0; k < pool.length; k++) {
    var bot = pool[k];
    var botSlug = bot.slug || bot.name;

    // Check Favorites filter
    if (isFavFilter) {
      if (!favoritesSet || !favoritesSet[botSlug]) continue;
    }

    // Check Custom filter
    if (isCustomFilter) {
      if (!bot.isCustom) continue;
    }

    // Check Category filter
    if (hasCatFilter) {
      var botCat = (bot.category || "General").trim();
      if (botCat.toLowerCase() !== selectedCategory.toLowerCase()) {
        continue;
      }
    }

    // Check Search Query
    if (hasQuery) {
      var score = scoreBot(bot, q);
      if (score <= 0) continue;
      bot._searchScore = score;
    }

    results.push(bot);
  }

  // Sort by search score if querying, else alphabetically
  if (hasQuery) {
    results.sort(function(a, b) {
      return (b._searchScore || 0) - (a._searchScore || 0);
    });
  } else if (!isRecentFilter) {
    results.sort(function(a, b) {
      var aFav = (favoritesSet && favoritesSet[a.slug || a.name]) ? 1 : 0;
      var bFav = (favoritesSet && favoritesSet[b.slug || b.name]) ? 1 : 0;
      if (aFav !== bFav) return bFav - aFav; // Favorites on top
      return (a.name || "").localeCompare(b.name || "");
    });
  }

  return results;
}

/**
 * Returns a distinct themed accent color for category chips.
 */
function categoryColor(cat, defaultColor) {
  if (!cat) return defaultColor;
  var c = cat.toLowerCase();
  if (c === "marketing") return "#F59E0B";     // Amber
  if (c === "sales") return "#10B981";         // Emerald
  if (c === "productivity") return "#3B82F6";  // Blue
  if (c === "ops") return "#8B5CF6";           // Violet
  if (c === "success") return "#EC4899";       // Pink
  if (c === "personal") return "#EAB308";      // Yellow
  if (c === "coding") return "#06B6D4";        // Cyan
  if (c === "design") return "#F43F5E";        // Rose
  return defaultColor;
}

/**
 * Cleans prompt text for preview cards.
 */
function cleanPreview(promptText) {
  if (!promptText) return "";
  return promptText
    .replace(/^#+\s+/gm, "")
    .replace(/\r?\n+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
