import WidgetKit
import SwiftUI
import Charts
import AppIntents

// MARK: - 1. Shared Day Offset & Local Cache
struct ForecastWindowStore {
    static let dayOffsetKey = "rain_forecast_day_offset"
    static let cacheDataKey = "rain_forecast_cached_points"
    static let maxDays = 3 // 0 = Today, 1 = Tomorrow, 2 = Day +2, 3 = Day +3

    static var currentDayOffset: Int {
        get { UserDefaults.standard.integer(forKey: dayOffsetKey) }
        set { UserDefaults.standard.set(newValue, forKey: dayOffsetKey) }
    }

    static func saveCache(_ points: [RainPoint]) {
        if let encoded = try? JSONEncoder().encode(points) {
            UserDefaults.standard.set(encoded, forKey: cacheDataKey)
        }
    }

    static func loadCache() -> [RainPoint] {
        guard let data = UserDefaults.standard.data(forKey: cacheDataKey),
              let decoded = try? JSONDecoder().decode([RainPoint].self, from: data) else {
            return []
        }
        return decoded
    }
}

// MARK: - 2. Interactive AppIntents (< and > Day Buttons)
struct ShiftForecastForwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Day"

    func perform() async throws -> some IntentResult {
        let next = ForecastWindowStore.currentDayOffset + 1
        ForecastWindowStore.currentDayOffset = min(next, ForecastWindowStore.maxDays)
        return .result()
    }
}

struct ShiftForecastBackwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Day"

    func perform() async throws -> some IntentResult {
        let prev = ForecastWindowStore.currentDayOffset - 1
        ForecastWindowStore.currentDayOffset = max(prev, 0)
        return .result()
    }
}

// MARK: - 3. Open-Meteo Data Models & Fetcher
struct RainPoint: Identifiable, Codable {
    var id: Date { date }
    let date: Date
    let probability: Int
}

struct OpenMeteoResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let precipitation_probability: [Int]
    }
    let hourly: Hourly
}

struct WeatherService {
    // San Francisco coordinates
    static func fetchFourDayRain(lat: Double = 37.7749, lon: Double = -122.4194) async -> [RainPoint] {
        // Fetch 4 full days (96 hours) starting from midnight today
        let urlString = "https://open-meteo.com\(lat)&longitude=\(lon)&hourly=precipitation_probability&forecast_days=4&timezone=auto"
        guard let url = URL(string: urlString) else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

            let points: [RainPoint] = zip(decoded.hourly.time, decoded.hourly.precipitation_probability).compactMap { timeStr, prob in
                guard let date = formatter.date(from: timeStr) else { return nil }
                return RainPoint(date: date, probability: prob)
            }

            if !points.isEmpty {
                ForecastWindowStore.saveCache(points)
            }
            return points
        } catch {
            return ForecastWindowStore.loadCache()
        }
    }
}

// MARK: - 4. Timeline Provider
struct RainEntry: TimelineEntry {
    let date: Date
    let allPoints: [RainPoint]
    let dayOffset: Int
}

struct RainTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RainEntry {
        RainEntry(date: .now, allPoints: sampleData(), dayOffset: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (RainEntry) -> Void) {
        let cached = ForecastWindowStore.loadCache()
        completion(RainEntry(
            date: .now,
            allPoints: cached.isEmpty ? sampleData() : cached,
            dayOffset: ForecastWindowStore.currentDayOffset
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RainEntry>) -> Void) {
        Task {
            let fetched = await WeatherService.fetchFourDayRain()
            let points = fetched.isEmpty ? sampleData() : fetched
            let entry = RainEntry(
                date: .now,
                allPoints: points,
                dayOffset: ForecastWindowStore.currentDayOffset
            )

            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func sampleData() -> [RainPoint] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return (0..<96).map { hour in
            RainPoint(
                date: Calendar.current.date(byAdding: .hour, value: hour, to: startOfDay)!,
                probability: Int.random(in: 0...80)
            )
        }
    }
}

// MARK: - 5. Widget SwiftUI View
struct RainWidgetView: View {
    var entry: RainEntry

    private var calendar: Calendar { Calendar.current }

    // Midnight-to-midnight bounds for the selected day
    private var dayBounds: (start: Date, end: Date) {
        let todayStart = calendar.startOfDay(for: entry.date)
        let start = calendar.date(byAdding: .day, value: entry.dayOffset, to: todayStart)!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    // Filter points to the selected day AND only from the current hour forward
    private var visiblePoints: [RainPoint] {
        let bounds = dayBounds
        let currentHourFloor = calendar.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
        return entry.allPoints.filter { point in
            point.date >= bounds.start &&
            point.date <= bounds.end &&
            point.date >= currentHourFloor
        }
    }

    // Header label: "TODAY" for day 0, otherwise uppercase weekday (e.g., "SUNDAY")
    private var dayLabel: String {
        if entry.dayOffset == 0 {
            return "TODAY"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: dayBounds.start).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Day Label + Larger < > Controls
            HStack {
                Text(dayLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 8) {
                    Button(intent: ShiftForecastBackwardIntent()) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.bold())
                            .frame(width: 36, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.dayOffset <= 0)

                    Button(intent: ShiftForecastForwardIntent()) {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.bold())
                            .frame(width: 36, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.dayOffset >= ForecastWindowStore.maxDays)
                }
            }

            // Midnight-to-Midnight Line Chart
            Chart(visiblePoints) { point in
                LineMark(
                    x: .value("Hour", point.date),
                    y: .value("Chance", point.probability)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.gray.opacity(0.45), .blue],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
            .chartXScale(domain: dayBounds.start...dayBounds.end)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let intVal = value.as(Int.self) {
                            Text("\(intVal)%").font(.system(size: 9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
                        .font(.system(size: 9))
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - 6. Widget Configuration
struct RainWidget: Widget {
    let kind: String = "RainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RainTimelineProvider()) { entry in
            RainWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Rain Forecast")
        .description("Day-by-day hourly precipitation probability graph.")
        .supportedFamilies([.systemMedium])
    }
}
