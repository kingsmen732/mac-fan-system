import Foundation
import WidgetKit

struct FanRPMEntry: TimelineEntry {
    let date: Date
    let payload: FanWidgetEntryData
}

struct FanRPMProvider: TimelineProvider {
    func placeholder(in context: Context) -> FanRPMEntry {
        FanRPMEntry(
            date: .now,
            payload: FanDataStore.load()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FanRPMEntry) -> Void) {
        let payload = FanDataStore.load()
        completion(FanRPMEntry(date: payload.timestamp, payload: payload))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FanRPMEntry>) -> Void) {
        let payload = FanDataStore.load()
        let entry = FanRPMEntry(date: payload.timestamp, payload: payload)
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}
