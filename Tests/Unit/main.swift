import Foundation

runActionsTests()
runProofreadTests()
runAutocompleteTests()
runSettingsTests()
runUITests()
runVoiceTests()
runLocalServerTests()

if failures == 0 {
    print("ALL TESTS PASSED")
    exit(0)
} else {
    print("\(failures) TEST(S) FAILED")
    exit(1)
}
