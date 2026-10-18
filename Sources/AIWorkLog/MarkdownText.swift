import SwiftUI

/// AI 답변과 메모에 흔한 마크다운(제목, 목록, 코드 블록, 인용, 표)을 가볍게 그린다.
struct MarkdownText: View {
    var text: String
    /// 바로 바깥이 ScrollView 이고 글이 아주 길 때: 보이는 블록만 그린다.
    var lazy = false
    /// 형광펜을 칠할 검색어.
    var highlight: String? = nil

    private enum Block: Hashable {
        case heading(Int, String)
        case bullet(Int, String)
        case numbered(String, String)
        case quote(String)
        case code(String)
        case table(String)
        case paragraph(String)
        case rule
    }

    var body: some View {
        let blocks = Array(Self.parse(text).enumerated())
        Group {
            if lazy {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(blocks, id: \.offset) { _, block in view(for: block) }
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(blocks, id: \.offset) { _, block in view(for: block) }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            Text(RichText.inline(s, highlight: highlight))
                .font(level <= 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .bullet(let indent, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(indent > 0 ? "◦" : "•").foregroundStyle(.secondary)
                Text(RichText.inline(s, highlight: highlight))
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).foregroundStyle(.secondary).monospacedDigit()
                Text(RichText.inline(s, highlight: highlight))
            }
        case .quote(let s):
            Text(RichText.inline(s, highlight: highlight))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 2) }
        case .code(let s), .table(let s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s).font(.system(.callout, design: .monospaced)).fixedSize()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        case .paragraph(let s):
            Text(RichText.inline(s, highlight: highlight)).fixedSize(horizontal: false, vertical: true)
        case .rule:
            Divider()
        }
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        var table: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        func flushTable() {
            if !table.isEmpty { blocks.append(.table(table.joined(separator: "\n"))); table = [] }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flushParagraph(); flushTable(); code = [] }
                continue
            }
            if code != nil { code?.append(raw); continue }

            if line.hasPrefix("|") {
                flushParagraph()
                // 표의 구분선(|---|---|)은 빼고 칸만 남긴다.
                if line.replacingOccurrences(of: "|", with: "").allSatisfy({ "-: ".contains($0) }) { continue }
                table.append(line)
                continue
            }
            flushTable()

            if line.isEmpty { flushParagraph(); continue }
            if line == "---" || line == "***" { flushParagraph(); blocks.append(.rule); continue }

            if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"), line[hashes] == " " {
                flushParagraph()
                blocks.append(.heading(line.distance(from: line.startIndex, to: hashes), String(line[hashes...]).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix("> ") { flushParagraph(); blocks.append(.quote(String(line.dropFirst(2)))); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                let indent = raw.prefix(while: { $0 == " " }).count / 2
                blocks.append(.bullet(indent, String(line.dropFirst(2))))
                continue
            }
            if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }), dot > line.startIndex,
               line[..<dot].allSatisfy(\.isNumber), line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                flushParagraph()
                blocks.append(.numbered(String(line[...dot]), String(line[line.index(dot, offsetBy: 2)...])))
                continue
            }
            paragraph.append(line)
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flushTable()
        flushParagraph()
        return blocks
    }
}

/// 긴 글은 접어 두고 "더 보기"로 편다.
struct Collapsible<Content: View>: View {
    var isLong: Bool
    var collapsedHeight: CGFloat = 180
    @ViewBuilder var content: Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
                .frame(maxHeight: isLong && !expanded ? collapsedHeight : nil, alignment: .top)
                .clipped()
                .mask {
                    if isLong && !expanded {
                        LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle()
                    }
                }
            if isLong {
                Button(expanded ? "접기" : "더 보기") { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

extension String {
    var looksLong: Bool { count > 700 || components(separatedBy: "\n").count > 12 }
}
