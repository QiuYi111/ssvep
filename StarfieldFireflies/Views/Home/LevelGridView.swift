import SwiftUI

struct LevelGridView: View {
    let onSelectLevel: (LevelID) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(LevelID.allCases) { level in
                let config = level.cardConfig
                let locked = !level.isUnlocked

                LevelCard(
                    level: level,
                    isLocked: locked,
                    subtitle: config.subtitle,
                    icon: config.icon,
                    accentColor: config.color
                )
                .onTapGesture {
                    if !locked {
                        onSelectLevel(level)
                    }
                }
            }
        }
    }
}

extension LevelID {
    struct CardConfig {
        let icon: String
        let color: Color
        let subtitle: String
    }

    var cardConfig: CardConfig {
        switch self {
        case .level1:
            return CardConfig(
                icon: "water.waves",
                color: Color(red: 1.00, green: 0.77, blue: 0.58),
                subtitle: "花蕊波光 15Hz"
            )
        case .level2:
            return CardConfig(
                icon: "light.max",
                color: Color(red: 0.80, green: 0.86, blue: 0.22),
                subtitle: "萤火虫群 15Hz"
            )
        case .level3:
            return CardConfig(
                icon: "star.circle",
                color: Color(red: 1.00, green: 0.91, blue: 0.65),
                subtitle: "主星 15Hz / 繁星 20Hz"
            )
        case .level4:
            return CardConfig(
                icon: "eye",
                color: Color(red: 0.80, green: 0.86, blue: 0.22),
                subtitle: "黄绿 15Hz / 幽蓝 20Hz"
            )
        case .level5:
            return CardConfig(
                icon: "bird",
                color: Color(red: 0.60, green: 0.76, blue: 0.92),
                subtitle: "灵燕 15Hz / 雷云 20Hz"
            )
        case .level6:
            return CardConfig(
                icon: "meteor",
                color: Color(red: 1.00, green: 0.91, blue: 0.65),
                subtitle: "孤星 15Hz / 瞬态干扰"
            )
        }
    }
}
