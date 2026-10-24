import SwiftUI

struct QTOHomeSummaryView: View {
    let projectCount: Int
    let scanCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("المسح • المخططات • حصر الكميات", systemImage: "square.3.layers.3d")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                metric("المشروعات", count: projectCount, icon: "folder.fill")
                metric("المسحات", count: scanCount, icon: "viewfinder")
            }
            Text("أنشئ مشروعًا، امسح المكان، ثم راجع القياسات والعناصر قبل التصدير.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private func metric(_ title: String, count: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(count, format: .number).font(.title2.bold()).monospacedDigit()
            Label(title, systemImage: icon).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct QTOQuantityQualityView: View {
    let summary: RoomTakeoffSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if summary.polygonFloorCount > 0 {
                Label("\(summary.polygonFloorCount) أرضية محسوبة من مضلع المسح الفعلي.", systemImage: "checkmark.seal")
            }
            if summary.rectangularFloorEstimateCount > 0 {
                Label("\(summary.rectangularFloorEstimateCount) أرضية بتقدير مستطيل؛ المسحات القديمة تحتاج إعادة مسح للحصول على حدود المضلع.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if summary.unassignedOpeningCount > 0 {
                Label("\(summary.unassignedOpeningCount) فتحة غير مرتبطة لم تُخصم من الحوائط.", systemImage: "link.badge.plus")
                    .foregroundStyle(.orange)
            }
            Label("الأسقف تقدير من مساحة الأرضيات، والحوائط من الطول × الارتفاع. راجع المقاسات ميدانيًا قبل التنفيذ.",
                  systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct QTOScanStatusView: View {
    let wallCount: Int
    let openingCount: Int
    let guidance: String
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 16) {
                Label("حوائط: \(wallCount)", systemImage: "rectangle.3.group")
                Label("فتحات: \(openingCount)", systemImage: "door.left.hand.open")
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            Text(guidance).font(.caption).lineLimit(compact ? 1 : 3)
                .fixedSize(horizontal: false, vertical: !compact)
        }
        .padding(compact ? 6 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
