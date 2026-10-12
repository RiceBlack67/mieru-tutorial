# 仓库约定

## 提交与推送

- 所有提交的作者和提交者都使用 `Claude <noreply@anthropic.com>`，不要加 `Co-Authored-By` 等共同作者行。
- 改动直接推送到 `main`，不要通过 GitHub 网页或 API 合并 PR。

## 内容

- `install.sh` 的改动要在干净的 Debian / Ubuntu 上实测通过再推送；README 里的安装命令直接从 `main` 拉这个脚本。

## 修改 CLAUDE.md

- 修改 CLAUDE.md 前，先把要改的完整内容给仓库主人看，得到明确同意后再提交和推送。
