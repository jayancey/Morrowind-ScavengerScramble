-- Category objectives. Each entry has an id, a display name and a matcher that
-- takes an item record from data/items.lua and returns true when it qualifies.
-- Add or remove entries freely; the roller only offers categories that have
-- enough matching instances in the chosen location.

local function isType(t)
    return function(item) return item.type == t end
end

local function isSubtype(t, s)
    return function(item) return item.type == t and item.subtype == s end
end

local function isSubtypes(t, list)
    local set = {}
    for _, s in ipairs(list) do set[s] = true end
    return function(item) return item.type == t and set[item.subtype] == true end
end

local function worthAtLeast(gold)
    return function(item) return (item.value or 0) >= gold end
end

return {
    -- Weapons
    { id = "shortblade", name = "Any short blade (dagger, tanto, short sword)", match = isSubtype("weapon", "shortblade") },
    { id = "longblade", name = "Any long blade", match = isSubtype("weapon", "longblade") },
    { id = "blunt", name = "Any blunt weapon", match = isSubtype("weapon", "blunt") },
    { id = "axe", name = "Any axe", match = isSubtype("weapon", "axe") },
    { id = "spear", name = "Any spear or halberd", match = isSubtype("weapon", "spear") },
    { id = "bow", name = "Any bow or crossbow", match = isSubtypes("weapon", { "bow", "crossbow" }) },
    { id = "thrown", name = "Any thrown weapon (darts, stars, knives)", match = isSubtype("weapon", "thrown") },
    { id = "ammo", name = "Any arrows or bolts", match = isSubtypes("weapon", { "arrow", "bolt" }) },

    -- Armor
    { id = "helmet", name = "Any helmet", match = isSubtype("armor", "helmet") },
    { id = "cuirass", name = "Any cuirass", match = isSubtype("armor", "cuirass") },
    { id = "pauldron", name = "Any pauldron", match = isSubtypes("armor", { "lpauldron", "rpauldron" }) },
    { id = "greaves", name = "Any greaves", match = isSubtype("armor", "greaves") },
    { id = "boots", name = "Any pair of armored boots", match = isSubtype("armor", "boots") },
    { id = "gauntlet", name = "Any gauntlet or bracer", match = isSubtypes("armor", { "lgauntlet", "rgauntlet", "lbracer", "rbracer" }) },
    { id = "shield", name = "Any shield", match = isSubtype("armor", "shield") },

    -- Clothing and jewelry
    { id = "ring", name = "Any ring", match = isSubtype("clothing", "ring") },
    { id = "amulet", name = "Any amulet", match = isSubtype("clothing", "amulet") },
    { id = "robe", name = "Any robe", match = isSubtype("clothing", "robe") },
    { id = "shirt", name = "Any shirt", match = isSubtype("clothing", "shirt") },
    { id = "pants", name = "Any pants", match = isSubtype("clothing", "pants") },
    { id = "shoes", name = "Any pair of shoes", match = isSubtype("clothing", "shoes") },
    { id = "belt", name = "Any belt", match = isSubtype("clothing", "belt") },
    { id = "skirt", name = "Any skirt", match = isSubtype("clothing", "skirt") },
    { id = "glove", name = "Any glove", match = isSubtypes("clothing", { "lglove", "rglove" }) },

    -- Books and scrolls
    { id = "book", name = "Any book", match = isSubtype("book", "book") },
    { id = "scroll", name = "Any scroll", match = isSubtype("book", "scroll") },

    -- Consumables and tools
    { id = "potion", name = "Any potion", match = isType("potion") },
    { id = "ingredient", name = "Any alchemy ingredient", match = isType("ingredient") },
    { id = "soulgem", name = "Any soul gem", match = isSubtype("misc", "soulgem") },
    { id = "thieftool", name = "Any lockpick or probe", match = function(item) return item.type == "lockpick" or item.type == "probe" end },
    { id = "repair", name = "Any repair tool", match = isType("repair") },
    { id = "apparatus", name = "Any alchemy apparatus", match = isType("apparatus") },
    { id = "light", name = "Any portable light (torch, candle, lantern)", match = isType("light") },

    -- Value and enchantment tiers
    { id = "worth100", name = "Any item worth at least 100 gold", match = worthAtLeast(100) },
    { id = "worth500", name = "Any item worth at least 500 gold", match = worthAtLeast(500) },
    { id = "worth2000", name = "Any item worth at least 2000 gold", match = worthAtLeast(2000) },
    { id = "enchanted", name = "Any enchanted item", match = function(item) return item.enchanted == true end },
}
