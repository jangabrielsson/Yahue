-- ─────────────────────────────────────────────────────────────────────────
-- lang.lua  –  Yahue internationalisation (i18n)
-- Supported language codes: "en" (default), "pl", "hr", "de", "nl", "fr"
-- Set via QA variable  language  (e.g. language=de).
-- Falls back to English for any missing key or unknown language code.
-- ─────────────────────────────────────────────────────────────────────────

local TRANSLATIONS = {
  en = {
    -- Main QA UI element labels
    ["ui.huedevs"]        = "Hue devices found:",
    ["ui.devSelect"]      = "Devices",
    ["ui.pairHue"]        = "Pair with bridge",
    ["ui.restart"]        = "Restart",
    ["ui.dump"]           = "Dump",
    ["ui.applyDevices"]   = "Apply selection",
    -- Info / status messages shown in the 'info' label
    ["msg.missingEngine"] = "Missing engine files",
    ["msg.setIP"]         = "Set Hue_IP variable then restart",
    ["msg.setUser"]       = "Set Hue_User, or press 'Pair with bridge'",
    ["msg.setIPFirst"]    = "Set Hue_IP first, then press Pair",
    ["msg.pressButton"]   = "Press the button on your Hue bridge now\xe2\x80\xa6",
    ["msg.paired"]        = "Paired! Restarting\xe2\x80\xa6",
    ["msg.timedOut"]      = "Timed out \xe2\x80\x94 press Pair and try again",
    ["msg.pairError"]     = "Pair error: ",
    -- Child device UI
    ["ui.scene"]          = "Scene",
    ["ui.static"]         = "Static",
    ["ui.dynamic"]        = "Dynamic",
    ["ui.none"]           = "- None -",
  },
  pl = {
    -- Main QA UI element labels
    ["ui.huedevs"]        = "Znaleziono urządzenia Hue:",
    ["ui.devSelect"]      = "Urządzenia",
    ["ui.pairHue"]        = "Paruj z mostem",
    ["ui.restart"]        = "Uruchom ponownie",
    ["ui.dump"]           = "Zrzut",
    ["ui.applyDevices"]   = "Zastosuj wybór",
    -- Info / status messages
    ["msg.missingEngine"] = "Brak plików silnika",
    ["msg.setIP"]         = "Ustaw zmienną Hue_IP i uruchom ponownie",
    ["msg.setUser"]       = "Ustaw Hue_User lub naciśnij 'Paruj z mostem'",
    ["msg.setIPFirst"]    = "Najpierw ustaw Hue_IP, potem naciśnij Paruj",
    ["msg.pressButton"]   = "Naciśnij teraz przycisk na moście Hue\xe2\x80\xa6",
    ["msg.paired"]        = "Sparowano! Uruchamiam ponownie\xe2\x80\xa6",
    ["msg.timedOut"]      = "Czas minął \xe2\x80\x94 naciśnij Paruj i spróbuj ponownie",
    ["msg.pairError"]     = "Błąd parowania: ",
    -- Child device UI
    ["ui.scene"]          = "Scena",
    ["ui.static"]         = "Statyczna",
    ["ui.dynamic"]        = "Dynamiczna",
    ["ui.none"]           = "- Brak -",
  },
  hr = {
    -- Main QA UI element labels
    ["ui.huedevs"]        = "Pronađeni Hue uređaji:",
    ["ui.devSelect"]      = "Uređaji",
    ["ui.pairHue"]        = "Upari s mostom",
    ["ui.restart"]        = "Ponovo pokreni",
    ["ui.dump"]           = "Ispis",
    ["ui.applyDevices"]   = "Primijeni odabir",
    -- Info / status messages
    ["msg.missingEngine"] = "Nedostaju datoteke pokretača",
    ["msg.setIP"]         = "Postavi varijablu Hue_IP i ponovo pokreni",
    ["msg.setUser"]       = "Postavi Hue_User ili pritisni 'Upari s mostom'",
    ["msg.setIPFirst"]    = "Prvo postavi Hue_IP, zatim pritisni Upari",
    ["msg.pressButton"]   = "Pritisni gumb na Hue mostu sada\xe2\x80\xa6",
    ["msg.paired"]        = "Upareno! Ponovo pokretanje\xe2\x80\xa6",
    ["msg.timedOut"]      = "Istek vremena \xe2\x80\x94 pritisni Upari i pokušaj ponovo",
    ["msg.pairError"]     = "Greška uparivanja: ",
    -- Child device UI
    ["ui.scene"]          = "Scena",
    ["ui.static"]         = "Statično",
    ["ui.dynamic"]        = "Dinamično",
    ["ui.none"]           = "- Ništa -",
  },
  de = {
    -- Main QA UI element labels
    ["ui.huedevs"]        = "Gefundene Hue-Geräte:",
    ["ui.devSelect"]      = "Geräte",
    ["ui.pairHue"]        = "Mit Bridge koppeln",
    ["ui.restart"]        = "Neustart",
    ["ui.dump"]           = "Ausgabe",
    ["ui.applyDevices"]   = "Auswahl übernehmen",
    -- Info / status messages
    ["msg.missingEngine"] = "Engine-Dateien fehlen",
    ["msg.setIP"]         = "Hue_IP-Variable setzen und neu starten",
    ["msg.setUser"]       = "Hue_User setzen oder 'Mit Bridge koppeln' drücken",
    ["msg.setIPFirst"]    = "Zuerst Hue_IP setzen, dann Koppeln drücken",
    ["msg.pressButton"]   = "Jetzt die Taste an der Hue Bridge drücken\xe2\x80\xa6",
    ["msg.paired"]        = "Gekoppelt! Neustart\xe2\x80\xa6",
    ["msg.timedOut"]      = "Zeitüberschreitung \xe2\x80\x94 Koppeln drücken und erneut versuchen",
    ["msg.pairError"]     = "Kopplungsfehler: ",
    -- Child device UI
    ["ui.scene"]          = "Szene",
    ["ui.static"]         = "Statisch",
    ["ui.dynamic"]        = "Dynamisch",
    ["ui.none"]           = "- Keins -",
  },
  nl = {
    -- Main QA UI element labels
    ["ui.huedevs"]        = "Gevonden Hue-apparaten:",
    ["ui.devSelect"]      = "Apparaten",
    ["ui.pairHue"]        = "Koppel met bridge",
    ["ui.restart"]        = "Herstart",
    ["ui.dump"]           = "Dump",
    ["ui.applyDevices"]   = "Selectie toepassen",
    -- Info / status messages
    ["msg.missingEngine"] = "Engine-bestanden ontbreken",
    ["msg.setIP"]         = "Stel Hue_IP-variabele in en herstart",
    ["msg.setUser"]       = "Stel Hue_User in of druk op 'Koppel met bridge'",
    ["msg.setIPFirst"]    = "Stel eerst Hue_IP in, druk dan op Koppelen",
    ["msg.pressButton"]   = "Druk nu op de knop van uw Hue bridge\xe2\x80\xa6",
    ["msg.paired"]        = "Gekoppeld! Herstart\xe2\x80\xa6",
    ["msg.timedOut"]      = "Time-out \xe2\x80\x94 druk op Koppelen en probeer opnieuw",
    ["msg.pairError"]     = "Koppelingsfout: ",
    -- Child device UI
    ["ui.scene"]          = "Scène",
    ["ui.static"]         = "Statisch",
    ["ui.dynamic"]        = "Dynamisch",
    ["ui.none"]           = "- Geen -",
  },
  fr = {
    -- Main QA UI element labels
    ["ui.huedevs"]        = "Appareils Hue trouvés :",
    ["ui.devSelect"]      = "Appareils",
    ["ui.pairHue"]        = "Associer au pont",
    ["ui.restart"]        = "Redémarrer",
    ["ui.dump"]           = "Dump",
    ["ui.applyDevices"]   = "Appliquer la sélection",
    -- Info / status messages
    ["msg.missingEngine"] = "Fichiers moteur manquants",
    ["msg.setIP"]         = "Définir la variable Hue_IP puis redémarrer",
    ["msg.setUser"]       = "Définir Hue_User ou appuyer sur 'Associer au pont'",
    ["msg.setIPFirst"]    = "Définir Hue_IP d'abord, puis appuyer sur Associer",
    ["msg.pressButton"]   = "Appuyez maintenant sur le bouton du pont Hue\xe2\x80\xa6",
    ["msg.paired"]        = "Associé ! Redémarrage\xe2\x80\xa6",
    ["msg.timedOut"]      = "Délai dépassé \xe2\x80\x94 appuyer sur Associer et réessayer",
    ["msg.pairError"]     = "Erreur d'association : ",
    -- Child device UI
    ["ui.scene"]          = "Scène",
    ["ui.static"]         = "Statique",
    ["ui.dynamic"]        = "Dynamique",
    ["ui.none"]           = "- Aucun -",
  },
}

-- ── runtime state ──────────────────────────────────────────────────────────
local _lang = TRANSLATIONS.en  -- active table; defaults to English

-- T(key) – return the translation for key in the active language.
-- Falls back to English, then returns the key itself so callers never get nil.
function T(key)
  return _lang[key] or TRANSLATIONS.en[key] or key
end

-- fibaro.lang.init(code)  – call once at QA startup with the "language"
-- QA variable value.  Unknown codes silently fall back to English.
fibaro.lang = {
  init = function(code)
    _lang = TRANSLATIONS[code] or TRANSLATIONS.en
  end,
  supported = { "en", "pl", "hr", "de", "nl", "fr" },
}
