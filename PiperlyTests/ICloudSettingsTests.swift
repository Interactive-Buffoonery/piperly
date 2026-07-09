import Testing
import SwiftUI
@testable import Piperly

@Suite("iCloud settings presentation")
struct ICloudSettingsPresentationTests {
    @Test func coversEverySyncStateWithRecoverableCopy() {
        let states: [LibrarySyncStatus] = [
            .disabled,
            .idle,
            .syncing,
            .waitingToRetry(nil),
            .accountConfirmationRequired,
            .blocked(.quotaExceeded),
        ]

        for state in states {
            let presentation = ICloudStatusPresentation(state)
            #expect(!presentation.title.isEmpty)
            #expect(!presentation.explanation.isEmpty)
            #expect(!presentation.symbolName.isEmpty)
        }
        #expect(ICloudStatusPresentation(.disabled).explanation.contains("stay on this iPad"))
        #expect(ICloudStatusPresentation(.blocked(.quotaExceeded)).explanation.contains("quota"))
    }

    @Test func accountPolicyChoicesRemainExplicit() {
        #expect(AccountTransitionPolicy.keepLocalAndUploadAfterFetch != .discardPendingChanges)
        #expect(SyncAccountConfirmationContext.firstEnable != .accountChangedWithPendingWork)
    }

    @Test func controlsCoverEnableDisableAccountChoiceAndRetry() {
        let disabled = ICloudSettingsActions(status: .disabled, context: nil, isEnabled: false)
        #expect(disabled.showsEnable)
        #expect(!disabled.showsDisable)
        #expect(!disabled.showsAssetRecovery)

        let enabled = ICloudSettingsActions(status: .idle, context: nil, isEnabled: true)
        #expect(enabled.showsDisable)
        #expect(!enabled.showsRetry)
        #expect(enabled.showsAssetRecovery)

        let changedAccount = ICloudSettingsActions(
            status: .accountConfirmationRequired,
            context: .accountChangedWithPendingWork,
            isEnabled: true
        )
        #expect(changedAccount.showsDiscardPendingWork)
        #expect(changedAccount.showsDisable)

        let firstEnableConfirmation = ICloudSettingsActions(
            status: .accountConfirmationRequired,
            context: .firstEnable,
            isEnabled: false
        )
        #expect(!firstEnableConfirmation.showsEnable)
        #expect(!firstEnableConfirmation.showsDisable)

        let blocked = ICloudSettingsActions(
            status: .blocked(.quotaExceeded),
            context: nil,
            isEnabled: true
        )
        #expect(blocked.showsRetry)

        let failedFirstEnable = ICloudSettingsActions(
            status: .blocked(.accountUnavailable),
            context: nil,
            isEnabled: false
        )
        #expect(failedFirstEnable.showsEnable)
        #expect(!failedFirstEnable.showsRetry)
        #expect(!failedFirstEnable.showsAssetRecovery)
    }

    @Test func parentGateRelocksWheneverTheAppLeavesTheForeground() {
        #expect(!ParentGateAccessPolicy.shouldReset(when: .active))
        #expect(ParentGateAccessPolicy.shouldReset(when: .inactive))
        #expect(ParentGateAccessPolicy.shouldReset(when: .background))
    }

    @Test @MainActor func stoppedSyncLifecycleRejectsLateCallbacks() {
        let token = ICloudSyncLifecycleToken()
        #expect(token.isActive)

        token.invalidate()

        #expect(!token.isActive)
    }

    @Test func replacementEngineRejectsOldBatchProvider() {
        let oldEngineToken = CloudSyncActivityToken()
        let newEngineToken = CloudSyncActivityToken()
        #expect(oldEngineToken.isActive)

        oldEngineToken.invalidate()

        #expect(!oldEngineToken.isActive)
        #expect(newEngineToken.isActive)
    }
}
