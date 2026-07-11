import re
import sys

with open("OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift", "r") as f:
    content = f.read()

# Let's write a simple python script to balance braces for computeAnswerRelevance
def get_braces():
    lines = content.split('\n')
    balance = 0
    in_func = False
    for i, line in enumerate(lines):
        if "private func computeAnswerRelevance" in line:
            in_func = True

        if in_func:
            balance += line.count("{")
            balance -= line.count("}")
            if balance == 0 and "{" in line: # actually first `{` will make it >0
                pass
            if in_func and balance == 0 and "{" not in line and "}" in line:
                print(f"Ends at line {i+1}")
                in_func = False

get_braces()
