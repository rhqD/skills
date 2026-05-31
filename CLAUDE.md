# 技能仓库指南

这是一个个人的 Skill 集合仓库，用于在 Claude Code 中复用专业化的工作流程。

## 仓库结构

- `skills/` — 所有 Skill 定义，每个 Skill 有独立目录，目录名即为 Skill 名称（kebab-case）
- `templates/` — 创建新 Skill 时的模板文件

## Skill 格式

每个 Skill 是一个目录，包含一个 `SKILL.md` 文件。`SKILL.md` 使用 YAML frontmatter + Markdown 正文：

```markdown
---
name: <skill-name>
description: <简短描述，用于自动匹配触发>
allowed-tools: [Read, Write, Bash, ...]
---

# Instructions
...
```

## 如何新增 Skill

1. 在 `skills/` 下创建新目录（以 kebab-case 命名）
2. 参考 `templates/SKILL.md.template` 编写 `SKILL.md`
3. 提交并推送到远程仓库

## 如何使用

将 `skills/` 目录软链接或复制到 `~/.claude/skills/`（全局可用）或项目中的 `.claude/skills/`（项目级可用）。
