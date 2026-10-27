package ohos_app_cangjie_entry

import kit.PerformanceAnalysisKit.Hilog
import kit.AbilityKit.Want
import kit.AbilityKit.UIAbility
import kit.AbilityKit.LaunchParam
import kit.AbilityKit.LaunchReason
import kit.ArkUI.WindowStage
// Force-link the demo page subpackage so its @Entry("EntryView") registration runs.
// The page lives in its own package to keep `import kit.ArkUI.*` from leaking
// None-bearing ArkUI enums into the entry package where the unit-test suites live.
import ohos_app_cangjie_entry.page.EntryView

class MainAbility <: UIAbility {
    public init() {
        super()
        registerSelf()
    }

    public override func onCreate(want: Want, launchParam: LaunchParam): Unit {
        Hilog.info(1, "Cangjie", "MainAbility OnCreated.${want.abilityName}")
        match (launchParam.launchReason) {
            case LaunchReason.StartAbility => Hilog.info(1, "Cangjie", "START_ABILITY")
            case _ => ()
        }
    }

    public override func onWindowStageCreate(windowStage: WindowStage): Unit {
        Hilog.info(1, "Cangjie", "MainAbility onWindowStageCreate.")
        windowStage.loadContent("EntryView")
    }
}
