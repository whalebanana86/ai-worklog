import AppKit
import SwiftUI
import WorkLogCore

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// 밝은 모드와 어두운 모드에서 따로 고른 색.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    /// 차트 축 글자. `.secondary` 를 쓰면 차트 안에서는 첫 계열 색으로 칠해져서 따로 둔다.
    static let axisInk = Color(nsColor: .secondaryLabelColor)
    static let cardBorder = Color(nsColor: .separatorColor).opacity(0.6)
    static let searchHighlight = Color(light: 0xFFE27A, dark: 0x7A5D00)
    static let added = Color(light: 0x1F8A3B, dark: 0x4CC26B)
    static let removed = Color(light: 0xC23B3B, dark: 0xE66767)

    /// 히트맵용 한 가지 색(파랑) 단계. 0 은 바탕에 묻히고 클수록 진해진다.
    static func heat(_ level: Int) -> Color {
        let light: [UInt32] = [0xCDE2FB, 0x9EC5F4, 0x6DA7EC, 0x3987E5, 0x256ABF, 0x184F95]
        let dark: [UInt32] = [0x10325E, 0x104281, 0x1C5CAB, 0x2A78D6, 0x5598E7, 0x86B6EF]
        let i = max(0, min(level, light.count - 1))
        return Color(light: light[i], dark: dark[i])
    }
}

extension AITool {
    /// 차트 범주 색 1~3번 칸 (색약 검증 통과 순서).
    var color: Color {
        switch self {
        case .codex: return Color(light: 0x2A78D6, dark: 0x3987E5)
        case .claudeCode: return Color(light: 0xEB6834, dark: 0xD95926)
        case .lmStudio: return Color(light: 0x1BAF7A, dark: 0x199E70)
        }
    }

    var symbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .lmStudio: return "cpu"
        }
    }

    static var chartOrder: [AITool] { [.codex, .claudeCode, .lmStudio] }
}

/// 둥근 테두리 카드.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var padding: CGFloat = 16
    /// 나란히 놓인 카드끼리 높이를 맞출 때 켠다 (`CardPair`).
    var fillHeight = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.cardBorder))
    }
}

/// 카드 두 장을 너비를 반씩 나눠 나란히 놓는다. 자리가 모자라면 위아래로 쌓는다.
/// (격자에 맡기면 넓은 창에서 세 칸이 생겨 두 장이 왼쪽으로 쏠린다.)
struct CardPair<First: View, Second: View>: View {
    var minWidth: CGFloat = 360
    var spacing: CGFloat = 18
    @ViewBuilder var first: First
    @ViewBuilder var second: Second
    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if width == 0 || width >= minWidth * 2 + spacing {
                HStack(alignment: .top, spacing: spacing) {
                    first.frame(maxWidth: .infinity)
                    second.frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: spacing) {
                    first
                    second
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var caption: String?
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.cardBorder))
    }
}

/// 도구 이름이 붙은 작은 꼬리표. 색만으로 구분하지 않도록 글자를 같이 쓴다.
struct ToolBadge: View {
    var tool: AITool
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tool.color).frame(width: 7, height: 7)
            if !compact { Text(tool.displayName) }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 0 : 7)
        .padding(.vertical, compact ? 0 : 2)
        .background {
            if !compact { Capsule().fill(tool.color.opacity(0.12)) }
        }
        .help(tool.displayName)
    }
}

struct Chip: View {
    var text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.1)))
    }
}

/// +123 −45 처럼 늘고 준 줄 수.
struct LineDelta: View {
    var added: Int
    var removed: Int
    var approximate = false

    var body: some View {
        HStack(spacing: 6) {
            if approximate { Text(L("약")).foregroundStyle(.tertiary) }
            Text("+\(Fmt.number(added))").foregroundStyle(Color.added)
            Text("−\(Fmt.number(removed))").foregroundStyle(Color.removed)
        }
        .font(.caption.monospacedDigit())
    }
}

/// 가로로 넘치면 다음 줄로 넘기는 배치 (칩 목록용).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 비어 있을 때 보여 주는 안내.
struct EmptyHint: View {
    var title: String
    var message: String
    var symbol: String = "tray"

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

/// 테두리 있는 카드 가운데에 놓는 빈 화면 안내. 탭마다 "아직 없어요"를 같은 모양으로 보여 준다.
/// `actions` 에 "전체 기간 보기" 같은 버튼을 넣을 수 있다.
struct EmptyCard<Actions: View>: View {
    var title: String
    var message: String
    var symbol: String = "tray"
    @ViewBuilder var actions: Actions

    var body: some View {
        Card {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(message)
            } actions: {
                actions
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}

extension EmptyCard where Actions == EmptyView {
    init(title: String, message: String, symbol: String = "tray") {
        self.init(title: title, message: message, symbol: symbol) { EmptyView() }
    }
}

/// AI 답변·프롬프트 글을 마크다운 일부(굵게, 코드, 링크)까지 살려 보여 준다.
enum RichText {
    static func inline(_ s: String, highlight: String? = nil) -> AttributedString {
        // 한국어 글의 "R1~R4" 같은 범위 표시가 취소선(~글자~)으로 바뀌지 않게, 홑 ~ 는 글자 그대로 둔다.
        let escaped = s.replacingOccurrences(of: #"(?<!~)~(?!~)"#, with: #"\~"#, options: .regularExpression)
        let parsed = (try? AttributedString(markdown: escaped, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        return mark(parsed, highlight)
    }

    /// 마크다운 해석 없이 글 그대로 + 검색어 강조.
    static func plain(_ s: String, highlight: String? = nil) -> AttributedString {
        mark(AttributedString(s), highlight)
    }

    /// 검색어가 나오는 곳마다 형광펜을 칠한다.
    static func mark(_ text: AttributedString, _ query: String?) -> AttributedString {
        guard let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty else { return text }
        var result = text
        var from = result.startIndex
        while from < result.endIndex,
              let range = result[from...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].swiftUI.backgroundColor = Color.searchHighlight
            from = range.upperBound
        }
        return result
    }

    /// 한 줄 미리보기. 검색어가 뒤쪽에 있으면 그 근처부터 보여 준다.
    static func snippet(_ s: String, around query: String?) -> String {
        guard let query = query?.trimmingCharacters(in: .whitespaces), !query.isEmpty,
              let hit = s.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return s }
        let offset = s.distance(from: s.startIndex, to: hit.lowerBound)
        guard offset > 40 else { return s }
        return "…" + s[s.index(hit.lowerBound, offsetBy: -20)...]
    }
}

extension String {
    func contains(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// 무한 스크롤: 목록 맨 아래에 두면, 보이는 순간 다음 묶음을 불러온다.
struct LoadMoreRow: View {
    var remaining: Int
    var load: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("%@개 더 불러오는 중…", Fmt.number(remaining))).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        // 화면을 그리는 도중에 상태를 바꾸지 않도록 한 박자 뒤에 부른다.
        .onAppear { DispatchQueue.main.async(execute: load) }
    }
}
