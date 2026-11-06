import AppKit
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var model: UsageViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .padding(16)
        .frame(width: 340)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot = model.snapshot {
                // Show only the limits this plan actually reports.
                if let session = snapshot.session {
                    LimitCard(title: "Current session (5h)", reading: session, now: now)
                }
                if let weekly = snapshot.weekly {
                    LimitCard(title: "Weekly · all models", reading: weekly, now: now)
                }

                if !snapshot.scoped.isEmpty {
                    scopedSection(snapshot.scoped, now: now)
                }

                if let extra = snapshot.extraUsage {
                    extraUsageRow(extra)
                }
            } else if model.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading your Claude usage…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            settingsSection
            Divider()
            footer(now: now)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude usage").font(.headline)
                if let plan = model.snapshot?.planName {
                    Text(plan).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Refresh usage")
        }
    }

    private func scopedSection(_ readings: [LimitReading], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(readings) { reading in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(reading.title).font(.subheadline)
                        Spacer()
                        Text("\(Int(reading.remainingPercent.rounded()))% left")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    UsageBar(remainingFraction: reading.remainingPercent / 100,
                             level: UsageLevel(remainingPercent: reading.remainingPercent),
                             height: 6)
                    if let resetsAt = reading.resetsAt, reading.usedPercent > 0 {
                        Text("Resets \(countdown(to: resetsAt, now: now))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(reading.isActive ? 1 : 0.6)
            }
        }
    }

    private func extraUsageRow(_ extra: ExtraUsageReading) -> some View {
        HStack {
            Label("Extra usage", systemImage: "creditcard")
                .font(.subheadline)
            Spacer()
            Group {
                if let limit = extra.limit {
                    Text("\(money(extra.used, extra.currency)) of \(money(limit, extra.currency))")
                } else {
                    Text("\(money(extra.used, extra.currency)) spent")
                }
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Menu bar style", selection: $model.gaugeStyle) {
                ForEach(GaugeStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            // Only offer a choice when the plan has more than one limit.
            if model.availableSources.count > 1 {
                Picker("Gauge tracks", selection: $model.gaugeSource) {
                    ForEach(model.availableSources) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.menu)
            }

            Toggle("Show percentage in menu bar", isOn: $model.showPercentage)

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
        }
        .font(.subheadline)
    }

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let snapshot = model.snapshot {
                HStack(spacing: 6) {
                    if model.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: model.errorMessage == nil ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                            .foregroundStyle(model.errorMessage == nil ? .green : .orange)
                    }
                    Text("Updated \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Open usage page") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency))
    }
}

// MARK: - Components

private struct LimitCard: View {
    let title: String
    let reading: LimitReading
    let now: Date

    var body: some View {
        let remaining = reading.remainingPercent
        let level = UsageLevel(remainingPercent: remaining)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(reading.usedPercent.rounded()))% used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(Int(remaining.rounded()))%")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("left").foregroundStyle(.secondary)
                Spacer()
                if let resetsAt = reading.resetsAt {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Resets \(countdown(to: resetsAt, now: now))")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                        Text(resetsAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            UsageBar(remainingFraction: remaining / 100, level: level, height: 8)
        }
    }
}

/// A capsule progress bar matching the menu-bar "Bar" style.
struct UsageBar: View {
    let remainingFraction: Double
    let level: UsageLevel
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, remainingFraction))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(level.color)
                    .frame(width: fraction > 0 ? max(height, geometry.size.width * fraction) : 0)
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(Int((remainingFraction * 100).rounded())) percent left")
    }
}

extension UsageLevel {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}

func countdown(to date: Date, now: Date = Date()) -> String {
    let remaining = Int(max(0, date.timeIntervalSince(now)))
    let days = remaining / 86_400
    let hours = (remaining % 86_400) / 3_600
    let minutes = (remaining % 3_600) / 60
    if days > 0 { return "in \(days)d \(hours)h" }
    if hours > 0 { return "in \(hours)h \(minutes)m" }
    if minutes > 0 { return "in \(minutes)m" }
    return "now"
}
