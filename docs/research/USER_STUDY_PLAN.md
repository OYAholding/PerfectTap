# PerfectTap — Study plan: does practice transfer beyond the game?

**Prepared:** 2026-11-21 · **Status:** **plan only.** Nothing has been run, registered, or submitted. No one has been contacted, and no data has been collected.
**Background:** [ADHD_ATTENTION_EVIDENCE.md](ADHD_ATTENTION_EVIDENCE.md) · [MODE_EVIDENCE_MATRIX.md](MODE_EVIDENCE_MATRIX.md) · [COMPLIANCE.md](COMPLIANCE.md)

---

## 1. Why a study, and what it can and cannot show

- **The evidence so far:** cognitive training reliably improves the practiced task (a). It rarely transfers to untrained attention tasks (b). It shows small to null effects on blinded symptom ratings (c) (Westwood et al. 2023; Cortese et al. 2015; Rapport et al. 2013).
- **What is untested:** no study has tested a self-paced tap-timing game like PerfectTap.
- **What a study gives PerfectTap:** the only honest route to saying anything beyond "it's a game".
  - A **null result is a legitimate and useful outcome**, and the plan commits to publishing it.
  - Even a positive result on a lab task would **not** by itself support claims about ADHD symptoms or everyday concentration.
  - Any health claim would also raise FDA/FTC issues ([COMPLIANCE.md](COMPLIANCE.md) §4).

**Studio role:** the studio should **fund and provide the software, not run the science**. A conflict of interest is the most common weakness of the existing literature. Examples are the developer co-author on the Interactive Metronome trial and the sponsor-run EndeavorRx trials. The study should be led by an independent academic team.

---

## 2. Research questions and hypotheses

| # | Question | Outcome class | Primary/secondary |
|---|---|---|---|
| RQ1 | Does 4 weeks of PerfectTap practice improve **sustained attention on an untrained CPT**, compared with an active control game? | (b) far transfer | **Primary** |
| RQ2 | Does practice improve an **untrained timing task**? Candidate: finger-tapping synchronization/continuation variability. | (b) near transfer | Secondary |
| RQ3 | Does practice change **RT variability** (ex-Gaussian *tau*, SD of RT) on the CPT? | (b) | Secondary |
| RQ4 | Any change in **blinded** ratings of inattention (teacher or blinded clinician) or in self-reported everyday attention? | (c) | Secondary / exploratory |
| RQ5 | How much do players improve in-game, and does in-game improvement predict any transfer? | (a), dose-response | Secondary |
| RQ6 | Adherence, enjoyment, frustration, adverse events | Feasibility and safety | Secondary |

**Directional hypothesis (H1):** PerfectTap > active control on CPT change at post-test. **The null hypothesis is the expected default** given the literature.

---

## 3. Design

### 3.1 Phase 0: feasibility pilot (recommended first)

- **Size:** n ≈ 40–60, the same design at small scale.
- **Purpose:** check recruitment, adherence, telemetry, outcome-test logistics and effect-size variance.
- **No efficacy conclusions** from the pilot.

### 3.2 Phase 1: main trial

| Element | Plan |
|---|---|
| Design | **Randomized, parallel-group, active-controlled**, outcome-assessor-blinded (participant-masked as far as possible), pre-registered superiority trial |
| Arms | **(1) PerfectTap "Practice Session"**: fixed-protocol mode plus adaptive staircase (MODE_EVIDENCE_MATRIX R2/R3, optionally R7). **(2) Active control**: same app shell, visuals, session length, rewards and feedback, but a non-timing casual task (e.g. a matching or word game without timing demands). It must be matched for expectation, engagement and screen time. |
| Why active control | Gamified placebos produce symptom "improvement" too (Dovis et al. 2015; the EndeavorRx control arm). A waitlist or no-contact control cannot separate expectancy from effect (Simons et al. 2016). |
| Dose | E.g. 15–20 min/day, 5 days/week, 4 weeks, in-app enforced and logged. This is comparable to EndeavorRx (25 min × 5 × 4) but shorter. Final dose to be set after the pilot. |
| Timepoints | Baseline (T0), post-training (T1, week 4), follow-up (T2, ~3 months) |
| Population | **Adults (18+) first.** Consent is simpler and there is less risk. Inclusion is not conditional on diagnosis (see §5). A youth study only as a later step with a pediatric research team, parental consent and child assent. |
| Randomization | Computer-generated, stratified (e.g. by baseline CPT score and by self-reported medication use, if collected). Allocation concealed from assessors. |
| Sample size | Illustrative only: to detect a standardized difference of 0.30 on the primary outcome (two-sided α = 0.05, power 0.80) requires about **176 per arm** before attrition, or **~220 per arm** at 20% dropout. A realistic effect could be smaller (the EndeavorRx CPT effect was ≈0.28 SD, our estimate). The statistician should set the final number from pilot data. |

