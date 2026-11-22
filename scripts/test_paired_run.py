#!/usr/bin/env python3
"""Tests for scripts/paired_run.py on invented run folders and invented source trees. No simulator, no network, no git.

Run: python3 scripts/test_paired_run.py
"""
import contextlib, io, os, shutil, sys, tempfile, unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paired_run as pr

QUESTIONS = ["exact_fuel_capacity", "exact_capex", "retrieval_policy_alpha", "multi_hop_project_m1", "lost_in_middle_middle"]


def score_text(results, name="standard-app"):
    """A `.score.txt` as scripts/score_answer_eval.py prints it."""
    rows = [f"  {'PASS' if right else 'fail'} judge=fail  {q:28s} {120:5d} chars" for q, right in results.items()]
    right = sum(results.values())
    return "\n".join([f"== {name}.xcresult  ({len(results)} cases)"] + rows
                     + [f"  rule {right}/{len(results)}  judge 0/{len(results)}  agree 0/{len(results)}"]) + "\n"


def answers(*right):
    """Right for the questions named, wrong for the rest."""
    return {q: q in right for q in QUESTIONS}


def make_run(parent, name, modes, result="passed"):
    """A run folder with a score file per mode and a SUMMARY.md, as bench_answer_modes.sh leaves it."""
    folder = os.path.join(parent, name)
    os.makedirs(folder)
    rows = []
    for key, results in modes.items():
        mode, model = key.split("-")
        with open(os.path.join(folder, key + ".score.txt"), "w") as f:
            f.write(score_text(results, key))
        rows.append(f"| {mode} | {model} | {sum(results.values())}/{len(results)} | 0.5 | {len(results)} | 0 | 7 | {result} |")
    with open(os.path.join(folder, "SUMMARY.md"), "w") as f:
        f.write("# Answer quality by mode\n\n| Mode | Model | Right by rule | Judge | Answered | Refused | Minutes | Result |\n"
                "|---|---|---|---|---|---|---|---|\n" + "\n".join(rows) + "\n")
    return folder


# Invented cases and an invented rule, shaped like the scorer's: right when the case's value is in the answer.
CASES = [
    {"id": "exact_a", "category": "exact_value", "query": "What is A?", "needle": "A1"},
    {"id": "missing_b", "category": "missing_evidence", "expected_behavior": "abstain", "query": "What is B?", "needle": "not in"},
    {"id": "litm_1", "category": "lost_in_middle", "query": "What is the token?", "needle": "T1"},
    {"id": "litm_2", "category": "lost_in_middle", "query": "What is the token?", "needle": "T2"},
    {"id": "file_c", "category": "retrieval_only", "query": "Which file has C?", "needle": "c.md"},
]
RULE = lambda case, answer, cases: case["needle"] in answer


def line(question, answer=None, error=None):
    kind, tail = ("answered", f"answer={answer}") if error is None else ("refused", f"error={error}")
    return f"[AnswerQualityEvaluation] {kind} mode=standard seconds=12 question={question} {tail}"


