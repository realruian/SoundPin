import Foundation

/// Keywords used to detect headphone-like devices and auto-categorize them
struct HeadphoneDetection {
    /// Words that say outright that the device is worn. They win over everything else.
    static let wornWords: [String] = [
        "headphone",
        "headset",
        "earphone",
        "earbud",
        "buds",
        "pods",
        "耳机",
        "耳麦",
    ]

    /// "ear" where it opens a word ("Nothing Ear", "EarFun", "On-Ear"), not inside one ("UltraGear")
    private static let wornPattern = #"(?<![a-z])ear"#

    /// Names in which a worn word is part of another word: "HomePods" has "pods" in it
    static let notWornWords: [String] = [
        "homepod",
    ]

    /// Speakers and speakerphones, by what they are called or by product line. Checked
    /// before `keywords`, because many of the makers listed there sell both: a Marshall
    /// Stanmore or a Beats Pill is a speaker.
    static let speakerWords: [String] = [
        // What it is
        "speaker",
        "soundbar",
        "sound bar",
        "subwoofer",
        "boombox",
        "音箱",
        "音响",
        "回音壁",

        // Beats
        "beats pill",

        // Bose ("Revolve" has "evolve" in it)
        "soundlink",

        // Marshall
        "stanmore",
        "acton",
        "woburn",
        "emberton",
        "kilburn",
        "tufton",
        "middleton",
        "willen",

        // Speakerphones and video bars
        "speakerphone",
        "conference",
        "jabra speak",
        "panacast",
        "poly sync",
        "poly studio",
        "polycom",
        "powerconf",

        // Anker Soundcore
        "soundcore motion",
        "soundcore flare",
        "soundcore boom",
        "soundcore mini",
        "soundcore rave",
        "soundcore glow",
        "soundcore select",

        // Bang & Olufsen
        "beosound",
        "beolit",

        // Razer, SteelSeries, Corsair
        "razer leviathan",
        "razer nommo",
        "steelseries arena",
        "corsair sp",

        // Bowers & Wilkins
        "zeppelin",
    ]

    /// Edifier's speaker ranges (R1700BT, S1000, MR4, QD35); its headphones are the W, WH and X ranges.
    /// Soundcore's first speakers are called just that, or that and a number ("Soundcore 3").
    private static let speakerPattern = #"edifier (r|s|d|m|mr|mp|mf|qr|qd|es)\d|soundcore( \d|$)"#

    /// Makers and product lines that indicate headphones/earbuds
    static let keywords: [String] = [
        // Apple
        "airpods",
        "earpods",
        "beats",
        "powerbeats",
        "beatsx",
        "beats fit",
        "beats solo",
        "beats studio",

        // Sony
        "linkbuds",
        "inzone",
        "ult wear",

        // Samsung
        "galaxy buds",
        "buds pro",
        "buds live",
        "buds fe",

        // Bose
        "quietcomfort",
        "qc ultra",
        "qc45",
        "qc35",
        "soundsport",
        "sport earbuds",

        // Sennheiser
        "momentum",
        "accentum",
        "hd 4",
        "hd 5",
        "pxc",

        // Jabra
        "jabra",
        "evolve",

        // JBL
        "jbl tune",
        "jbl live",
        "jbl tour",
        "jbl reflect",

        // Other brands
        "anker",
        "soundcore",
        "skullcandy",
        "nothing ear",
        "oneplus buds",
        "pixel buds",
        "huawei freebuds",
        "freeclip",
        "freelace",
        "lg tone",
        "lg-tone",
        "qcy",
        "shokz",
        "oppo enco",
        "technics eah",
        "bowers",
        "b&w px",
        "denon perl",
        "focal bathys",
        "hifiman",
        "shure aonic",
        "audio-technica ath",
        "beyerdynamic",
        "marshall",
        "bang & olufsen",
        "b&o",
        "akg",
        "plantronics",
        "poly",
        "razer",
        "steelseries",
        "hyperx",
        "logitech g pro",
        "astro",
        "corsair",
        "1more",
        "tozo",
        "edifier",
        "fiio",
        "moondrop",
    ]

    /// Model numbers and abbreviations that are a word of their own: Sony's WH-, WF- and WI-
    /// ranges ("WH-1000XM5", "LE_WH-CH720N"), and "TWS" for true wireless earbuds
    private static let keywordPattern = #"(?<![a-z0-9])w[hfi]-[a-z0-9]|(?<![a-z])tws(?![a-z])"#

    /// Check if a device name matches headphone patterns
    static func isHeadphone(deviceName: String) -> Bool {
        let nameLower = deviceName.lowercased()
        if notWornWords.contains(where: { nameLower.contains($0) }) {
            return false
        }
        if wornWords.contains(where: { nameLower.contains($0) }) || matches(wornPattern, nameLower) {
            return true
        }
        if speakerWords.contains(where: { nameLower.contains($0) }) || matches(speakerPattern, nameLower) {
            return false
        }
        return keywords.contains { nameLower.contains($0) } || matches(keywordPattern, nameLower)
    }

    private static func matches(_ pattern: String, _ name: String) -> Bool {
        name.range(of: pattern, options: .regularExpression) != nil
    }
}
