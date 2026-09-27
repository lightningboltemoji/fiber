import AppKit
import FiberBridge

@objc @implementation extension FiberTextRun {
  let range: NSRange
  let style: FiberTextStyle

  @objc(initWithRange:style:)
  init(range: NSRange, style: FiberTextStyle) {
    self.range = range
    self.style = style
    super.init()
  }
}

@objc @implementation extension FiberSuggestion {
  let kind: FiberSuggestionKind
  let contents: String
  let contentsRuns: [FiberTextRun]
  let detail: String
  let detailRuns: [FiberTextRun]
  let favicon: NSImage?
  let header: String
  let keywordLabel: String
  let actionTitles: [String]
  let isRemovable: Bool
  let isHidden: Bool

  @objc(
    initWithKind:contents:contentsRuns:detail:detailRuns:favicon:header:
    keywordLabel:actionTitles:removable:hidden:
  )
  init(
    kind: FiberSuggestionKind, contents: String, contentsRuns: [FiberTextRun],
    detail: String, detailRuns: [FiberTextRun], favicon: NSImage?,
    header: String, keywordLabel: String, actionTitles: [String],
    removable: Bool, hidden: Bool
  ) {
    self.kind = kind
    self.contents = contents
    self.contentsRuns = contentsRuns
    self.detail = detail
    self.detailRuns = detailRuns
    self.favicon = favicon
    self.header = header
    self.keywordLabel = keywordLabel
    self.actionTitles = actionTitles
    self.isRemovable = removable
    self.isHidden = hidden
    super.init()
  }
}