class ReadingARun(unittest.TestCase):
    def test_score_rows_become_right_and_wrong_by_question(self):
        results, problems = pr.parse_score(score_text(answers("exact_capex", "lost_in_middle_middle")))
        self.assertEqual(list(results), QUESTIONS)  # in the file's order
        self.assertEqual(results["exact_capex"], True)
        self.assertEqual(results["exact_fuel_capacity"], False)
        self.assertEqual(problems, [])

    def test_the_real_scorer_format_with_a_banner_column(self):
        text = ("== standard-app.xcresult  (3 cases)\n"
                "  PASS judge=pass  exact_fuel_capacity             26 chars\n"
                "  PASS judge=fail  exact_temperature_limit        355 chars  [Needs Verification]\n"
                "  fail judge=pass  lost_in_middle_middle          242 chars\n"
                "  rule 2/3  judge 2/3  agree 1/3\n")
        results, problems = pr.parse_score(text)
        self.assertEqual(results, {"exact_fuel_capacity": True, "exact_temperature_limit": True, "lost_in_middle_middle": False})
        self.assertEqual(problems, [])

    def test_the_judge_column_is_not_the_score(self):
        results, _ = pr.parse_score("== x  (1 cases)\n  fail judge=pass  exact_capex   87 chars\n  rule 0/1  judge 1/1  agree 0/1\n")
        self.assertEqual(results, {"exact_capex": False})

    def test_an_empty_score_file_has_no_results(self):
        self.assertEqual(pr.parse_score(""), ({}, []))
        self.assertEqual(pr.parse_score("Traceback (most recent call last):\n  File x\n"), ({}, []))

    def test_a_total_that_disagrees_with_the_rows_is_named(self):
        text = score_text(answers("exact_capex")).replace("rule 1/5", "rule 3/5")
        self.assertIn("disagrees with the rows (1 of 5)", pr.parse_score(text)[1][0])
        cut_short = "\n".join(score_text(answers("exact_capex")).splitlines()[:-1])
        self.assertIn("did not finish", pr.parse_score(cut_short)[1][0])

    def test_a_question_the_scorer_could_not_place_keeps_its_row(self):
        results, _ = pr.parse_score("== x  (2 cases)\n  fail judge=fail  ?   10 chars\n  PASS judge=fail  ?   10 chars\n"
                                    "  rule 1/2  judge 0/2  agree 1/2\n")
        self.assertEqual(results, {"?row1": False, "?row2": True})

    def test_several_sections_read_the_last(self):
        text = score_text(answers()) + score_text(answers("exact_capex"))
        results, problems = pr.parse_score(text)
        self.assertEqual(sum(results.values()), 1)
        self.assertIn("2 scored sections", problems[0])

    def test_answer_lines_are_parsed_in_order(self):
        text = "\n".join(["[AnswerQualityEvaluation] imported 25 of 25 fixtures", line("What is A?", "It is A1. [S1]"),
                          line("What is B?", error="timed out"), "[AnswerQualityEvaluation] correct: 0.5 over 20 cases"])
        self.assertEqual(pr.parse_answer_lines(text), [("What is A?", "It is A1. [S1]"), ("What is B?", None)])

    def test_a_whole_printed_answer_is_scored_right_or_wrong(self):
        results, unscored = pr.score_prefixes([("What is A?", "It is A1."), ("Which file has C?", "No file.")], CASES, RULE)
        self.assertEqual(results, {"exact_a": True, "file_c": False})
        self.assertEqual(unscored, [])

    def test_a_cut_answer_is_scored_only_when_the_value_is_already_there(self):
        long = "x" * pr.PRINTED
        results, unscored = pr.score_prefixes(
            [("What is A?", "A1 " + long[3:]),         # cut, the value is in the printed part: right
             ("Which file has C?", long),              # cut, no file name yet: it may come later
             ("What is B?", "not in " + long[7:])],    # cut, a refusal so far: an amount may come later
            CASES, RULE)
        self.assertEqual(results, {"exact_a": True})
        self.assertEqual(unscored, ["file_c", "missing_b"])

    def test_the_cut_is_where_the_answer_test_makes_it(self):
        self.assertEqual(pr.PRINTED, 300)
        results, unscored = pr.score_prefixes([("Which file has C?", "y" * 299), ("What is A?", "y" * 300)], CASES, RULE)
        self.assertEqual((results, unscored), ({"file_c": False}, ["exact_a"]))  # 299 is whole, 300 may be cut
        swift = os.path.join(pr.ROOT, pr.ANSWER_TEST)
        if os.path.exists(swift):
            # `first` is the first answer's text since 2026-11-22 (the ask-again option keeps it to compare with later asks).
            self.assertIn(f"first.prefix({pr.PRINTED})", open(swift, encoding="utf-8").read())

    def test_a_cut_token_answer_is_never_scored(self):
        results, unscored = pr.score_prefixes([("What is the token?", "T1 " + "x" * pr.PRINTED)], CASES, RULE)
        self.assertEqual((results, unscored), ({}, ["litm_1"]))  # another case's token may follow

    def test_a_refusal_is_wrong_and_a_shared_question_goes_by_order(self):
        results, unscored = pr.score_prefixes(
            [("What is A?", None), ("What is the token?", "T1"), ("What is the token?", "T1")], CASES, RULE)
        self.assertEqual(results, {"exact_a": False, "litm_1": True, "litm_2": False})
        self.assertEqual(unscored, [])

    def test_a_question_outside_the_manifest_is_unscored_under_its_first_words(self):
        results, unscored = pr.score_prefixes([("Who wrote the seven page memo on tides?", "Someone.")], CASES, RULE)
        self.assertEqual(results, {})
        self.assertEqual(unscored, ["? Who wrote the seven page memo"])

    def test_a_run_folder_is_read_from_its_score_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = make_run(tmp, "2026-01-01-0100-answer-modes-x", {"standard-app": answers("exact_capex"),
                                                                    "deepThink-app": answers()})
            run = pr.read_run(folder)
            self.assertEqual(run["name"], "2026-01-01-0100-answer-modes-x")
            self.assertEqual(sorted(run["modes"]), ["deepThink-app", "standard-app"])
            self.assertEqual(run["modes"]["standard-app"]["source"], "score")
            self.assertEqual(pr.tally(run["modes"]["standard-app"]["results"]), (1, 5))

    def test_a_stopped_run_falls_back_to_its_answer_lines_and_says_so(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = make_run(tmp, "run", {"maximum-app": answers()}, result="failed (exit 143)")
            open(os.path.join(folder, "maximum-app.score.txt"), "w").close()  # the scorer wrote nothing
            with open(os.path.join(folder, "maximum-app.txt"), "w") as f:
                f.write(line("What is A?", "A1") + "\n" + line("Which file has C?", "y" * pr.PRINTED) + "\n")
            mode = pr.read_run(folder, prefix_scorer=(RULE, CASES))["modes"]["maximum-app"]
            self.assertEqual(mode["source"], "prefix")
            self.assertEqual(mode["results"], {"exact_a": True})
            text = " ".join(mode["problems"])
            self.assertIn("the score file is empty; 1 of 2 answers scored", text)
            self.assertIn("left unscored: file_c", text)
            self.assertIn("failed (exit 143)", text)

    def test_a_folder_with_only_a_log_reads_as_nothing_scored(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "run"))
            open(os.path.join(tmp, "run", "deepThink-app.log"), "w").close()
            open(os.path.join(tmp, "run", "SUMMARY.md.progress"), "w").close()
            mode = pr.read_run(os.path.join(tmp, "run"))["modes"]["deepThink-app"]
            self.assertEqual((mode["source"], mode["results"]), (None, {}))
            self.assertIn("no score file", mode["problems"][0])


