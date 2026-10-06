import Foundation
import HealthKit

/// Apple Health equivalent of Android's `HealthConnectManager`.
/// Produces the same `TodaySummary`, `HealthMetricDto` and `ExerciseSessionDto` shapes so the
/// server/web dashboard can't tell which platform the data came from.
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    /// Live snapshot of today for the Home dashboard.
    struct TodaySummary {
        var steps: Int = 0
        var activeKcal: Int? = nil
        var totalKcal: Int? = nil
        var activeMinutes: Int = 0
        var avgHr: Int? = nil
        var maxHr: Int? = nil
        var restingHr: Int? = nil
        var latestHr: Int? = nil
        var hourlyHr: [Int?] = Array(repeating: nil, count: 24)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var ids: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .restingHeartRate, .activeEnergyBurned, .basalEnergyBurned,
            .appleExerciseTime, .bodyMass, .bodyFatPercentage, .leanBodyMass, .vo2Max, .flightsClimbed,
            .oxygenSaturation, .respiratoryRate, .height, .bodyTemperature, .bloodGlucose,
            .bloodPressureSystolic, .bloodPressureDiastolic, .dietaryWater, .dietaryProtein,
            .dietaryCarbohydrates, .dietaryFatTotal, .distanceWalkingRunning
        ]
        ids.append(.distanceCycling)
        var set = Set<HKObjectType>(ids.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        set.insert(HKObjectType.workoutType())
        return set
    }

    /// Shows the Health permission sheet (no-op if already answered).
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            print("HealthKit auth failed: \(error)")
            return false
        }
    }

    // MARK: - Today

    func readToday() async -> TodaySummary? {
        guard isAvailable else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let now = Date()

        var s = TodaySummary()
        s.steps = Int(await sum(.stepCount, unit: .count(), from: start, to: now) ?? 0)
        let active = await sum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: now)
        let basal = await sum(.basalEnergyBurned, unit: .kilocalorie(), from: start, to: now)
        s.activeKcal = active.map { Int($0) }
        if active != nil || basal != nil { s.totalKcal = Int((active ?? 0) + (basal ?? 0)) }
        s.activeMinutes = Int(await sum(.appleExerciseTime, unit: .minute(), from: start, to: now) ?? 0)

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrSamples = await quantitySamples(.heartRate, from: start, to: now)
        var hourly = Array(repeating: [Double](), count: 24)
        var latest: (Date, Double)?
        var total = 0.0
        var maxV = 0.0
        for q in hrSamples {
            let v = q.quantity.doubleValue(for: bpm)
            hourly[cal.component(.hour, from: q.startDate)].append(v)
            if latest == nil || q.startDate > latest!.0 { latest = (q.startDate, v) }
            total += v
            maxV = max(maxV, v)
        }
        if !hrSamples.isEmpty {
            s.avgHr = Int(total / Double(hrSamples.count))
            s.maxHr = Int(maxV)
        }
        s.latestHr = latest.map { Int($0.1) }
        s.hourlyHr = hourly.map { $0.isEmpty ? nil : Int($0.reduce(0, +) / Double($0.count)) }
        let rhr = await quantitySamples(.restingHeartRate, from: cal.date(byAdding: .day, value: -1, to: start)!, to: now)
        s.restingHr = rhr.last.map { Int($0.quantity.doubleValue(for: bpm)) }
        return s
    }

    // MARK: - Daily metrics (last N days)

    func readHealthMetrics(days: Int = 30) async -> [HealthMetricDto] {
        guard isAvailable else { return [] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: end))!
        let bpm = HKUnit.count().unitDivided(by: .minute())

        async let steps = daily(.stepCount, .cumulativeSum, .count(), start, end)
        async let active = daily(.activeEnergyBurned, .cumulativeSum, .kilocalorie(), start, end)
        async let basal = daily(.basalEnergyBurned, .cumulativeSum, .kilocalorie(), start, end)
        async let exercise = daily(.appleExerciseTime, .cumulativeSum, .minute(), start, end)
        async let floors = daily(.flightsClimbed, .cumulativeSum, .count(), start, end)
        async let water = daily(.dietaryWater, .cumulativeSum, .fluidOunceUS(), start, end)
        async let protein = daily(.dietaryProtein, .cumulativeSum, .gram(), start, end)
        async let carbs = daily(.dietaryCarbohydrates, .cumulativeSum, .gram(), start, end)
        async let fat = daily(.dietaryFatTotal, .cumulativeSum, .gram(), start, end)
        async let hrAvg = daily(.heartRate, .discreteAverage, bpm, start, end)
        async let hrMax = daily(.heartRate, .discreteMax, bpm, start, end)
        async let rhr = daily(.restingHeartRate, .discreteAverage, bpm, start, end)
        async let weight = daily(.bodyMass, .discreteAverage, .pound(), start, end)
        async let bodyFat = daily(.bodyFatPercentage, .discreteAverage, .percent(), start, end)
        async let lean = daily(.leanBodyMass, .discreteAverage, .pound(), start, end)
        async let vo2 = daily(.vo2Max, .discreteAverage, HKUnit(from: "ml/kg*min"), start, end)
        async let spo2 = daily(.oxygenSaturation, .discreteAverage, .percent(), start, end)
        async let resp = daily(.respiratoryRate, .discreteAverage, bpm, start, end)
        async let height = daily(.height, .discreteAverage, .inch(), start, end)
        async let temp = daily(.bodyTemperature, .discreteAverage, .degreeCelsius(), start, end)
        async let glucose = daily(.bloodGlucose, .discreteAverage, HKUnit(from: "mg/dL"), start, end)
        async let sys = daily(.bloodPressureSystolic, .discreteAverage, .millimeterOfMercury(), start, end)
        async let dia = daily(.bloodPressureDiastolic, .discreteAverage, .millimeterOfMercury(), start, end)

        let (st, ac, ba, ex, fl) = await (steps, active, basal, exercise, floors)
        let (wa, pr, ca, fa) = await (water, protein, carbs, fat)
        let (ha, hm, rh, we, bf, le, vo) = await (hrAvg, hrMax, rhr, weight, bodyFat, lean, vo2)
        let (sp, re, he, te, gl, sy, di) = await (spo2, resp, height, temp, glucose, sys, dia)

        var out: [HealthMetricDto] = []
        var day = start
        while day <= end {
            let key = Self.dayKey(day)
            let total: Int? = (ac[key] != nil || ba[key] != nil) ? Int((ac[key] ?? 0) + (ba[key] ?? 0)) : nil
            var m = HealthMetricDto(date: key, steps: Int(st[key] ?? 0))
            m.avgHeartRate = ha[key].map { Int($0) }
            m.maxHeartRate = hm[key].map { Int($0) }
            m.restingHeartRate = rh[key].map { Int($0) }
            m.calories = total
            m.bmr = ba[key].map { Int($0) }
            m.activeCalories = ac[key].map { Int($0) }
            m.activeMinutes = ex[key].map { Int($0) }
            m.floorsClimbed = fl[key]
            m.weightLbs = we[key]
            m.bodyFatPercentage = bf[key].map { $0 * 100 }
            m.leanMassLbs = le[key]
            m.vo2Max = vo[key]
            m.oxygenSaturation = sp[key].map { $0 * 100 }
            m.respiratoryRate = re[key]
            m.heightInches = he[key]
            m.bodyTemperatureCelsius = te[key]
            m.bloodGlucose = gl[key]
            m.bloodPressureSystolic = sy[key]
            m.bloodPressureDiastolic = di[key]
            m.hydrationOunces = wa[key]
            m.proteinGrams = pr[key]
            m.carbsGrams = ca[key]
            m.fatGrams = fa[key]
            let hasAnything = m.steps > 0 || total != nil || m.avgHeartRate != nil || m.weightLbs != nil
            if hasAnything { out.append(m) }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }

    // MARK: - Workouts

    func readExerciseSessions(days: Int = 90) async -> [ExerciseSessionDto] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        var out: [ExerciseSessionDto] = []
        for w in workouts {
            let hr = await quantitySamples(.heartRate, from: w.startDate, to: w.endDate)
            let samples: [HrSample] = hr.map {
                HrSample(timeOffsetSec: max(0, Int($0.startDate.timeIntervalSince(w.startDate))), bpm: Int($0.quantity.doubleValue(for: bpm)))
            }
            let bpms = samples.map { $0.bpm }
            var kcal: Int?
            if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
               let q = w.statistics(for: type)?.sumQuantity() {
                kcal = Int(q.doubleValue(for: .kilocalorie()))
            }
            var dto = ExerciseSessionDto(
                id: w.uuid.uuidString,
                startTime: Int64(w.startDate.timeIntervalSince1970 * 1000),
                endTime: Int64(w.endDate.timeIntervalSince1970 * 1000),
                durationMinutes: Int(w.duration / 60),
                exerciseType: Self.typeName(w.workoutActivityType)
            )
            dto.avgHeartRate = bpms.isEmpty ? nil : bpms.reduce(0, +) / bpms.count
            dto.peakHeartRate = bpms.max()
            dto.calories = kcal
            dto.distanceMeters = w.totalDistance?.doubleValue(for: .meter())
            dto.hrSamples = samples.isEmpty ? nil : samples
            out.append(dto)
        }
        return out
    }

    /// Same display names Android sends, so the web groups sessions identically.
    static func typeName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength Training"
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing, .stairs: return "Stair Climber"
        case .downhillSkiing, .crossCountrySkiing: return "Skiing"
        case .crossTraining: return "Cross Training"
        default: return "Workout"
        }
    }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    // MARK: - Query helpers

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func quantitySamples(_ id: HKQuantityTypeIdentifier, from: Date, to: Date) async -> [HKQuantitySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        return await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
    }

    /// Per-day statistic keyed by "yyyy-MM-dd".
    private func daily(_ id: HKQuantityTypeIdentifier, _ option: HKStatisticsOptions, _ unit: HKUnit, _ start: Date, _ end: Date) async -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        return await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: pred, options: option,
                anchorDate: Calendar.current.startOfDay(for: start), intervalComponents: DateComponents(day: 1)
            )
            q.initialResultsHandler = { _, results, _ in
                var map: [String: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let quantity: HKQuantity?
                    switch option {
                    case .cumulativeSum: quantity = stats.sumQuantity()
                    case .discreteMax: quantity = stats.maximumQuantity()
                    default: quantity = stats.averageQuantity()
                    }
                    if let quantity { map[Self.dayKey(stats.startDate)] = quantity.doubleValue(for: unit) }
                }
                cont.resume(returning: map)
            }
            store.execute(q)
        }
    }
}
