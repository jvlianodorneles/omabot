// Model.js - Data filtering, search, and category management for Omabot
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
 * Extracts unique categories from the bots dataset, always starting with "All".
 */
function extractCategories(bots) {
  if (!bots || !bots.length) return ["All"];
  var map = { "All": true };
  var list = ["All"];
  
  for (var i = 0; i < bots.length; i++) {
    var cat = bots[i].category;
    if (cat && typeof cat === "string") {
      cat = cat.trim();
      if (cat && !map[cat]) {
        map[cat] = true;
        list.push(cat);
      }
    }
  }
  
  // Keep "All" first, sort the rest alphabetically
  var sub = list.slice(1).sort(function(a, b) {
    return a.localeCompare(b);
  });
  return ["All"].concat(sub);
}

/**
 * Filters bots by keyword search and category selection.
 */
function filterBots(bots, query, selectedCategory) {
  if (!bots || !bots.length) return [];
  
  var q = (query || "").trim().toLowerCase();
  var cat = (selectedCategory || "All").trim();
  var hasQuery = q.length > 0;
  var hasCat = cat !== "" && cat.toLowerCase() !== "all";

  return bots.filter(function(bot) {
    // Check Category filter
    if (hasCat) {
      var botCat = (bot.category || "General").trim();
      if (botCat.toLowerCase() !== cat.toLowerCase()) {
        return false;
      }
    }

    // Check Text Query
    if (hasQuery) {
      var name = (bot.name || "").toLowerCase();
      var prompt = (bot.prompt || "").toLowerCase();
      var category = (bot.category || "").toLowerCase();
      var contributor = (bot.contributor || "").toLowerCase();

      var match = (
        name.indexOf(q) !== -1 ||
        prompt.indexOf(q) !== -1 ||
        category.indexOf(q) !== -1 ||
        contributor.indexOf(q) !== -1
      );
      if (!match) return false;
    }

    return true;
  });
}

/**
 * Cleans and formats prompt text for preview (removes redundant newlines/markdown headers).
 */
function cleanPreview(promptText) {
  if (!promptText) return "";
  var cleaned = promptText
    .replace(/^#+\s+/gm, "")
    .replace(/\r?\n+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return cleaned;
}