class Percentages(unittest.TestCase):
    def test_the_percentage_comes_first_with_the_count_beside_it(self):
        self.assertEqual(pr.pct(15, 17), "88% (15 of 17)")
        self.assertEqual(pr.pct(18, 20), "90% (18 of 20)")
        self.assertEqual(pr.pct(0, 20), "0% (0 of 20)")
        self.assertEqual(pr.pct(20, 20), "100% (20 of 20)")

    def test_a_half_rounds_up(self):
        self.assertEqual(pr.pct(1, 8), "13% (1 of 8)")   # 12.5
        self.assertEqual(pr.pct(17, 40), "43% (17 of 40)")  # 42.5

    def test_nothing_scored_is_not_zero_percent(self):
        self.assertEqual(pr.pct(0, 0), "none scored")

    def test_a_net_change_reads_in_points_with_the_count(self):
        self.assertEqual(pr.net_text(1, 20), "+5 points (+1 question of 20)")
        self.assertEqual(pr.net_text(-3, 20), "-15 points (-3 questions of 20)")
        self.assertEqual(pr.net_text(0, 20), "0 points (0 questions of 20)")


def run_of(name, **modes):
    return {"name": name, "folder": name,
            "modes": {key.replace("_", "-"): {"source": "score", "results": results, "problems": []} for key, results in modes.items()}}


BEFORE = run_of("before", standard_app=answers("exact_fuel_capacity", "exact_capex"))
# fixes two questions and breaks one: net +1
AFTER = run_of("after", standard_app=answers("exact_fuel_capacity", "retrieval_policy_alpha", "multi_hop_project_m1"))


