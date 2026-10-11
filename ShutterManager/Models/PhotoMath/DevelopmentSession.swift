//
//  DevelopmentSession.swift
//  ShutterManager
//
//  The timing behind the film development timer: steps run one after another, each started by
//  hand (you pour between them), with agitation cues inside each step. Foundation-only; times come
//  from wall-clock dates, so it stays right while the app is in the background.
//

import Foundation

/// When to agitate during a step.
struct AgitationPattern: Equatable, Codable {
    /// Agitate continuously for this long at the start of the step.
    var initialSeconds: Double
    /// Then agitate at every multiple of this many seconds from the start of the step (0 = never),
    /// skipping marks that fall within or at the end of the initial period…
    var intervalSeconds: Double
    /// …for this long each time.
    var durationSeconds: Double

    static let none = AgitationPattern(initialSeconds: 0, intervalSeconds: 0, durationSeconds: 0)
    /// Ilford (HP5 Plus datasheet, spiral tanks): four inversions in the first 10 s, then four
    /// in the first 10 s of each further minute.
    static let everyMinute = AgitationPattern(initialSeconds: 10, intervalSeconds: 60, durationSeconds: 10)
    /// Kodak (Tri-X datasheet F-4017, small tanks): 5–7 inversions in 5 s, repeated at 30-second
    /// intervals.
    static let everyThirtySeconds = AgitationPattern(initialSeconds: 5, intervalSeconds: 30, durationSeconds: 5)

    var isNone: Bool { initialSeconds <= 0 && (intervalSeconds <= 0 || durationSeconds <= 0) }

    /// Whether `elapsed` seconds into the step falls in an agitation period.
    func isAgitating(at elapsed: Double) -> Bool {
        guard elapsed >= 0 else { return false }
        if elapsed < initialSeconds { return true }
        guard intervalSeconds > 0, durationSeconds > 0 else { return false }
        let mark = (elapsed / intervalSeconds).rounded(.down) * intervalSeconds
        return countsAsMark(mark) && elapsed - mark < durationSeconds
    }

    /// Times (seconds into the step) when agitation periods start, before `stepDuration`.
    func agitationStarts(within stepDuration: Double) -> [Double] {
        var starts: [Double] = initialSeconds > 0 ? [0] : []
        guard intervalSeconds > 0, durationSeconds > 0, stepDuration.isFinite else { return starts }
        var multiple = 1.0
        while multiple * intervalSeconds < stepDuration {
            let mark = multiple * intervalSeconds
            if countsAsMark(mark) { starts.append(mark) }
            multiple += 1
        }
        return starts
    }

    /// A mark within the initial period, or right at its end, would only extend it: with 30 s of
    /// initial agitation and a 30 s interval, the next agitation is at 1:00, not straight on at 0:30.
    private func countsAsMark(_ mark: Double) -> Bool {
        mark > 0 && mark > initialSeconds + 1e-6
    }
}

/// One step as the timer runs it.
struct DevelopmentStepPlan: Equatable, Identifiable {
    var id = UUID()
    var name: String
    /// Seconds.
    var duration: Double
    var agitation: AgitationPattern
}

/// A development run: which step is current, and whether its clock is running.
struct DevelopmentSession: Equatable {
    enum Phase: Equatable {
        /// The current step hasn't been started.
        case ready
        /// Counting down. `agitating` is whether to agitate now.
        case running(remaining: Double, agitating: Bool)
        case paused(remaining: Double)
        /// The step's time is up; waiting for the next step to be started.
        case stepComplete
        /// Every step is done.
        case finished
    }

    let steps: [DevelopmentStepPlan]
    private(set) var currentIndex = 0
    /// When the running stretch of the current step began.
    private(set) var runningSince: Date?
    /// Seconds of the current step already run before `runningSince`.
    private(set) var elapsedBefore: Double = 0

    init(steps: [DevelopmentStepPlan]) {
        self.steps = steps.filter { $0.duration > 0 }
    }

    var currentStep: DevelopmentStepPlan? { steps.indices.contains(currentIndex) ? steps[currentIndex] : nil }
    var isFinished: Bool { currentIndex >= steps.count }
    var isRunning: Bool { runningSince != nil }

    func elapsed(at date: Date) -> Double {
        elapsedBefore + (runningSince.map { max(date.timeIntervalSince($0), 0) } ?? 0)
    }

    func phase(at date: Date) -> Phase {
        guard let step = currentStep else { return .finished }
        let elapsed = elapsed(at: date)
        let remaining = step.duration - elapsed
        if remaining <= 0 { return .stepComplete }
        if runningSince != nil {
            return .running(remaining: remaining, agitating: step.agitation.isAgitating(at: elapsed))
        }
        return elapsed > 0 ? .paused(remaining: remaining) : .ready
    }

    /// Starts or resumes the current step.
    mutating func start(at date: Date) {
        guard !isFinished, runningSince == nil, phase(at: date) != .stepComplete else { return }
        runningSince = date
    }

    mutating func pause(at date: Date) {
        guard runningSince != nil else { return }
        elapsedBefore = elapsed(at: date)
        runningSince = nil
    }

    /// Moves to the next step, ready to start. Works before the time is up too (a step can be
    /// cut short).
    mutating func advance() {
        guard !isFinished else { return }
        currentIndex += 1
        runningSince = nil
        elapsedBefore = 0
    }

    /// Back to the start of the current step.
    mutating func restartStep() {
        runningSince = nil
        elapsedBefore = 0
    }

    /// When the running step ends, and when each of its remaining agitation periods starts, as
    /// dates: what the timer schedules notifications for. Empty unless running.
    func upcomingCues(after date: Date) -> (agitations: [Date], stepEnd: Date?) {
        guard let step = currentStep, let since = runningSince else { return ([], nil) }
        let stepStart = since.addingTimeInterval(-elapsedBefore)
        let elapsed = elapsed(at: date)
        let agitations = step.agitation.agitationStarts(within: step.duration)
            .filter { $0 > elapsed }
            .map { stepStart.addingTimeInterval($0) }
        return (agitations, stepStart.addingTimeInterval(step.duration))
    }

    /// Total time of every step.
    var totalDuration: Double { steps.reduce(0) { $0 + $1.duration } }
}
