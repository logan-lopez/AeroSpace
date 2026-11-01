---
paths:
  - "Sources/AppBundle/focus.swift"
  - "Sources/AppBundle/focusCache.swift"
  - "Sources/AppBundle/getNativeFocusedWindow.swift"
  - "Sources/AppBundle/GlobalObserver.swift"
  - "Sources/AppBundle/runLoop.swift"
  - "Sources/AppBundle/windowLevelCache.swift"
  - "Sources/AppBundle/initAppBundle.swift"
  - "Sources/AppBundle/tree/MacApp.swift"
  - "Sources/AppBundle/util/accessibility.swift"
  - "Sources/AppBundle/util/AxSubscription.swift"
  - "Sources/AppBundle/util/ThreadGuardedValue.swift"
  - "Sources/AppBundle/util/AwaitableOneTimeBroadcastLatch.swift"
  - "Sources/AppBundle/util/CompletableFuture.swift"
  - "Sources/AppBundle/util/AxUiElementMock.swift"
  - "Sources/AppBundle/util/axTrustedCheckOptionPrompt.swift"
  - "Sources/AppBundle/util/dumpAxRecursive.swift"
  - "Sources/AppBundle/util/appBundleUtil.swift"
  - "Sources/Common/model/AxAppThreadToken.swift"
  - "Sources/PrivateApi/**"
---

Before changing these files, read [Windows and focus](../../docs/architecture/windows-and-focus.md).

The accessibility layer, thread-per-application model, AX and NSWorkspace observation, caches, focus reconciliation and startup, for sessions touching window observation, focus or performance.
