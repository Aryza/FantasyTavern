import SwiftUI
import AppKit
import EntityModel
import WorldStore

struct TimelineView: View {
    @Environment(WorldSession.self) private var session
    @Environment(TabsModel.self) private var tabs

    @State private var granularity: TimelineGranularity = .decade
    @State private var wheelAccumulator: CGFloat = 0
    @State private var panOffset: Double = 0
    @State private var hoverYear: Int? = nil
    @State private var popoverEventID: EntityID? = nil
    @State private var createAtYear: Int? = nil
    @State private var scrollMonitor: Any?

    private let viewportWidth: Double = 2000   // logical width before user pan
    private let rowHeight: Double = 80

    var body: some View {
        GeometryReader { geo in
            let range = autoRange()
            let width = max(viewportWidth, geo.size.width)
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    eraBands(range: range, width: width, height: geo.size.height)
                    axis(range: range, width: width)
                    eventDots(range: range, width: width)
                }
                .frame(width: width, height: geo.size.height)
                .contentShape(Rectangle())
                .background(TimelineWheelCatcher { delta in handleWheel(delta) })
                .onTapGesture { location in
                    let year = TimelineGeometry.year(atX: location.x, range: range, width: width)
                    createAtYear = year
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .alert("Create event at year \(createAtYear ?? 0)?",
               isPresented: Binding(get: { createAtYear != nil }, set: { if !$0 { createAtYear = nil } })) {
            Button("Create") {
                if let year = createAtYear { createEvent(year: year) }
                createAtYear = nil
            }
            Button("Cancel", role: .cancel) { createAtYear = nil }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Zoom", selection: $granularity) {
                    Text("Year").tag(TimelineGranularity.year)
                    Text("Decade").tag(TimelineGranularity.decade)
                    Text("Century").tag(TimelineGranularity.century)
                }
                .pickerStyle(.segmented)
                Button("Fit") { fitToEvents() }
            }
        }
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
    }

    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            handleWheel(event.scrollingDeltaY)
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - data

    private var events: [(entity: Entity, year: Int)] {
        let raw = session.store?.entities(of: .timelineEvent) ?? []
        return raw.compactMap { e in
            guard case .string(let s)? = e.fields["date"] ?? nil,
                  let y = TimelineGeometry.year(fromDateString: s)
            else { return nil }
            return (e, y)
        }.sorted { $0.year < $1.year }
    }

    private func autoRange() -> ClosedRange<Int> {
        var ys = events.map(\.year)
        let calEras = session.store?.calendar.eras ?? []
        ys.append(contentsOf: calEras.map(\.start))
        ys.append(contentsOf: calEras.map(\.end))
        guard let lo = ys.min(), let hi = ys.max(), lo < hi else { return -100...100 }
        let pad = max(10, (hi - lo) / 10)
        return (lo - pad)...(hi + pad)
    }

    // MARK: - drawing

    private func eraBands(range: ClosedRange<Int>, width: Double, height: Double) -> some View {
        ForEach(session.store?.calendar.eras ?? [], id: \.id) { era in
            let x1 = TimelineGeometry.x(forYear: era.start, range: range, width: width)
            let x2 = TimelineGeometry.x(forYear: era.end,   range: range, width: width)
            let bandWidth = max(0, x2 - x1)
            Rectangle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: bandWidth, height: height)
                .offset(x: x1)
                .overlay(alignment: .topLeading) {
                    Text(era.name)
                        .font(.caption)
                        .padding(4)
                        .background(.regularMaterial)
                        .offset(x: x1 + 4, y: 4)
                }
        }
    }

    private func axis(range: ClosedRange<Int>, width: Double) -> some View {
        let step = TimelineGeometry.tickStep(granularity)
        let firstTick = ((range.lowerBound / step) * step)
        let ticks = stride(from: firstTick, through: range.upperBound, by: step)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: rowHeight))
                path.addLine(to: CGPoint(x: width, y: rowHeight))
            }
            .stroke(Color.secondary, lineWidth: 1)

            ForEach(Array(ticks), id: \.self) { year in
                let x = TimelineGeometry.x(forYear: year, range: range, width: width)
                VStack(spacing: 2) {
                    Rectangle().fill(Color.secondary).frame(width: 1, height: 8)
                    Text("\(year)").font(.caption2).foregroundStyle(.secondary)
                }
                .offset(x: x - 10, y: rowHeight - 4)
            }
        }
    }

    private func eventDots(range: ClosedRange<Int>, width: Double) -> some View {
        ForEach(events.map(\.entity), id: \.id) { entity in
            let year = TimelineGeometry.year(fromDateString: dateString(for: entity)) ?? 0
            let x = TimelineGeometry.x(forYear: year, range: range, width: width)
            Button {
                popoverEventID = entity.id
            } label: {
                Circle().fill(Color.accentColor).frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .offset(x: x - 6, y: rowHeight - 6)
            .popover(isPresented: Binding(
                get: { popoverEventID == entity.id },
                set: { if !$0 { popoverEventID = nil } }
            )) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entity.name).font(.headline)
                    Text("Year \(year)").font(.caption).foregroundStyle(.secondary)
                    if !entity.body.isEmpty {
                        Text(entity.body.prefix(200)).font(.body)
                    }
                    Button("Open in tab") {
                        tabs.open(.entity(entity.id))
                        popoverEventID = nil
                    }
                }
                .padding(12)
                .frame(width: 320)
            }
        }
    }

    private func dateString(for entity: Entity) -> String {
        if case .string(let s)? = entity.fields["date"] { return s }
        return ""
    }

    private func createEvent(year: Int) {
        guard let entity = try? session.createEntity(type: .timelineEvent, name: "Year \(year)") else { return }
        var updated = entity
        updated.fields["date"] = .string(String(year))
        try? session.save(updated)
        tabs.open(.entity(updated.id))
    }

    // MARK: - zoom

    private func handleWheel(_ delta: CGFloat) {
        wheelAccumulator += delta
        let threshold: CGFloat = 8 // small swipes shouldn't change zoom
        if wheelAccumulator > threshold {
            zoomIn(); wheelAccumulator = 0
        } else if wheelAccumulator < -threshold {
            zoomOut(); wheelAccumulator = 0
        }
    }

    private func zoomIn() {
        switch granularity {
        case .century: granularity = .decade
        case .decade:  granularity = .year
        case .year:    break
        }
    }

    private func zoomOut() {
        switch granularity {
        case .year:    granularity = .decade
        case .decade:  granularity = .century
        case .century: break
        }
    }

    private func fitToEvents() {
        let years = events.map(\.year)
        let span = (years.max() ?? 0) - (years.min() ?? 0)
        granularity = TimelineGeometry.fittedGranularity(forSpan: span)
    }
}