### 3.3 Outcomes (must be blinded or objective)

| Outcome | Instrument (examples) | Blinding / objectivity |
|---|---|---|
| **Primary:** sustained attention | An **established CPT** (e.g. Conners CPT 3, TOVA, or an open-source validated CPT), administered **outside PerfectTap** by assessors blind to arm. Pre-specify one summary index (e.g. d′ or an omnibus index). | Objective, assessor-blind |
| RT variability | SD of RT and ex-Gaussian *tau* from the CPT | Objective |
| Near transfer (timing) | Paced/unpaced finger tapping, computing the SD of inter-tap interval and asynchrony | Objective |
| Inhibition (exploratory) | Stop-signal task (SSRT) | Objective |
| Everyday attention | Blinded rater where possible. For adults: a self-report scale (e.g. ASRS) reported as **unblinded**. For youth: a teacher rating. | Report blinded and unblinded **separately** |
| In-game | Practice curve, staircase threshold, consistency metrics from per-session telemetry (MODE_EVIDENCE_MATRIX R1) | (a) only |
| Expectancy | A short expectation questionnaire at baseline and post ("how much do you expect this game to help your attention?") | Used as a covariate and a manipulation check |
| Safety / experience | Frustration, headaches, eye strain, sleep, problematic-use items, enjoyment | Self-report |

**Note on instruments:** commercial CPTs carry licensing fees, and some require qualified administrators. The research partner should select and license them. The studio should not choose the primary outcome.

---

## 4. Pre-registration and analysis

- **Pre-register before enrolment** on OSF Registries or ClinicalTrials.gov. ClinicalTrials.gov is advisable if any health outcome is included.
- The registration must include hypotheses, the primary outcome, the analysis plan, sample size and stopping rules.
- Consider a **Registered Report** at a journal, which reviews the method before results are known.
- **Primary analysis:** intention-to-treat, using an ANCOVA or mixed model of T1 CPT index with baseline as covariate.
- **Multiplicity:** all secondary outcomes are labelled as such, with a pre-specified correction (e.g. Holm) or treated as exploratory.
- **Report by outcome class:** (a), (b) and (c) are reported separately. Blinded and unblinded ratings are always reported separately. This is the core lesson of Cortese 2015 and Westwood 2023.
- **Publish regardless of the result:** open access, with de-identified data and analysis code shared where consent allows.
- **Checklist alignment:** CONSORT reporting. Simons et al. 2016 best-practice criteria: active control, pre-registration, blinding, expectation measurement, full outcome reporting.

---

## 5. Ethics, consent and privacy

### 5.1 Ethics review
- Approval from an **independent ethics committee / IRB** at the partner institution. In Israel, that may be a Helsinki committee where health data is involved; follow the partner's rules.
- Apple App Review Guideline **5.1.3(iv)** independently requires ethics-board approval for health-related human-subject research conducted through an app. Proof must be available on request ([COMPLIANCE.md](COMPLIANCE.md) §1.1).

### 5.2 Voluntary participation and informed consent
- **Never auto-enrol.** The study is a separate, opt-in flow, or preferably a **separate study build distributed via TestFlight**, not the production app.
- Consent covers (per Apple 5.1.3(iii) and standard research ethics):
  - nature, purpose and duration
  - procedures
  - risks and benefits, including "you may not benefit"
  - data handling
  - who to contact
  - the right to **withdraw at any time without penalty**, with data deletion on request
- **No inducements that compromise voluntariness.** Modest compensation for time is fine. In-game currency or cosmetics as payment should be avoided or approved by the ethics board, since it couples research to monetization.
- Participants in the control arm are offered the PerfectTap protocol after the study ends.

