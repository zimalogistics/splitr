## Where we left off
Splitr v1.1 is resubmitted to App Review (`WAITING_FOR_REVIEW`) after fixing two rejection issues: removed "Free" pricing references from screenshot CTAs (guideline 2.3.7) and added a real support page replacing the GitHub Issues URL (guideline 1.5).

## Next step
Wait for Apple's review response on v1.1. If approved, generate promo codes and consider starting the Android companion project. If rejected again, address the new feedback.

## Watch out for
- Screenshots are locked while `WAITING_FOR_REVIEW` — can't replace them until the review resolves. The currently uploaded screenshots already have the corrected CTAs (no pricing references), so this should be fine.
- Two orphaned empty draft submissions (iOS 1.0, 0 items) exist in App Store Connect from API debugging — harmless but can be deleted manually.
- publish.py has two known bugs that need fixing in the auto-listing session: (1) line 493 sets `marketingUrl = ""` causing RFC 3986 errors, (2) submit function uses deprecated `appStoreVersionSubmissions` instead of `reviewSubmissions` + `reviewSubmissionItems` API. We worked around both via direct API calls.
- Support URL and marketingUrl were fixed directly via API — verify publish.py reads the updated `support_url.txt` on next run.
- Widget target device family was fixed to iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`) in project.yml.
