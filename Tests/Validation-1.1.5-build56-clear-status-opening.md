# 1.1.5 (56) portrait status-bar selection

The user accepted the portrait OFF result on Build 55. In the ON result, the Dynamic Island and recording circle had a solid 64-pixel-high connection. The accepted reference had a 19-pixel gap. The matching clock digit had a median 10–90% edge width of 5.29 pixels in the reported result and 2.09 pixels in the reference. The finished images cannot establish whether the recording contained a sharper view of the same opening.

Portrait ON can choose an original frame that shows a detached recording circle and usable clock and battery detail. The frame comes from the same recording segment and must match the opening's native viewport, including navigation directly below the status band. The detector compares both side lanes, verifies a clock and matches the battery silhouette. Selection uses the chosen frame for the opening rows. If there is no verified peer, the recording supplies the original opening. No status bar pixels are drawn or retouched.

The detector distinguished the reported joined shape from the detached reference and measured lower detail in both lanes. The paired battery check passed eight native comparisons, including the real soft and clear samples and synthetic missing, moved and textured cases. Native status checks passed 60 assertions. UIKit passed 311 assertions. The focused cases cover clearer detached selection, rejection of weaker detail, changed navigation and another scroll position, raw ON fallback, OFF crop and unchanged source bytes. The private reference images stay local.

The final coherent run passed **33/33** gates, including performance, pinned baseline output, horizontal geometry and standard device/simulator builds. Source/config/test SHA-256 is `ee672158b8e2a6910ada6686a41ae50950607117a82deb953b59823436ca2e4a`. Report: `Build/regression-z7NJJq/report.json`.

The standard Build 56 device export passed strict signature, entitlement, version and bilingual resource checks. The owner confirmed on iPhone that the Dynamic Island and recording dot are separate and that the time and battery details are clear.
