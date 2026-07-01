# Agent Delegation Guide for Claude Code

## When to Delegate to Agents (Not Do It Yourself)

This guide prevents the anti-pattern of manually generating large, structured content when a skill + agent is the correct approach.

---

## Rule of Thumb

**If a task involves generating >2,000 words of structured content with quality gates, delegate to an agent.**

---

## Specific Triggers

### ✅ MUST Delegate (Use Agent Tool)

1. **k8s-homework-generator skill invoked**
   - User says: "Generate the assignment", "Create the homework files", "Build the tutorial"
   - What to do: Spawn agent with prompt referencing the skill
   - ❌ Do NOT: Start writing `tutorial.md` content yourself

2. **Multi-file generation with cross-file dependencies**
   - Example: 4 files that must be consistent (README, tutorial, homework, answers)
   - What to do: Let agent read all reference files and generate all outputs
   - ❌ Do NOT: Generate files sequentially yourself

3. **Complex quality gates**
   - Example: "Tutorial must use narrative paragraph flow, document spec fields with failure modes, show imperative + declarative forms"
   - What to do: Agent reads base-template.md and applies gates
   - ❌ Do NOT: Try to remember and apply 50+ quality checks yourself

4. **Content requiring deep reference material**
   - Example: Skills with 500+ line reference files (base-template.md)
   - What to do: Agent loads references fresh and applies them systematically
   - ❌ Do NOT: Skim references and hope you got the details right

### ✅ Can Do Yourself (No Agent Needed)

1. **Single-file edits**
   - Example: Update one section of CLAUDE.md, fix a typo, add one exercise
   
2. **Small generation tasks (<500 words)**
   - Example: Write a 2-paragraph summary, create a small config file

3. **Quick fixes with no quality gates**
   - Example: Rename a file, update a version number, fix broken link

---

## Correct Execution Pattern

### User Request
```
"Generate troubleshooting assignment-3 with hands-on kubelet breaking exercises"
```

### ✅ CORRECT: Delegate to Agent
```
1. Update/verify prompt.md exists in target directory
2. Invoke Agent tool:
   - description: "Generate troubleshooting assignment-3"
   - prompt: "Generate assignment using k8s-homework-generator skill.
             Location: exercises/19-troubleshooting/assignment-3/
             Prompt file: prompt.md
             Generate all 4 files following base template conventions."
3. Wait for agent to complete
4. Summarize results to user
```

### ❌ INCORRECT: Do It Yourself
```
1. Read base-template.md
2. Read prompt.md
3. Start writing: "# Tutorial..."
4. Get halfway through tutorial, realize it's 10,000 words
5. Run out of context
6. Incomplete generation, quality gates not checked
```

---

## Why This Matters

**Agent advantages:**
- Fresh context window for large generation tasks
- Can load 500+ line reference files without polluting your context
- Applies quality gates systematically across all outputs
- Generates all 4 files atomically (no partial outputs)

**Doing it yourself disadvantages:**
- Your context window gets filled with reference material
- Quality gate checking becomes manual and error-prone
- Partial generations if you run out of context mid-task
- Inconsistencies between files (tutorial uses pattern X, homework uses pattern Y)

---

## How to Catch Yourself

**Warning signs you should delegate instead:**
- You just read a 500+ line reference file
- You're about to write "# Tutorial..." for a homework assignment
- You're thinking "I'll generate the tutorial first, then the homework..."
- The task has phrases like "following the base template" or "quality gates"

**When you catch these, STOP and spawn an agent instead.**

---

## Examples from This Project

### ✅ Correctly Delegated
- **CoreDNS assignment-4**: User invoked skill → Agent generated 4 files → Success
- **Troubleshooting assignment-3**: User asked for regeneration → Agent generated 4 files → Success

### ❌ Incorrectly Done Manually (Then Fixed)
- **Troubleshooting assignment-3 (first attempt)**: Started writing tutorial manually → Realized mid-way → Stopped, deleted, spawned agent → Success

---

## Quick Decision Tree

```
User asks to generate assignment
    ↓
Is this a k8s-homework-generator skill task?
    ↓ YES
Will this be >2,000 words?
    ↓ YES
Does it have quality gates?
    ↓ YES
    ↓
✅ DELEGATE TO AGENT
    ↓
Agent(description="...", prompt="Use k8s-homework-generator skill...")
```

---

## Update Log

- 2026-06-27: Created after manually writing tutorial instead of delegating to agent
- Added to prevent repeating the "start writing inline then realize it should be an agent" pattern
