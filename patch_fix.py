import re

with open("OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift", "r") as f:
    content = f.read()

content = content.replace(r'#"[A-Z]{2,}[\\s-]?\\d+"#', r'#"[A-Z]{2,}[\s-]?\d+"#')

with open("OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift", "w") as f:
    f.write(content)

print("Done")
