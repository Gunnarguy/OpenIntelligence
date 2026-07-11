import sys

file_path = "OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift"
with open(file_path, "r") as f:
    lines = f.readlines()
with open(file_path, "w") as f:
    for line in lines:
        if line.strip() == "picker.allowsMultipleSelection = true  // Enable multiple file selection" or line.strip() == "return picker":
            continue
        f.write(line)
