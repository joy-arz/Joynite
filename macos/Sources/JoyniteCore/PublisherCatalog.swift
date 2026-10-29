import Foundation

public struct PublisherGame: Identifiable, Sendable {
    public let id: String
    public let aliases: [String]
    public let metadata: Metadata
}
public enum PublisherCatalog {
    public static let games: [PublisherGame] = [
        .init(id: "roblox", aliases: ["Roblox", "Roblox Player"], metadata: .init(name: "Roblox", summary: "Explore experiences made by a worldwide community, play with friends, and create your own worlds on Roblox.", developer: "Roblox Corporation", artwork: "https://images.rbxcdn.com/5348266ea6c5e67b19d6a814cbbb70f6.jpg", url: "https://www.roblox.com/", source: "Roblox · publisher catalog", genres: ["Multiplayer", "Creation", "Platform"])),
        .init(id: "valorant", aliases: ["Valorant", "VALORANT"], metadata: .init(name: "VALORANT", summary: "A competitive five-versus-five tactical shooter pairing precise gunplay with agents and their distinct abilities.", developer: "Riot Games", url: "https://playvalorant.com/en-us/", source: "Riot Games · publisher catalog", genres: ["Tactical shooter", "Multiplayer"])),
        .init(id: "genshin", aliases: ["Genshin Impact", "GenshinImpact", "原神"], metadata: .init(name: "Genshin Impact", summary: "Explore Teyvat in an open-world action RPG. Build a party, combine elemental abilities, and follow the Traveler's journey.", developer: "HoYoverse", url: "https://genshin.hoyoverse.com/en/", source: "HoYoverse · publisher catalog", genres: ["Action RPG", "Open world"])),
        .init(id: "starrail", aliases: ["Honkai Star Rail", "Honkai: Star Rail", "Star Rail"], metadata: .init(name: "Honkai: Star Rail", summary: "Travel aboard the Astral Express in a space-fantasy RPG with turn-based combat and a growing cast of companions.", developer: "HoYoverse", url: "https://hsr.hoyoverse.com/en-us/", source: "HoYoverse · publisher catalog", genres: ["Turn-based RPG", "Adventure"])),
        .init(id: "zzz", aliases: ["Zenless Zone Zero", "ZenlessZoneZero"], metadata: .init(name: "Zenless Zone Zero", summary: "Navigate New Eridu and its dangerous Hollows in an urban action RPG built around squad-based combat.", developer: "HoYoverse", url: "https://zenless.hoyoverse.com/en-us/", source: "HoYoverse · publisher catalog", genres: ["Action RPG"])),
        .init(id: "league", aliases: ["League of Legends", "LeagueofLegends", "League Client"], metadata: .init(name: "League of Legends", summary: "Two teams of five champions compete to break through their opponents' defenses and destroy the enemy Nexus.", developer: "Riot Games", url: "https://www.leagueoflegends.com/en-us/", source: "Riot Games · publisher catalog", genres: ["MOBA", "Strategy", "Multiplayer"])),
        .init(id: "minecraft", aliases: ["Minecraft", "Minecraft Launcher", "Minecraft Java Edition"], metadata: .init(name: "Minecraft", summary: "Build, explore, and survive in a world made of blocks. Play creatively or gather resources and venture into the unknown.", developer: "Mojang Studios", url: "https://www.minecraft.net/en-us", source: "Mojang Studios · publisher catalog", genres: ["Sandbox", "Survival", "Creation"]))
    ]
    public static func match(_ name: String) -> PublisherGame? {
        let normalized = Game.normalized(name)
        return games.first { $0.aliases.contains { Game.normalized($0) == normalized } }
    }
}