class Comparing(unittest.TestCase):
    def test_fixed_and_broken_are_listed_by_question(self):
        common, fixed, broken = pr.flips(BEFORE["modes"]["standard-app"]["results"], AFTER["modes"]["standard-app"]["results"])
        self.assertEqual(len(common), 5)
        self.assertEqual(fixed, ["retrieval_policy_alpha", "multi_hop_project_m1"])
        self.assertEqual(broken, ["exact_capex"])

    def test_one_run_of_each_build_gets_no_verdict(self):
        mode = pr.compare_runs(BEFORE, AFTER)["modes"][0]
        self.assertEqual((mode["before"], mode["after"], mode["net"]), ((2, 5), (3, 5), 1))
        self.assertIsNone(mode["noise"])
        self.assertEqual(mode["reading"], "noise not measured")

    def test_no_net_change_without_noise_says_both(self):
        same_count = run_of("after", standard_app=answers("exact_fuel_capacity", "lost_in_middle_middle"))
        mode = pr.compare_runs(BEFORE, same_count)["modes"][0]
        self.assertEqual((len(mode["fixed"]), len(mode["broken"]), mode["net"]), (1, 1, 0))
        self.assertEqual(mode["reading"], "no net change; noise not measured")

    def test_a_net_change_no_larger_than_the_flips_between_identical_builds_is_noise(self):
        again = run_of("before-2", standard_app=answers("exact_fuel_capacity"))  # one question differs from BEFORE
        mode = pr.compare_runs(BEFORE, AFTER, more_before=[again])["modes"][0]
        self.assertEqual(mode["noise"], {"flips": 1, "pairs": 1, "unstable": ["exact_capex"]})
        self.assertEqual(mode["reading"], "within run-to-run noise")  # net +1 against 1

    def test_a_net_change_larger_than_the_noise_is_said_to_be_larger(self):
        identical = run_of("before-2", standard_app=dict(BEFORE["modes"]["standard-app"]["results"]))
        mode = pr.compare_runs(BEFORE, AFTER, more_before=[identical])["modes"][0]
        self.assertEqual(mode["noise"]["flips"], 0)
        self.assertEqual(mode["reading"], "larger than run-to-run noise")

    def test_a_loss_is_held_to_the_same_rule(self):
        again = run_of("after-2", standard_app=answers("exact_fuel_capacity", "exact_capex", "lost_in_middle_middle"))
        mode = pr.compare_runs(AFTER, BEFORE, more_before=[again])["modes"][0]  # AFTER as the baseline: net -1
        self.assertEqual(mode["net"], -1)
        self.assertEqual(mode["noise"]["flips"], 4)
        self.assertEqual(mode["reading"], "within run-to-run noise")

    def test_noise_is_the_largest_count_over_every_two_runs_of_one_build(self):
        one, two, three = answers("exact_capex"), answers("exact_capex", "exact_fuel_capacity"), answers()
        noise = pr.noise_between([[one, two, three], [answers()]])
        self.assertEqual((noise["flips"], noise["pairs"]), (2, 3))  # two against three differ on two questions
        self.assertEqual(sorted(noise["unstable"]), ["exact_capex", "exact_fuel_capacity"])
        self.assertIsNone(pr.noise_between([[one], [two]]))  # runs of different builds measure no noise

    def test_runs_of_the_after_build_count_too(self):
        again = run_of("after-2", standard_app=answers("exact_fuel_capacity", "retrieval_policy_alpha"))
        mode = pr.compare_runs(BEFORE, AFTER, more_after=[again])["modes"][0]
        self.assertEqual(mode["noise"]["flips"], 1)
        self.assertEqual(mode["others"], [("after", "after-2", (2, 5), "score")])

    def test_one_build_on_both_sides_makes_every_flip_noise(self):
        mode = pr.compare_runs(BEFORE, AFTER, same_build=True)["modes"][0]
        self.assertEqual(mode["noise"]["flips"], 3)
        self.assertEqual(mode["reading"], "within run-to-run noise")

    def test_a_partial_run_is_compared_on_shared_questions_and_gets_no_verdict(self):
        partial = run_of("after", standard_app={"exact_fuel_capacity": True, "exact_capex": True, "retrieval_policy_alpha": True})
        partial["modes"]["standard-app"]["source"] = "prefix"
        again = run_of("before-2", standard_app=dict(BEFORE["modes"]["standard-app"]["results"]))
        mode = pr.compare_runs(BEFORE, partial, more_before=[again])["modes"][0]
        self.assertEqual((mode["common"], mode["before_common"], mode["after_common"]), (3, (2, 3), (3, 3)))
        self.assertEqual(mode["fixed"], ["retrieval_policy_alpha"])
        self.assertEqual(mode["reading"], "no verdict: only 3 of 5 questions were scored in both runs")

    def test_answer_line_scores_never_measure_noise(self):
        again = run_of("before-2", standard_app=answers())
        again["modes"]["standard-app"]["source"] = "prefix"
        self.assertIsNone(pr.compare_runs(BEFORE, AFTER, more_before=[again])["modes"][0]["noise"])

    def test_only_modes_in_both_runs_are_compared(self):
        before = run_of("before", standard_app=answers(), maximum_app=answers())
        after = run_of("after", standard_app=answers("exact_capex"), deepThink_app=answers())
        result = pr.compare_runs(before, after)
        self.assertEqual([m["mode"] for m in result["modes"]], ["standard-app"])
        self.assertEqual(result["skipped"], ["deepThink-app: nothing scored in before", "maximum-app: nothing scored in after"])

    def test_the_printed_comparison(self):
        again = run_of("before-2", standard_app=answers("exact_fuel_capacity"))
        text = pr.describe(pr.compare_runs(BEFORE, AFTER, more_before=[again]),
                           {"exact_capex": "What was the FY2018 capital expenditure amount?"})
        for expected in ["standard (app model)", "  before  40% (2 of 5)", "  after   60% (3 of 5)",
                         "  before  20% (1 of 5)  before-2", "fixed, wrong to right: 2", "broken, right to wrong: 1",
                         "What was the FY2018 capital expenditure amount?  (also flips between runs of one build)",
                         "net change: +20 points (+1 question of 5)",
                         "noise: at most 1 of 5 questions flipped between two runs of one build (1 pair of runs compared)",
                         "reading: within run-to-run noise",
                         "| standard (app model) | 40% (2 of 5) | 60% (3 of 5) | 2: retrieval_policy_alpha, multi_hop_project_m1 "
                         "| 1: exact_capex | +20 points (+1 question of 5) | within run-to-run noise |"]:
            self.assertIn(expected, text)

    def test_without_noise_the_printout_says_how_to_measure_it(self):
        text = pr.describe(pr.compare_runs(BEFORE, AFTER))
        self.assertIn("noise: not measured.", text)
        self.assertIn("--noise", text)
        self.assertIn("reading: noise not measured", text)

    def test_compare_from_the_command_line_on_folders(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = make_run(tmp, "a", {"standard-app": BEFORE["modes"]["standard-app"]["results"]})
            b = make_run(tmp, "b", {"standard-app": AFTER["modes"]["standard-app"]["results"]})
            a2 = make_run(tmp, "a2", {"standard-app": BEFORE["modes"]["standard-app"]["results"]})
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(pr.main(["compare", a, b, "--noise", a2]), 0)
            self.assertIn("larger than run-to-run noise", out.getvalue())
            self.assertIn("  also    a2 (the before build again)", out.getvalue())

    @unittest.skipUnless(os.path.isdir(os.path.join(pr.RUNS, "2026-11-19-0629-answer-modes-bind-fix-ans")),
                         "the run folders of 2026-11-19 are not on this machine (BenchmarkRuns is not in git)")
    def test_the_real_pair_of_2026_11_19_reads_as_the_ledger_says(self):
        before = pr.read_run(os.path.join(pr.RUNS, "2026-11-19-0620-answer-modes-bind-base-ans"))
        after = pr.read_run(os.path.join(pr.RUNS, "2026-11-19-0629-answer-modes-bind-fix-ans"))
        mode = pr.compare_runs(before, after)["modes"][0]
        self.assertEqual((mode["before"], mode["after"]), ((18, 20), (18, 20)))
        self.assertEqual((mode["fixed"], mode["broken"]), (["lost_in_middle_middle"], ["retrieval_nfcorpus_epsilon"]))


SIM = "#if targetEnvironment(simulator)"
MODE_TEST = 'let mode = ProcessInfo.processInfo.environment["OI_EVAL_MODE"] ?? ""\n'
OLD_TEST = 'let enabled = ProcessInfo.processInfo.environment["OI_MODEL_EVALS"] == "1"\n'


def write(root, path, text):
    full = os.path.join(root, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)


def make_tree(root, old_layout=False):
    """An invented source tree with the four Simulator switches where HEAD has them, or where v5.7.0 had them."""
    os.makedirs(os.path.join(root, "OpenIntelligence.xcodeproj"))
    first = f"func a() {{\n{SIM}\n// Foundation Models + PCC are not available inside the simulator runtime\nreturn false\n#endif\n}}\n"
    device = (f"func b() {{\n{SIM}\n// Simulator: Foundation Models not available\n#endif\n}}\nfunc chip() {{\n{SIM}\n"
              "return .a14Bionic  // Don't claim Apple Intelligence support in simulator\n#endif\n}\n")
    write(root, "OpenIntelligence/SDK/OpenIntelligenceEngine.swift", f"func c() {{\n{SIM}\nreturn .simulatorUnsupported\n#endif\n}}\n")
    if old_layout:
        write(root, "OpenIntelligence/Services/LLM/LLMService.swift", first)
        write(root, "OpenIntelligence/Services/RAG/Orchestration/RAGService.swift", device)
    else:
        write(root, "OpenIntelligence/Services/LLM/AppleFoundationLLMService.swift", first)
        write(root, "OpenIntelligence/Services/RAG/Orchestration/RAGService+Device.swift", device)
    write(root, pr.ANSWER_TEST, OLD_TEST if old_layout else MODE_TEST)
    write(root, "CHANGELOG.md", "## 9.9\n")


def quiet(function, *args, **kwargs):
    with contextlib.redirect_stdout(io.StringIO()) as out:
        result = function(*args, **kwargs)
    return result, out.getvalue()


class Staging(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix="paired-run-test."))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def path(self, *parts):
        return os.path.join(self.tmp, *parts)

    def test_a_copy_never_goes_into_the_repository_or_icloud(self):
        home = self.path("home")
        repo = os.path.join(home, "Documents", "GitHub", "App")
        os.makedirs(repo)
        check = lambda dest: pr.stage_dir_problem(dest, root=repo, home=home)
        self.assertIn("inside the repository", check(repo))
        self.assertIn("inside the repository", check(os.path.join(repo, "scratch")))
        self.assertIn("inside the repository", check(os.path.join(home, "Documents", "GitHub")))  # around it
        self.assertIn("iCloud", check(os.path.join(home, "Documents", "scratch")))
        self.assertEqual(check(self.path("scratch", "new")), "")  # not there yet: fine

    def test_a_folder_holding_something_else_is_refused(self):
        dest = self.path("dest")
        write(dest, "notes.txt", "mine")
        self.assertIn("give an empty folder", pr.stage_dir_problem(dest))
        write(dest, pr.MARKER, "patched")
        self.assertEqual(pr.stage_dir_problem(dest), "")  # an earlier patched copy may be replaced
        os.makedirs(self.path("empty"))
        self.assertEqual(pr.stage_dir_problem(self.path("empty")), "")

    def test_what_a_source_is(self):
        self.assertEqual(pr.source_kind("worktree"), ("tree", pr.ROOT))
        self.assertEqual(pr.source_kind("v5.7.0"), ("ref", "v5.7.0"))
        self.assertEqual(pr.source_kind(self.tmp), ("tree", self.tmp))
        self.assertEqual(pr.source_kind("origin/main"), ("ref", "origin/main"))  # a slash, but no such folder

    @unittest.skipUnless(shutil.which("rsync"), "rsync is not installed")
    def test_a_folder_is_copied_without_git_runs_or_secrets_and_patched(self):
        tree, dest = self.path("tree"), self.path("stage")
        make_tree(tree)
        for left_out in [".git/config", ".git.nosync/HEAD", ".build/x.o", "BenchmarkRuns/run/SUMMARY.md",
                         ".claude/worktrees/w/file.swift", ".env.appstore"]:
            write(tree, left_out, "x")
        write(tree, ".claude/rules/rule.md", "kept")
        staged, printed = quiet(pr.stage, tree, dest, pr.Shell(False))
        self.assertEqual(staged["patched_by"], "scripts/sim_model_copy.py")
        self.assertTrue(os.path.exists(os.path.join(dest, pr.MARKER)))  # what bench_answer_modes.sh checks
        self.assertTrue(os.path.exists(os.path.join(dest, ".claude", "rules", "rule.md")))
        for gone in [".git", ".git.nosync", ".build", "BenchmarkRuns", ".claude/worktrees", ".env.appstore"]:
            self.assertFalse(os.path.exists(os.path.join(dest, gone)), gone)
        patched = open(os.path.join(dest, "OpenIntelligence/Services/RAG/Orchestration/RAGService+Device.swift")).read()
        self.assertIn(pr.SIM_OFF, patched)
        self.assertIn(pr.CHIP_NEW, patched)
        self.assertNotIn(pr.SIM_OFF, open(os.path.join(tree, "OpenIntelligence/SDK/OpenIntelligenceEngine.swift")).read())
        self.assertIn("$ rsync -a --delete --exclude .git ", printed)
        # Again into the same folder: the copy is refreshed and patched once, not twice.
        quiet(pr.stage, tree, dest, pr.Shell(False))
        self.assertEqual(open(os.path.join(dest, "OpenIntelligence/SDK/OpenIntelligenceEngine.swift")).read().count(pr.SIM_OFF), 1)

    def test_an_old_ref_needs_a_newer_answer_test_and_is_patched_by_content(self):
        old, dest = self.path("old"), self.path("stage")
        make_tree(old, old_layout=True)
        extract = lambda ref, to: shutil.copytree(old, to, dirs_exist_ok=True)
        with mock.patch.object(pr, "extract_ref", extract), mock.patch.object(pr, "ref_file", lambda ref, path: MODE_TEST):
            with self.assertRaises(SystemExit) as stopped:
                quiet(pr.stage, "v-old", dest, pr.Shell(False))
            self.assertIn("--test-from", str(stopped.exception))
            self.assertFalse(os.path.exists(os.path.join(dest, pr.MARKER)))  # the bench script would refuse it
            # The stopped copy is this script's own, so the second try may replace it.
            staged, printed = quiet(pr.stage, "v-old", dest, pr.Shell(False), "newer")
        self.assertEqual(staged["test_from"], "newer")
        self.assertIn("found by content", staged["patched_by"])
        self.assertIn("patched by content: ", printed)
        self.assertEqual(open(os.path.join(dest, pr.ANSWER_TEST)).read(), MODE_TEST)
        self.assertTrue(os.path.exists(os.path.join(dest, pr.MARKER)))
        engine = open(os.path.join(dest, "OpenIntelligence/Services/RAG/Orchestration/RAGService.swift")).read()
        self.assertEqual((engine.count(pr.SIM_OFF), engine.count(pr.CHIP_NEW), engine.count(pr.CHIP_OLD)), (1, 1, 0))
        self.assertIn(pr.SIM_OFF, open(os.path.join(dest, "OpenIntelligence/Services/LLM/LLMService.swift")).read())
        self.assertNotIn(pr.SIM_OFF, open(os.path.join(old, "OpenIntelligence/Services/LLM/LLMService.swift")).read())

    def test_a_newer_answer_test_is_left_alone_when_the_copy_has_its_own(self):
        new, dest = self.path("new"), self.path("stage")
        make_tree(new)
        extract = lambda ref, to: shutil.copytree(new, to, dirs_exist_ok=True)
        with mock.patch.object(pr, "extract_ref", extract), mock.patch.object(pr, "ref_file", lambda ref, path: "other\n"):
            staged, _ = quiet(pr.stage, "v-new", dest, pr.Shell(False), "newer")
        self.assertIsNone(staged["test_from"])
        self.assertEqual(open(os.path.join(dest, pr.ANSWER_TEST)).read(), MODE_TEST)

    def test_patching_by_content_is_done_once_and_stops_on_a_missing_switch(self):
        tree = self.path("tree")
        make_tree(tree, old_layout=True)
        self.assertEqual(len(pr.patch_by_content(tree)), 3)
        self.assertEqual(pr.patch_by_content(tree), [])  # nothing left to change, nothing patched twice
        broken = self.path("broken")
        make_tree(broken, old_layout=True)
        write(broken, "OpenIntelligence/SDK/OpenIntelligenceEngine.swift", "func c() {}\n")
        with self.assertRaises(SystemExit) as stopped:
            pr.patch_by_content(broken)
        self.assertIn("return .simulatorUnsupported", str(stopped.exception))
        self.assertIn("0 times", str(stopped.exception))

    def test_the_switches_here_are_the_ones_sim_model_copy_patches(self):
        script = open(os.path.join(HERE, "sim_model_copy.py")).read()
        for text in pr.SWITCH_MARKERS + [pr.CHIP_OLD, pr.CHIP_NEW, pr.SIM_OFF, f'"{pr.MARKER}"']:
            self.assertIn(text, script)

    def test_the_bench_script_reads_what_pair_sets(self):
        bench = open(pr.BENCH).read()
        for variable in pr.bench_env("before", "x-before", "/scratch"):
            self.assertIn("${" + variable + ":-", bench)
        self.assertIn(f'[ -f "$STAGE/{pr.MARKER}" ]', bench)
        self.assertIn(f"-answer-modes${{NAME:+-$NAME}}", bench)  # the folder name run_folders() looks for


