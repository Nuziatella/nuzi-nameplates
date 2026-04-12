Gharka Bars v1.5.40

- fixes a client crash caused by runaway addon memory usage
- hardens the settings UI cleanup path so tracked widgets are freed more reliably
- prevents nil unit ids from being sent into target, unit-info, and nametag API calls
- reduces the warning spam tied to invalid `GetUnitInfoById`, `GetUnitScreenNameTagOffset`, and `TargetUnit` calls
- keeps the release copy aligned with the latest source bugfixes
