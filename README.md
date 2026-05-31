# Skills

个人的 Claude Code Skill 集合，用于沉淀和复用各类专业化工作流程。

## 目录结构

```
skills/
├── <skill-name>/       # 每个 Skill 独立目录
│   └── SKILL.md        # Skill 定义文件
├── templates/          # 新 Skill 模板
│   └── SKILL.md.template
├── CLAUDE.md           # 本仓库的 Claude Code 配置
└── README.md
```

## 使用方式

将本仓库 clone 到本地后，把 `skills/` 目录软链接到 Claude Code 的 skills 目录：

```bash
# 全局可用
ln -s "$(pwd)/skills" ~/.claude/skills

# 或项目级可用
ln -s "$(pwd)/skills" <project>/.claude/skills
```

## 新增 Skill

1. 在 `skills/` 下创建以 kebab-case 命名的目录
2. 复制 `templates/SKILL.md.template` 为 `SKILL.md` 并修改内容
3. 提交 PR