class Pairing(unittest.TestCase):
    def dry_run(self, *arguments):
        def ran(*args, **kwargs):
            raise AssertionError(f"a dry run ran something: {args}")
        scratch = os.path.join(tempfile.gettempdir(), "paired-run-test-never-made")
        out = io.StringIO()
        with mock.patch.object(pr.subprocess, "run", ran), mock.patch.object(pr.subprocess, "Popen", ran), \
                mock.patch.object(pr.os, "makedirs", ran), mock.patch.object(pr.shutil, "rmtree", ran), \
                contextlib.redirect_stdout(out):
            code = pr.main(["pair", *arguments, "--scratch", scratch, "--dry-run"])
        self.assertEqual(code, 0)
        self.assertFalse(os.path.exists(scratch))
        return out.getvalue(), scratch

    def test_a_dry_run_prints_every_command_and_runs_none(self):
        text, scratch = self.dry_run("--before", "v5.7.0", "--after", "worktree")
        commands = [l[2:] for l in text.splitlines() if l.startswith("$ ")]
        self.assertTrue(any(c.startswith("git -C ") and "archive v5.7.0 | tar -x -C " + scratch + "/before-stage" in c for c in commands))
        self.assertTrue(any(c.startswith("rsync -a --delete") and c.endswith(scratch + "/after-stage/") for c in commands))
        self.assertEqual(sum("sim_model_copy.py" in c for c in commands), 2)
        self.assertTrue(any(c == "pgrep -x xcodebuild" for c in commands))
        bench = [c for c in commands if "bench_answer_modes.sh" in c]
        self.assertEqual(len(bench), 2)
        self.assertIn(f"OI_BENCH_PRESTAGED={scratch}/before-stage OI_BENCH_NAME=pair-before OI_BENCH_SRC={scratch}/before-src "
                      f"OI_BENCH_DD={scratch}/before-dd OI_BENCH_SIM='OI pair before' bash ", bench[0])
        self.assertTrue(bench[0].endswith("bench_answer_modes.sh standard"))
        self.assertIn("OI_BENCH_NAME=pair-after ", bench[1])
        self.assertIn("compare BenchmarkRuns/<stamp>-answer-modes-pair-before BenchmarkRuns/<stamp>-answer-modes-pair-after", commands[-1])
        self.assertIn("DRY RUN", text)
        self.assertIn("BenchmarkRuns/LEDGER.md", text)
        self.assertIn("### ", text)
        self.assertIn("`<stamp>-answer-modes-pair-before`, `<stamp>-answer-modes-pair-after`", text)

    def test_repeats_alternate_and_never_share_a_name(self):
        text, _ = self.dry_run("--before", "HEAD", "--after", "HEAD", "--repeats", "2", "--mode", "standard,maximum", "--name", "noise")
        names = [part.split("=")[1] for l in text.splitlines() if "bench_answer_modes.sh" in l
                 for part in l.split() if part.startswith("OI_BENCH_NAME=")]
        self.assertEqual(names, ["noise-before-r1", "noise-after-r1", "noise-before-r2", "noise-after-r2"])
        self.assertIn("bench_answer_modes.sh standard maximum", text)
        self.assertIn("--noise BenchmarkRuns/<stamp>-answer-modes-noise-before-r2 --noise-after "
                      "BenchmarkRuns/<stamp>-answer-modes-noise-after-r2 --same-build", text)

    def test_each_side_has_its_own_copy_build_folder_and_simulator(self):
        before, after = pr.bench_env("before", "x-before", "/s"), pr.bench_env("after", "x-after", "/s")
        self.assertEqual(sorted(before), ["OI_BENCH_DD", "OI_BENCH_NAME", "OI_BENCH_PRESTAGED", "OI_BENCH_SIM", "OI_BENCH_SRC"])
        for variable in before:
            self.assertNotEqual(before[variable], after[variable], variable)

    def test_a_bad_mode_or_name_stops_before_anything(self):
        for arguments in (["--mode", "fast"], ["--name", "a b"], ["--name", "../x"], ["--repeats", "0"]):
            with self.assertRaises(SystemExit), contextlib.redirect_stdout(io.StringIO()):
                pr.main(["pair", "--before", "HEAD", "--after", "worktree", "--dry-run", *arguments])

    def test_the_ledger_lines_name_every_folder_and_carry_the_evidence_tag(self):
        text = pr.ledger_lines("2026-01-02", "bind", [("before", "`v1` (abc1234)"), ("after", "the working tree at def5678")],
                               ["standard"], 1, ["2026-01-02-0100-answer-modes-bind-before", "2026-01-02-0110-answer-modes-bind-after"],
                               "| Mode | Before |\n|---|---|")
        self.assertTrue(text.startswith('### 2026-01-02 Paired answer run "bind" (`2026-01-02-0100-answer-modes-bind-before`, '
                                        "`2026-01-02-0110-answer-modes-bind-after`)"))
        self.assertIn("before is `v1` (abc1234); after is the working tree at def5678", text.replace("\n", " "))
        self.assertIn("`[evidence_level: measured, confidence: low: one run per build]`", text)
        self.assertIn("noise was not measured", text.replace("\n", " "))
        self.assertIn("| Mode | Before |", text)
        self.assertIn("2 runs per build", pr.ledger_lines("2026-01-02", "bind", [], ["standard"], 2, [], ""))

    def real_run(self, bench, before="v1", after="v2"):
        """`pair` for real, with the staging, the git questions and the bench script replaced by stand-ins."""
        commits = {"v1": "abc1234", "v2": "def5678", "v2-again": "def5678"}
        answered = lambda *argv, **kw: mock.Mock(returncode=0, stdout="", stderr="")  # pgrep finds no xcodebuild
        staged = lambda source, dest, shell, test_from=None: {"patched_by": "scripts/sim_model_copy.py", "test_from": None}
        out = io.StringIO()
        with mock.patch.object(pr.Shell, "run", answered), mock.patch.object(pr, "stage", staged), \
                mock.patch.object(pr, "built_from", lambda source, shell: f"`{source}` ({commits[source]})"), \
                mock.patch.object(pr, "run_bench", bench), mock.patch.object(pr, "MIN_FREE_GIB", 0), \
                contextlib.redirect_stdout(out):
            code = pr.main(["pair", "--before", before, "--after", after, "--repeats", "2", "--name", "bind"])
        return code, out.getvalue()

    def test_a_pair_compares_the_folders_its_runs_made_and_prints_the_ledger_lines(self):
        made = []

        def bench(env, modes, shell, limit_hours):
            before = "before" in env["OI_BENCH_NAME"]
            right = answers("exact_capex") if before else answers("exact_capex", "exact_fuel_capacity", "multi_hop_project_m1")
            made.append(f"2026-01-02-01{len(made)}0-answer-modes-{env['OI_BENCH_NAME']}")
            make_run(pr.RUNS, made[-1], {"standard-app": right})
            return 0
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(pr, "RUNS", tmp):
            code, text = self.real_run(bench)
        self.assertEqual(code, 0)
        self.assertEqual([m.split("modes-")[1] for m in made], ["bind-before-r1", "bind-after-r1", "bind-before-r2", "bind-after-r2"])
        self.assertIn("  before  20% (1 of 5)", text)
        self.assertIn("  after   60% (3 of 5)", text)
        self.assertIn("(2 pairs of runs compared)", text)  # the two before runs, the two after runs
        self.assertIn("reading: larger than run-to-run noise", text)
        ledger = text[text.index("### "):]
        for folder in made:
            self.assertIn(f"`{folder}`", ledger)
        self.assertIn("| standard (app model) | 20% (1 of 5) | 60% (3 of 5) |", ledger)
        self.assertIn("before is `v1` (abc1234); after is `v2` (def5678)", ledger.replace("\n", " "))

    def test_two_names_for_one_commit_are_one_build_and_every_flip_is_noise(self):
        def bench(env, modes, shell, limit_hours):
            number = len(os.listdir(pr.RUNS))
            right = answers("exact_capex") if number % 2 else answers("exact_capex", "exact_fuel_capacity")
            make_run(pr.RUNS, f"2026-01-02-01{number}0-answer-modes-{env['OI_BENCH_NAME']}", {"standard-app": right})
            return 0
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(pr, "RUNS", tmp):
            code, text = self.real_run(bench, before="v2", after="v2-again")
        self.assertEqual(code, 0)
        self.assertIn(" --same-build", text)
        self.assertIn("Before and after are one build: every flip below is run-to-run noise.", text)
        self.assertIn("noise: at most 1 of 5 questions flipped between two runs of one build (6 pairs of runs compared)", text)
        self.assertIn("reading: within run-to-run noise", text)

    def test_a_run_that_fails_stops_the_pair_and_still_names_its_folders(self):
        def bench(env, modes, shell, limit_hours):
            if "after" in env["OI_BENCH_NAME"]:
                return 1  # the bench script stopped before making anything usable
            make_run(pr.RUNS, f"2026-01-02-0100-answer-modes-{env['OI_BENCH_NAME']}", {"standard-app": answers()})
            return 0
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(pr, "RUNS", tmp):
            code, text = self.real_run(bench)
        self.assertEqual(code, 1)
        self.assertIn('The after run "bind-after-r1" ended with exit 1 and made no run folder. The pair is incomplete.', text)
        self.assertIn("`2026-01-02-0100-answer-modes-bind-before-r1`", text[text.index("### "):])
        self.assertNotIn("bind-before-r2", text)  # nothing ran after the failure

    def test_run_folders_are_found_by_the_name_the_bench_script_gives_them(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(pr, "RUNS", tmp):
            for name in ["2026-01-02-0100-answer-modes-bind-before", "2026-01-02-0110-answer-modes-bind-after",
                         "2026-01-02-0120-answer-modes-rebind-before", "2026-01-02-0130-answer-modes-bind-before-r2"]:
                os.makedirs(os.path.join(tmp, name))
            self.assertEqual(pr.run_folders("bind-before"), {"2026-01-02-0100-answer-modes-bind-before"})


class Wording(unittest.TestCase):
    def test_no_long_dashes_in_either_file(self):
        for name in ("paired_run.py", "test_paired_run.py"):
            text = open(os.path.join(HERE, name), encoding="utf-8").read()
            self.assertNotIn(chr(0x2014), text, name)
            self.assertNotIn(chr(0x2013), text, name)


if __name__ == "__main__":
    unittest.main()
