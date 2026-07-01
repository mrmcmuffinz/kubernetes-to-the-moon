# CKA Day 6 (Sat, June 27) | Simulator B Retake

Goal: take the full Simulator B retake under real 2-hour timed conditions before the 36-hour window expires. This is a direct comparison test against yesterday's attempt (46/93, 49.5%), answering the critical question: was yesterday's time cascade a one-time execution failure or a pattern that will repeat? The answer determines whether the July 1 exam date holds.

## The attempt

- [ ] Full 2-hour timed attempt. No solutions during the attempt.
- [ ] Apply the self-identified quick fixes from yesterday's attempt where you already know what went wrong, but do not overthink them or let them become time sinks themselves:
  - Q1: Four-segment Service FQDN includes `.svc` (SERVICE.NAMESPACE.svc.cluster.local). Read back the full string before submitting. For stable Pod DNS that survives IP changes, recall hostname plus subdomain fields, not the pod IP-based format.
  - Q3: Two distinct kubelet certificates exist, client and server. Client cert is at `/var/lib/kubelet/pki/kubelet-client-current.pem`, server cert at `/var/lib/kubelet/pki/kubelet.crt`. The `openssl` flag is `-ext extendedKeyUsage`, not guessed.
  - Q6: Read the complete `systemctl status` output, including the exit code and the full `Process:` line, before forming any hypothesis. The diagnosis is in that output.
  - Q10, Q11: If you know the structure cold, build it. If not, use `kubectl explain` but timebox the lookup, do not spiral.
- [ ] Attempt Q9 and Q12 through Q17 even if time-pressed. Any submission, even partial, is better than another cascade of zeros, because zeros give no diagnostic signal at all about whether you know the material.
- [ ] Note your finish time and specifically which questions got attempted this time versus skipped or run-out-of-time.

## What success looks like on this attempt

This is not about a perfect score. This is about **breaking the time cascade** and **collecting real data** on the topics that returned zeros yesterday.

- Q1 and Q3 move to full marks or near it, and in reasonable time.
- Q6's method is faster (you read the output, not a long detour).
- Q9, Q12, Q13, Q14, Q15, Q16, Q17 are at least attempted, even if some are wrong. Wrong is fine. Zero from never-attempted is not, because it tells you nothing.
- Finish time: ideally under two hours with all questions touched, or at least with enough time that any skips this time are genuine confidence-based decisions, not clock exhaustion.

If this attempt lands in the mid-70s or better and the back-half questions got real tries, the exam date holds and Days 7 through 9 are polish and speed work. If this attempt reproduces the cascade (another 50% with zeros on the same block), that is the signal to reschedule, because two identical failures is a pattern, not bad luck.

## Check-in

- [ ] Score: attempt 1 was 46/93 (49.5%). Attempt 2: __/93 (__%).
- [ ] Time cascade broken? How many of Q9, Q12-Q17 were attempted this time (full, partial, or at least started)?
- [ ] Q1, Q3 outcomes: full marks, partial, or still wrong? If still wrong, on the same subtasks or different ones?
- [ ] Finish time and how much of the two hours was left when you completed or gave up on the last question.