### 5.3 Diagnosis and health data: minimize
- **Default: do not collect an ADHD diagnosis.**
  - The primary question (does practice transfer to a CPT?) can be studied in a general adult population.
  - Use a **validated symptom screener** (e.g. ASRS) only if the research team needs it for stratification or subgroup analysis.
- **If diagnosis or medication status is needed**, for example for an ADHD-subgroup analysis designed by clinicians:
  - Collect it **only within the research partner's systems**, never in PerfectTap's production backend (Supabase) or analytics.
  - Store it pseudonymised, with a separate key held by the research team.
  - Never link it to the player's game account or leaderboards.
  - **Never share it with advertising platforms.** This is also required by Apple 5.1.3(i) and Meta's Business Tools terms.
  - Treat it as special-category data under GDPR Art. 9, with explicit consent, a DPIA and a data-processing agreement. Apply equivalent protections under US state privacy laws and Israel's Privacy Protection Law.
- **Telemetry:** research telemetry (per-tap timing) is collected in the study build only. It is keyed to a random study ID and retained only as long as the protocol states.
- **Minors:** excluded from Phase 1. Any later youth study needs parental consent and child assent, pediatric expertise, and no ads or third-party SDKs in the study build.

### 5.4 Safety
- Monitor adverse events (frustration, headaches, eye strain, sleep, compulsive play). There should be a pre-defined pathway for participants who report distress.
- Not a treatment: participants are told to **continue any existing care unchanged**. The study makes no treatment recommendation.
- Photosensitivity: screen out photosensitive epilepsy, and keep flashing within safe limits. The EndeavorRx label flags photosensitive epilepsy as a possible contraindication.

---

## 6. Partners and governance

| Role | Who | Notes |
|---|---|---|
| Principal investigator | An **independent academic** with ADHD and attention research expertise (clinical psychology, psychiatry or cognitive neuroscience) | Owns design, analysis and publication. The studio has no veto over publication. |
| Clinical advisor | A licensed ADHD clinician | Safety, consent wording, adverse-event pathway |
| Lived-experience input | Adults with ADHD on an advisory panel | Design comfort, burden, wording |
| Statistician | Independent of the studio | Sample size, analysis plan, blinded data handling |
| Studio | Funds the work; builds the study build and both arms; provides telemetry tooling | **Declares the conflict of interest**. No access to unblinded outcome data before analysis is locked. |

**Contracting:** a research agreement guaranteeing the right to publish, data ownership by the institution, and a data-processing agreement. **No outreach has been made. Identifying partners is a future step for the owner.**

---

## 7. What the studio may say at each stage

| Stage | OK to say | Not OK |
|---|---|---|
| Before or during the study | "We're supporting independent research into whether timing practice carries over beyond the game. Results aren't in yet." | "Studies show…", "being clinically tested to improve focus" |
| After a null result | "An independent study found no evidence that PerfectTap practice improves attention outside the game. It's a game, and we're proud of how it feels to play." | Spinning secondary or within-group results |
| After a positive primary result | Describe the exact finding, e.g. "improved performance on a lab attention test in adults vs. an active control game", with a link to the paper, **after legal review** | "Improves focus", "helps ADHD", any symptom or treatment claim. A single study does not meet the FTC's substantiation bar for broad claims, and ADHD claims enter FDA device territory ([COMPLIANCE.md](COMPLIANCE.md) §4). |

---

## 8. Rough timeline (indicative)

| Step | Duration |
|---|---|
| Identify academic partner; scope and contract | 2–4 months |
| Protocol, instrument licensing, ethics approval, pre-registration | 2–4 months |
| Study build (protocol mode, active control, telemetry, consent flow) | Parallel, ~1–2 months engineering |
| Phase 0 pilot (incl. analysis) | ~3 months |
| Phase 1 main trial (recruitment + 4 weeks training + 3-month follow-up) | 9–12 months |
| Analysis and publication | 3–6 months |

**Prerequisites in the app:** MODE_EVIDENCE_MATRIX **R1** (telemetry), **R2** (fixed protocol) and **R3** (staircase). These are useful even if no study is ever run.
