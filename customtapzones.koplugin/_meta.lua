-- v1.1: Inlined en/uk tr() localization; added version header.
-- v1.0: Initial version.
local function is_uk_language()
    local lang = G_reader_settings and G_reader_settings:readSetting("language")
    return type(lang) == "string" and lang:sub(1, 2) == "uk"
end

local function tr(en, uk)
    if is_uk_language() then return uk or en end
    return en
end

return {
    fullname = tr("Custom tap zones", "Власні зони гортання"),
    description = tr(
        "Configure custom page-turn tap zones.",
        "Дозволяє настроїти власні зони гортання сторінок."),
}
