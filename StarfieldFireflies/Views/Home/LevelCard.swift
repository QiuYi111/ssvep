// ============================================
// Views/Home/LevelCard.swift
// StarfieldFireflies — 星空与萤火
// ============================================

import SwiftUI

struct LevelCard: View {
    let level: LevelID
    let isLocked: Bool
    let subtitle: String
    let icon: String
    let accentColor: Color

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(isLocked ? 0.08 : 0.16))
                        .frame(width: 48, height: 48)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(accentColor)
                    }
                }

                Spacer()

                Text(realmTag)
                    .font(.system(size: 11, weight: .medium, design: .serif))
                    .foregroundColor(isLocked ? Color.secondary.opacity(0.45) : accentColor.opacity(0.85))
            }

            Text(level.displayName)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundColor(isLocked ? Color.secondary.opacity(0.45) : Color.white.opacity(0.92))
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(isLocked ? Color.secondary.opacity(0.35) : Color.white.opacity(0.58))
                .minimumScaleFactor(0.72)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Capsule()
                .fill(accentColor.opacity(isLocked ? 0.08 : 0.45))
                .frame(height: 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 154)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isLocked ? 0.035 : 0.055))

                LinearGradient(
                    colors: [
                        accentColor.opacity(isLocked ? 0.02 : 0.14),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    accentColor.opacity(isLocked ? 0.05 : 0.28),
                    lineWidth: 1
                )
        )
        .opacity(isLocked ? 0.45 : 1.0)
        .scaleEffect(isHovering && !isLocked ? 1.03 : (isLocked ? 0.97 : 1.0))
        .animation(
            reduceMotion ? .none : .easeOut(duration: 0.2),
            value: isHovering
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel("\(level.displayName)，\(realmTag)")
        .accessibilityHint(isLocked ? "已锁定，完成前一关卡后解锁" : "双击开始训练")
        .accessibilityAddTraits(isLocked ? [] : [.isButton])
    }

    private var realmTag: String {
        switch level {
        case .level1: return "觉醒·壹"
        case .level2: return "觉醒·贰"
        case .level3: return "共鸣·壹"
        case .level4: return "共鸣·贰"
        case .level5: return "心流·壹"
        case .level6: return "心流·贰"
        }
    }
}
