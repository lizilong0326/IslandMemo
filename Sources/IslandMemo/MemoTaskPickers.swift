import SwiftUI

// Shared by the main memo editor and the selection/clipboard capture window.
struct PriorityPickerPopover: View {
    @Binding var selection: TaskPriority
    @ObservedObject var settings: AppSettingsStore
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    selection = priority
                    onSelect()
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(settings.priorityColor(for: priority)).frame(width: 11, height: 11)
                        Text(settings.priorityName(for: priority))
                        Spacer()
                        if selection == priority {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(width: 150)
    }
}
struct DueDatePickerPopover: View {
    @Binding var selection: Date
    let showsClear: Bool
    let onClear: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("结束时间").font(.headline)

            HStack(spacing: 8) {
                presetButton("今天 18:00", date: todayAt(hour: 18))
                presetButton("明天 09:00", date: tomorrowAt(hour: 9))
                presetButton("一周后", date: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
            }

            WideCalendarPicker(selection: $selection)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Text("时间").foregroundStyle(.secondary)
                Picker("小时", selection: hourBinding) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 72)
                Text(":").foregroundStyle(.secondary)
                Picker("分钟", selection: minuteBinding) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 72)
                Spacer()
            }

            HStack {
                if showsClear {
                    Button("清除时间", role: .destructive, action: onClear)
                }
                Spacer()
                Button("保存", action: onSave).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 410)
    }

    private func presetButton(_ title: String, date: Date) -> some View {
        Button(title) { selection = date }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.hour, from: selection) },
            set: { hour in
                selection = Calendar.current.date(bySettingHour: hour, minute: minuteBinding.wrappedValue, second: 0, of: selection) ?? selection
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.minute, from: selection) },
            set: { minute in
                selection = Calendar.current.date(bySettingHour: hourBinding.wrappedValue, minute: minute, second: 0, of: selection) ?? selection
            }
        )
    }

    private func todayAt(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }

    private func tomorrowAt(hour: Int) -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

private struct WideCalendarPicker: View {
    @Binding var selection: Date
    @State private var displayedMonth: Date
    private let calendar = Calendar.current
    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    init(selection: Binding<Date>) {
        _selection = selection
        let components = Calendar.current.dateComponents([.year, .month], from: selection.wrappedValue)
        _displayedMonth = State(initialValue: Calendar.current.date(from: components) ?? .now)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(monthTitle).font(.headline)
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Button { displayedMonth = startOfMonth(.now) } label: { Circle().frame(width: 7, height: 7) }
                    .buttonStyle(.borderless).help("回到今天")
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<cellCount, id: \.self) { index in
                    if let date = dateForCell(index) {
                        Button { select(date) } label: {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .foregroundStyle(calendar.isDate(date, inSameDayAs: selection) ? .white : .primary)
                                .background {
                                    if calendar.isDate(date, inSameDayAs: selection) {
                                        RoundedRectangle(cornerRadius: 7).fill(.blue)
                                    } else if calendar.isDateInToday(date) {
                                        RoundedRectangle(cornerRadius: 7).stroke(.blue.opacity(0.8), lineWidth: 1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: selection) { newValue in
            displayedMonth = startOfMonth(newValue)
        }
    }

    private var monthTitle: String {
        let values = calendar.dateComponents([.year, .month], from: displayedMonth)
        return "\(values.year ?? 0)年 \(values.month ?? 0)月"
    }

    private var leadingEmptyDays: Int {
        max(0, calendar.component(.weekday, from: displayedMonth) - 1)
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    private var cellCount: Int {
        Int(ceil(Double(leadingEmptyDays + daysInMonth) / 7.0)) * 7
    }

    private func dateForCell(_ index: Int) -> Date? {
        let day = index - leadingEmptyDays + 1
        guard day >= 1, day <= daysInMonth else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: displayedMonth)
    }

    private func select(_ date: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: selection)
        selection = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
    }

    private func moveMonth(_ offset: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
