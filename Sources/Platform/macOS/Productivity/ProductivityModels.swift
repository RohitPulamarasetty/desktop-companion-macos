import Foundation
import Core

/// One day of the last-7-days charts.
public struct DayStat: Equatable {
    public var label: String
    public var tasks: Int
    public var focusMinutes: Int
    public var water: Int
    public var activeMinutes: Int
    public init(label: String, tasks: Int = 0, focusMinutes: Int = 0, water: Int = 0, activeMinutes: Int = 0) {
        self.label = label
        self.tasks = tasks
        self.focusMinutes = focusMinutes
        self.water = water
        self.activeMinutes = activeMinutes
    }
}

/// Everything the productivity window shows, computed by the app layer.
/// Equatable so the window can skip rebuilding when nothing changed.
public struct ProductivitySnapshot: Equatable {
    public var petName = ""
    public var petStatus = ""
    public var mood = ""
    public var greeting = ""
    public var nextEvent = ""
    public var todayTasks: [TaskItem] = []
    public var overdue: [TaskItem] = []
    public var upcoming: [TaskItem] = []
    public var doneRecently: [TaskItem] = []
    public var tasksDoneToday = 0
    public var focusPhase: FocusPhase = .idle
    public var focusSessionsToday = 0
    public var focusMinutesToday = 0
    public var focusGoalMinutes = 120
    public var pomodoroPlan = PomodoroPlan.classic
    public var pomodoroCompleted = 0
    public var waterToday = 0
    public var waterGoal = 8
    public var lastWater: Date?
    public var nextWater: Date?
    public var breaksToday = 0
    public var focusBreaksToday = 0
    public var activeMinutesToday = 0
    public var idleMinutesToday = 0
    public var continuousWorkMinutes = 0
    public var reminders: [ReminderItem] = []
    public var eyeBreaksOn = false
    public var stretchOn = false
    public var bedtimeOn = false
    public var streakDays = 0
    public var week: [DayStat] = []
    public init() {}
}

/// What the "New task" form produces.
public struct TaskDraft {
    public var title: String
    public var notes = ""
    public var dueDate: Date?
    public var hasDueTime = false
    public var remindBeforeMinutes: Int?
    public var repeatEveryMinutes: Int?
    public var priority: TaskPriority = .medium
    public var recurrence: RecurrenceRule = .none
    public init(title: String) { self.title = title }
}
