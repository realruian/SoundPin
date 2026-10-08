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

        // Jabra and Poly speakerphones
        "jabra speak",
        "poly sync",

        // Anker Soundcore
        "soundcore motion",
        "soundcore flare",
        "soundcore boom",
        "soundcore mini",
        "soundcore rave",
        "soundcore glow",

        // Bang & Olufsen
        "beosound",
        "beolit",

        // Razer
        "razer leviathan",
        "razer nommo",
    ]

    /// Edifier's speaker ranges (R1700BT, S1000, MR4); its headphones are the W, WH and X ranges
    private static let speakerPattern = #"edifier (r|s|d|m|mr|mp|qr|es)\d"#

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
        "wh-1000",  // WH-1000XM series
        "wf-1000",  // WF-1000XM series
        "linkbuds",
        "inzone",

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
        "hd 4",
        "hd 5",
        "pxc",

        // Jabra
        "jabra",
        "elite",
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

    /// Check if a device name matches headphone patterns
    static func isHeadphone(deviceName: String) -> Bool {
        let nameLower = deviceName.lowercased()
        if wornWords.contains(where: { nameLower.contains($0) }) || matches(wornPattern, nameLower) {
            return true
        }
        if speakerWords.contains(where: { nameLower.contains($0) }) || matches(speakerPattern, nameLower) {
            return false
        }
        return keywords.contains { nameLower.contains($0) }
    }

    private static func matches(_ pattern: String, _ name: String) -> Bool {
        name.range(of: pattern, options: .regularExpression) != nil
    }
}
