internal import os

public func once(key: String, _ body: () -> Void) {
    let onceKeys = OSAllocatedUnfairLock(initialState: Set<String>())
    let run = onceKeys.withLockUnchecked { keys in
        guard keys.contains(key) == false else {
            return false
        }
        keys.insert(key)
        return true
    }
    if run {
        body()
    }
}
